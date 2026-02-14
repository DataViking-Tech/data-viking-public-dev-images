#!/usr/bin/env python3
"""
Slack notification utilities for AI coding agents.

Provides:
- SlackConfig loading (secrets/config/env)
- Rate limiting (30 req/60s)
- SlackNotifier.send() interface
- Secrets file initialization
"""

import os
import re
import stat
import sys
import logging
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

try:
    import requests
    import yaml
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install requests pyyaml")
    sys.exit(1)

REQUIRED_FILE_MODE = 0o600  # rw-------
RATE_LIMIT_MAX = 30
RATE_LIMIT_WINDOW = 60

BASE_DIR_ENV = "AI_CODING_UTILS_BASE"


def _get_base_dir() -> Path:
    env_base = os.environ.get(BASE_DIR_ENV)
    return Path(env_base) if env_base else Path.cwd()


def get_beads_dir(base_dir: Optional[Path] = None) -> Path:
    base = Path(base_dir) if base_dir else _get_base_dir()
    return base / ".beads"


def get_secrets_file(base_dir: Optional[Path] = None) -> Path:
    base = Path(base_dir) if base_dir else _get_base_dir()
    return base / ".secrets" / "slack_webhook"


def get_config_file(base_dir: Optional[Path] = None) -> Path:
    return get_beads_dir(base_dir) / "slack_config.yaml"


class SensitiveDataFilter(logging.Filter):
    """Filter to mask webhook URLs and other sensitive data in logs."""

    WEBHOOK_PATTERN = re.compile(r'https://hooks\.slack\.com/services/[A-Za-z0-9/]+')

    def filter(self, record):
        if isinstance(record.msg, str):
            record.msg = self.WEBHOOK_PATTERN.sub('[WEBHOOK_URL_MASKED]', record.msg)
        if record.args:
            args = []
            for arg in record.args:
                if isinstance(arg, str):
                    arg = self.WEBHOOK_PATTERN.sub('[WEBHOOK_URL_MASKED]', arg)
                args.append(arg)
            record.args = tuple(args)
        return True


logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()],
)
logger = logging.getLogger(__name__)
logger.addFilter(SensitiveDataFilter())


def mask_url(url: str) -> str:
    """Mask a webhook URL for display."""
    if not url:
        return "(not set)"
    if "hooks.slack.com" in url:
        parts = url.split("/")
        if len(parts) >= 5:
            return f"https://hooks.slack.com/services/{parts[-3][:4]}.../{parts[-1][-4:]}"
    return url[:20] + "..." if len(url) > 20 else url


def sanitize_for_slack(text: str, max_length: int = 3000) -> str:
    """Sanitize text for safe inclusion in Slack messages."""
    if not text:
        return ""

    if len(text) > max_length:
        text = text[:max_length - 3] + "..."

    text = text.replace("&", "&amp;")
    text = text.replace("<", "&lt;")
    text = text.replace(">", "&gt;")
    text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', text)

    return text


def enforce_file_permissions(path: Path, mode: int = REQUIRED_FILE_MODE) -> bool:
    """Ensure file has restricted permissions. Returns True if permissions changed."""
    if not path.exists():
        return False

    current_mode = stat.S_IMODE(os.stat(path).st_mode)
    if current_mode != mode:
        try:
            os.chmod(path, mode)
            logger.info(f"Set permissions on {path.name} to {oct(mode)}")
            return True
        except OSError as e:
            logger.warning(f"Could not set permissions on {path}: {e}")
    return False


class RateLimiter:
    """Simple sliding window rate limiter."""

    def __init__(self, max_requests: int = RATE_LIMIT_MAX, window_seconds: int = RATE_LIMIT_WINDOW):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.requests: deque = deque()

    def allow(self) -> bool:
        """Check if a request is allowed under the rate limit."""
        now = os.times().elapsed if hasattr(os.times(), 'elapsed') else __import__('time').time()
        while self.requests and self.requests[0] < now - self.window_seconds:
            self.requests.popleft()
        if len(self.requests) >= self.max_requests:
            return False
        self.requests.append(now)
        return True

    def get_stats(self) -> dict:
        now = os.times().elapsed if hasattr(os.times(), 'elapsed') else __import__('time').time()
        while self.requests and self.requests[0] < now - self.window_seconds:
            self.requests.popleft()
        return {
            "requests_in_window": len(self.requests),
            "max_requests": self.max_requests,
            "window_seconds": self.window_seconds,
        }


@dataclass
class SlackConfig:
    """Configuration for Slack notifications."""
    webhook_url: str = ""
    channel: Optional[str] = None
    notify_created: bool = True
    notify_in_progress: bool = True
    notify_closed: bool = True
    notify_agent_complete: bool = True
    notify_review_request: bool = True

    @classmethod
    def load(cls, config_path: Optional[Path] = None, base_dir: Optional[Path] = None) -> "SlackConfig":
        """Load configuration from YAML file and/or secrets."""
        config = cls()
        secrets_file = get_secrets_file(base_dir)

        if secrets_file.exists():
            try:
                current_mode = stat.S_IMODE(os.stat(secrets_file).st_mode)
                if current_mode != REQUIRED_FILE_MODE:
                    logger.warning(f"Secrets file has insecure permissions ({oct(current_mode)}), fixing...")
                    enforce_file_permissions(secrets_file)

                webhook_url = secrets_file.read_text().strip()
                if webhook_url:
                    config.webhook_url = webhook_url
                    logger.info("Loaded webhook URL from secrets file")
            except Exception as e:
                logger.error(f"Failed to read secrets file: {e}")

        config_path = config_path or get_config_file(base_dir)
        if config_path.exists():
            enforce_file_permissions(config_path)
            try:
                with open(config_path) as f:
                    data = yaml.safe_load(f) or {}
            except Exception as e:
                logger.error(f"Failed to load config: {e}")
                return config

            if not config.webhook_url:
                webhook_url = data.get("webhook_url", "")
                if webhook_url.startswith("${") and webhook_url.endswith("}"):
                    env_var = webhook_url[2:-1]
                    webhook_url = os.environ.get(env_var, "")
                config.webhook_url = webhook_url

            config.channel = data.get("channel")

            notify_on = data.get("notify_on", {})
            if isinstance(notify_on, dict):
                config.notify_created = notify_on.get("created", True)
                config.notify_in_progress = notify_on.get("in_progress", True)
                config.notify_closed = notify_on.get("closed", True)
                config.notify_agent_complete = notify_on.get("agent_complete", True)
                config.notify_review_request = notify_on.get("review_request", True)
            elif isinstance(notify_on, list):
                config.notify_created = "created" in notify_on
                config.notify_in_progress = "in_progress" in notify_on
                config.notify_closed = "closed" in notify_on
                config.notify_agent_complete = "agent_complete" in notify_on
                config.notify_review_request = "review_request" in notify_on

        if not config.webhook_url:
            config.webhook_url = os.environ.get("SLACK_WEBHOOK_URL", "")

        return config


class SlackNotifier:
    """Sends notifications to Slack with rate limiting and sanitization."""

    def __init__(self, config: SlackConfig):
        self.config = config
        self.rate_limiter = RateLimiter()

    def send(self, text: str, blocks: Optional[list] = None) -> bool:
        """Send a message to Slack."""
        if not self.config.webhook_url:
            logger.warning("No webhook URL configured - skipping notification")
            return False

        if not self.rate_limiter.allow():
            stats = self.rate_limiter.get_stats()
            logger.warning(
                f"Rate limit exceeded ({stats['requests_in_window']}/{stats['max_requests']} in {stats['window_seconds']}s)"
            )
            return False

        text = sanitize_for_slack(text)

        payload = {"text": text}
        if blocks:
            payload["blocks"] = blocks
        if self.config.channel:
            payload["channel"] = self.config.channel

        try:
            response = requests.post(
                self.config.webhook_url,
                json=payload,
                timeout=10,
            )
            if response.status_code == 200:
                logger.info(f"Sent notification: {text[:50]}...")
                return True
            logger.error(f"Slack API error: HTTP {response.status_code}")
            return False
        except requests.exceptions.Timeout:
            logger.error("Slack API timeout")
            return False
        except requests.exceptions.RequestException as e:
            error_msg = str(e)
            error_msg = re.sub(r'https://hooks\.slack\.com/services/[A-Za-z0-9/]+', '[MASKED]', error_msg)
            logger.error(f"Failed to send Slack notification: {error_msg}")
            return False


def get_webhook_url(base_dir: Optional[Path] = None, config_path: Optional[Path] = None) -> Optional[str]:
    """Get webhook URL from secrets file, config file, or environment."""
    secrets_file = get_secrets_file(base_dir)
    if secrets_file.exists():
        try:
            current_mode = stat.S_IMODE(os.stat(secrets_file).st_mode)
            if current_mode != REQUIRED_FILE_MODE:
                print(f"Warning: Secrets file has insecure permissions ({oct(current_mode)})", file=sys.stderr)
            webhook_url = secrets_file.read_text().strip()
            if webhook_url and not webhook_url.startswith("#"):
                return webhook_url
        except Exception:
            pass

    env_url = os.environ.get("SLACK_WEBHOOK_URL")
    if env_url:
        return env_url

    config_path = config_path or get_config_file(base_dir)
    if config_path.exists():
        try:
            with open(config_path) as f:
                data = yaml.safe_load(f) or {}
                webhook_url = data.get("webhook_url", "")
                if webhook_url.startswith("${") and webhook_url.endswith("}"):
                    env_var = webhook_url[2:-1]
                    return os.environ.get(env_var, "")
                return webhook_url if webhook_url else None
        except Exception:
            pass

    return None


def init_secrets_file(base_dir: Optional[Path] = None) -> bool:
    """Initialize the secrets file with proper permissions."""
    secrets_file = get_secrets_file(base_dir)
    secrets_dir = secrets_file.parent

    if not secrets_dir.exists():
        try:
            secrets_dir.mkdir(parents=True, mode=0o700)
            print(f"Created secrets directory: {secrets_dir}")
        except Exception as e:
            print(f"Failed to create secrets directory: {e}")
            return False

    if secrets_file.exists():
        print(f"Secrets file already exists: {secrets_file}")
        enforce_file_permissions(secrets_file)
        return True

    try:
        secrets_file.write_text("# Paste your Slack webhook URL here (replace this line)\n")
        os.chmod(secrets_file, REQUIRED_FILE_MODE)
        print(f"Created secrets file: {secrets_file}")
        print("\nNext steps:")
        print(f"  1. Edit {secrets_file}")
        print("  2. Replace the placeholder with your Slack webhook URL")
        return True
    except Exception as e:
        print(f"Failed to create secrets file: {e}")
        return False
