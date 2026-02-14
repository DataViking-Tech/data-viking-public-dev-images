#!/usr/bin/env python3
"""
Beads Slack Notifier - Watches issues.jsonl and sends Slack notifications on state changes.

This daemon monitors the beads issue tracking system and alerts via Slack when:
1. A bead is created
2. A bead moves to `in_progress`
3. A bead is completed (`closed`)
4. All issues for an assignee are completed

Security hardening:
- Webhook URL never logged (masked in all output)
- Config files automatically set to mode 600
- Rate limiting (max 30 notifications/minute)
- Input sanitization for Slack messages
- Secrets file support with strict permissions

Usage:
    python beads_slack_notifier.py --daemon           # Run as background daemon
    python beads_slack_notifier.py --foreground      # Run in foreground (for debugging)
    python beads_slack_notifier.py --check           # Check config and exit
    python beads_slack_notifier.py --init-secret     # Initialize secrets file
"""

import argparse
import json
import logging
import os
import re
import signal
import stat
import sys
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional

try:
    import requests
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler, FileModifiedEvent
    import yaml
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install watchdog requests pyyaml")
    sys.exit(1)

BASE_DIR_ENV = "AI_CODING_UTILS_BASE"


def _get_base_dir() -> Path:
    env_base = os.environ.get(BASE_DIR_ENV)
    return Path(env_base) if env_base else Path.cwd()


# Configuration
DEFAULT_BEADS_DIR = _get_base_dir() / ".beads"
DEFAULT_ISSUES_FILE = DEFAULT_BEADS_DIR / "issues.jsonl"
DEFAULT_CONFIG_FILE = DEFAULT_BEADS_DIR / "slack_config.yaml"
SECRETS_FILE = _get_base_dir() / ".secrets" / "slack_webhook"
PID_FILE = DEFAULT_BEADS_DIR / "slack_notifier.pid"
LOG_FILE = DEFAULT_BEADS_DIR / "slack_notifier.log"
STATE_FILE = DEFAULT_BEADS_DIR / "slack_notifier_state.json"

# Security settings
REQUIRED_FILE_MODE = 0o600  # rw-------
RATE_LIMIT_MAX = 30  # Max notifications per window
RATE_LIMIT_WINDOW = 60  # Window in seconds

# Setup logging with custom filter to mask sensitive data
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
    handlers=[
        logging.StreamHandler(),
    ]
)
logger = logging.getLogger(__name__)
logger.addFilter(SensitiveDataFilter())


def mask_url(url: str) -> str:
    """Mask a webhook URL for display."""
    if not url:
        return "(not set)"
    if "hooks.slack.com" in url:
        # Show just enough to identify it
        parts = url.split("/")
        if len(parts) >= 5:
            return f"https://hooks.slack.com/services/{parts[-3][:4]}.../{parts[-1][-4:]}"
    return url[:20] + "..." if len(url) > 20 else url


def enforce_file_permissions(path: Path, mode: int = REQUIRED_FILE_MODE) -> bool:
    """Ensure file has restricted permissions. Returns True if permissions were changed."""
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


def sanitize_for_slack(text: str, max_length: int = 3000) -> str:
    """Sanitize text for safe inclusion in Slack messages."""
    if not text:
        return ""

    # Truncate to max length
    if len(text) > max_length:
        text = text[:max_length - 3] + "..."

    # Escape special Slack characters that could be used for injection
    # < > & are meaningful in Slack's mrkdwn
    text = text.replace("&", "&amp;")
    text = text.replace("<", "&lt;")
    text = text.replace(">", "&gt;")

    # Remove any potential control characters
    text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', text)

    return text


class RateLimiter:
    """Simple sliding window rate limiter."""

    def __init__(self, max_requests: int = RATE_LIMIT_MAX, window_seconds: int = RATE_LIMIT_WINDOW):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.requests: deque = deque()

    def allow(self) -> bool:
        """Check if a request is allowed under the rate limit."""
        now = time.time()

        # Remove old requests outside the window
        while self.requests and self.requests[0] < now - self.window_seconds:
            self.requests.popleft()

        if len(self.requests) >= self.max_requests:
            return False

        self.requests.append(now)
        return True

    def get_stats(self) -> dict:
        """Get current rate limiter stats."""
        now = time.time()
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
    def load(cls, config_path: Path) -> "SlackConfig":
        """Load configuration from YAML file and/or secrets."""
        config = cls()

        # Try to load webhook URL from secrets file first (most secure)
        if SECRETS_FILE.exists():
            try:
                # Verify permissions
                current_mode = stat.S_IMODE(os.stat(SECRETS_FILE).st_mode)
                if current_mode != REQUIRED_FILE_MODE:
                    logger.warning(f"Secrets file has insecure permissions ({oct(current_mode)}), fixing...")
                    enforce_file_permissions(SECRETS_FILE)

                webhook_url = SECRETS_FILE.read_text().strip()
                if webhook_url:
                    config.webhook_url = webhook_url
                    logger.info("Loaded webhook URL from secrets file")
            except Exception as e:
                logger.error(f"Failed to read secrets file: {e}")

        # Load config file
        if config_path.exists():
            # Enforce permissions on config file
            enforce_file_permissions(config_path)

            try:
                with open(config_path) as f:
                    data = yaml.safe_load(f) or {}
            except Exception as e:
                logger.error(f"Failed to load config: {e}")
                return config

            # Only use webhook from config if not already loaded from secrets
            if not config.webhook_url:
                webhook_url = data.get("webhook_url", "")
                if webhook_url.startswith("${") and webhook_url.endswith("}"):
                    env_var = webhook_url[2:-1]
                    webhook_url = os.environ.get(env_var, "")
                config.webhook_url = webhook_url

            config.channel = data.get("channel")

            # Parse notify_on settings
            notify_on = data.get("notify_on", {})
            if isinstance(notify_on, dict):
                config.notify_created = notify_on.get("created", True)
                config.notify_in_progress = notify_on.get("in_progress", True)
                config.notify_closed = notify_on.get("closed", True)
                config.notify_agent_complete = notify_on.get("agent_complete", True)
                config.notify_review_request = notify_on.get("review_request", True)
            elif isinstance(notify_on, list):
                # Legacy list format
                config.notify_created = "created" in notify_on
                config.notify_in_progress = "in_progress" in notify_on
                config.notify_closed = "closed" in notify_on
                config.notify_agent_complete = "agent_complete" in notify_on
                config.notify_review_request = "review_request" in notify_on

        # Fall back to environment variable
        if not config.webhook_url:
            config.webhook_url = os.environ.get("SLACK_WEBHOOK_URL", "")

        return config


@dataclass
class Issue:
    """Represents a beads issue."""
    id: str
    title: str
    status: str
    priority: int = 2
    issue_type: str = "task"
    owner: str = ""
    assignee: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    closed_at: Optional[str] = None
    close_reason: Optional[str] = None
    comments: list = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict) -> "Issue":
        """Create Issue from dictionary."""
        return cls(
            id=data.get("id", ""),
            title=data.get("title", ""),
            status=data.get("status", "open"),
            priority=data.get("priority", 2),
            issue_type=data.get("issue_type", "task"),
            owner=data.get("owner", ""),
            assignee=data.get("assignee"),
            created_at=data.get("created_at"),
            updated_at=data.get("updated_at"),
            closed_at=data.get("closed_at"),
            close_reason=data.get("close_reason"),
            comments=data.get("comments", []),
        )

    def get_assigned_agent(self) -> Optional[str]:
        """Extract assigned agent from comments or assignee field."""
        # First check explicit assignee field
        if self.assignee:
            return self.assignee

        # Then check comments for @assigned convention
        for comment in reversed(self.comments):  # Most recent first
            text = comment.get("text", "")
            match = re.search(r"@assigned\s+(\S+)", text)
            if match:
                return match.group(1)

        return None


class NotifierState:
    """Manages persistent state for the notifier."""

    def __init__(self, state_path: Path):
        self.state_path = state_path
        self.previous_issues: dict[str, dict] = {}
        self.assignee_issues: dict[str, set] = {}  # assignee -> set of issue IDs
        self.load()

    def load(self):
        """Load state from file."""
        if self.state_path.exists():
            try:
                with open(self.state_path) as f:
                    data = json.load(f)
                    self.previous_issues = data.get("previous_issues", {})
                    # Convert lists back to sets
                    self.assignee_issues = {
                        k: set(v) for k, v in data.get("assignee_issues", {}).items()
                    }
            except Exception as e:
                logger.error(f"Failed to load state: {e}")

    def save(self):
        """Save state to file."""
        try:
            data = {
                "previous_issues": self.previous_issues,
                # Convert sets to lists for JSON
                "assignee_issues": {k: list(v) for k, v in self.assignee_issues.items()},
            }
            with open(self.state_path, "w") as f:
                json.dump(data, f, indent=2)
            # Protect state file
            enforce_file_permissions(self.state_path)
        except Exception as e:
            logger.error(f"Failed to save state: {e}")

    def update_assignee_tracking(self, issue: Issue, old_status: Optional[str]):
        """Update assignee tracking when issue status changes."""
        agent = issue.get_assigned_agent()
        if not agent:
            return

        if agent not in self.assignee_issues:
            self.assignee_issues[agent] = set()

        if issue.status == "closed":
            # Remove from tracking
            self.assignee_issues[agent].discard(issue.id)
        elif issue.status in ("open", "in_progress"):
            # Add to tracking
            self.assignee_issues[agent].add(issue.id)

    def get_open_issues_for_assignee(self, agent: str) -> set:
        """Get all open issues for an assignee."""
        return self.assignee_issues.get(agent, set())


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

        # Check rate limit
        if not self.rate_limiter.allow():
            stats = self.rate_limiter.get_stats()
            logger.warning(f"Rate limit exceeded ({stats['requests_in_window']}/{stats['max_requests']} in {stats['window_seconds']}s)")
            return False

        # Sanitize text
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
                # Log without the URL
                logger.info(f"Sent notification: {text[:50]}...")
                return True
            else:
                # Don't log the response body as it might contain URL info
                logger.error(f"Slack API error: HTTP {response.status_code}")
                return False
        except requests.exceptions.Timeout:
            logger.error("Slack API timeout")
            return False
        except requests.exceptions.RequestException as e:
            # Sanitize error message to avoid leaking URL
            error_msg = str(e)
            error_msg = re.sub(r'https://hooks\.slack\.com/services/[A-Za-z0-9/]+', '[MASKED]', error_msg)
            logger.error(f"Failed to send Slack notification: {error_msg}")
            return False

    def notify_created(self, issue: Issue):
        """Send notification for new issue."""
        if not self.config.notify_created:
            return

        agent = issue.get_assigned_agent()
        agent_text = f"\n   Assigned to: {sanitize_for_slack(agent)}" if agent else ""
        priority_text = f"P{issue.priority}"

        safe_title = sanitize_for_slack(issue.title, 200)
        safe_id = sanitize_for_slack(issue.id, 100)

        text = f"Issue Created: {safe_id}\n   \"{safe_title}\"{agent_text}\n   Priority: {priority_text}"

        blocks = [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f":new: *Issue Created:* `{safe_id}`\n\"{safe_title}\""
                }
            },
            {
                "type": "context",
                "elements": [
                    {"type": "mrkdwn", "text": f"*Priority:* {priority_text}"},
                    {"type": "mrkdwn", "text": f"*Type:* {sanitize_for_slack(issue.issue_type, 50)}"},
                ]
            }
        ]

        if agent:
            blocks[1]["elements"].append({"type": "mrkdwn", "text": f"*Assigned to:* {sanitize_for_slack(agent, 100)}"})

        self.send(text, blocks)

    def notify_in_progress(self, issue: Issue):
        """Send notification when work starts."""
        if not self.config.notify_in_progress:
            return

        agent = issue.get_assigned_agent()
        agent_text = f"\n   Agent: {sanitize_for_slack(agent)}" if agent else ""

        safe_title = sanitize_for_slack(issue.title, 200)
        safe_id = sanitize_for_slack(issue.id, 100)

        text = f"Work Started: {safe_id}\n   \"{safe_title}\"{agent_text}"

        blocks = [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f":arrow_forward: *Work Started:* `{safe_id}`\n\"{safe_title}\""
                }
            },
        ]

        if agent:
            blocks.append({
                "type": "context",
                "elements": [{"type": "mrkdwn", "text": f"*Agent:* {sanitize_for_slack(agent, 100)}"}]
            })

        self.send(text, blocks)

    def notify_closed(self, issue: Issue):
        """Send notification when issue is completed."""
        if not self.config.notify_closed:
            return

        agent = issue.get_assigned_agent()
        agent_text = f"\n   Agent: {sanitize_for_slack(agent)}" if agent else ""

        safe_title = sanitize_for_slack(issue.title, 200)
        safe_id = sanitize_for_slack(issue.id, 100)
        safe_reason = sanitize_for_slack(issue.close_reason, 200) if issue.close_reason else None

        # Calculate duration if we have timestamps
        duration_text = ""
        if issue.created_at and issue.closed_at:
            try:
                created = datetime.fromisoformat(issue.created_at.replace("Z", "+00:00"))
                closed = datetime.fromisoformat(issue.closed_at.replace("Z", "+00:00"))
                duration = closed - created
                hours = duration.total_seconds() / 3600
                if hours < 1:
                    duration_text = f"\n   Duration: {int(duration.total_seconds() / 60)}m"
                elif hours < 24:
                    duration_text = f"\n   Duration: {hours:.1f}h"
                else:
                    duration_text = f"\n   Duration: {duration.days}d {int(hours % 24)}h"
            except Exception:
                pass

        text = f"Completed: {safe_id}\n   \"{safe_title}\"{duration_text}{agent_text}"

        blocks = [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f":white_check_mark: *Completed:* `{safe_id}`\n\"{safe_title}\""
                }
            },
        ]

        context_elements = []
        if duration_text:
            context_elements.append({"type": "mrkdwn", "text": f"*Duration:* {duration_text.strip().replace('Duration: ', '')}"})
        if agent:
            context_elements.append({"type": "mrkdwn", "text": f"*Agent:* {sanitize_for_slack(agent, 100)}"})

        if context_elements:
            blocks.append({"type": "context", "elements": context_elements})

        if safe_reason:
            blocks.append({
                "type": "context",
                "elements": [{"type": "mrkdwn", "text": f"_{safe_reason}_"}]
            })

        self.send(text, blocks)

    def notify_agent_complete(self, agent: str, closed_issues: list[Issue]):
        """Send notification when all issues for an agent are done."""
        if not self.config.notify_agent_complete:
            return

        safe_agent = sanitize_for_slack(agent, 100)
        issue_list = "\n".join([
            f"   - {sanitize_for_slack(i.id, 50)}: {sanitize_for_slack(i.title, 50)}"
            for i in closed_issues[:10]
        ])
        if len(closed_issues) > 10:
            issue_list += f"\n   ... and {len(closed_issues) - 10} more"

        text = f"Agent Completed All Work\n   Agent: {safe_agent}\n   Issues closed: {len(closed_issues)}\n{issue_list}"

        blocks = [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f":tada: *Agent Completed All Work*\n*Agent:* {safe_agent}\n*Issues closed:* {len(closed_issues)}"
                }
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "\n".join([
                        f"- `{sanitize_for_slack(i.id, 50)}`: {sanitize_for_slack(i.title, 50)}"
                        for i in closed_issues[:5]
                    ])
                }
            }
        ]

        if len(closed_issues) > 5:
            blocks.append({
                "type": "context",
                "elements": [{"type": "mrkdwn", "text": f"_...and {len(closed_issues) - 5} more_"}]
            })

        self.send(text, blocks)


def parse_issues_jsonl(path: Path) -> dict[str, Issue]:
    """Parse issues.jsonl file into a dictionary of issues."""
    issues = {}

    if not path.exists():
        return issues

    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    issue = Issue.from_dict(data)
                    issues[issue.id] = issue
                except json.JSONDecodeError as e:
                    logger.warning(f"Failed to parse JSONL line: {e}")
    except Exception as e:
        logger.error(f"Failed to read issues file: {e}")

    return issues


class IssueFileHandler(FileSystemEventHandler):
    """Handles file system events for the issues.jsonl file."""

    def __init__(self, notifier: SlackNotifier, state: NotifierState, issues_path: Path):
        self.notifier = notifier
        self.state = state
        self.issues_path = issues_path
        self.last_process_time = 0
        self.debounce_seconds = 1.0  # Minimum time between processing

    def on_modified(self, event):
        """Handle file modification events."""
        if not isinstance(event, FileModifiedEvent):
            return

        if Path(event.src_path).name != self.issues_path.name:
            return

        # Debounce rapid file changes
        now = time.time()
        if now - self.last_process_time < self.debounce_seconds:
            return
        self.last_process_time = now

        self.process_changes()

    def process_changes(self):
        """Process changes in the issues file."""
        current_issues = parse_issues_jsonl(self.issues_path)

        for issue_id, issue in current_issues.items():
            prev = self.state.previous_issues.get(issue_id)

            if prev is None:
                # New issue
                logger.info(f"New issue detected: {issue_id}")
                self.notifier.notify_created(issue)
                self.state.update_assignee_tracking(issue, None)
            elif prev.get("status") != issue.status:
                # Status change
                old_status = prev.get("status")
                logger.info(f"Status change: {issue_id} {old_status} -> {issue.status}")

                if issue.status == "in_progress" and old_status != "in_progress":
                    self.notifier.notify_in_progress(issue)
                elif issue.status == "closed" and old_status != "closed":
                    self.notifier.notify_closed(issue)

                    # Check if agent completed all work
                    agent = issue.get_assigned_agent()
                    if agent:
                        self.state.update_assignee_tracking(issue, old_status)
                        open_issues = self.state.get_open_issues_for_assignee(agent)
                        if not open_issues:
                            # Get recently closed issues for this agent
                            closed_by_agent = [
                                i for i in current_issues.values()
                                if i.get_assigned_agent() == agent and i.status == "closed"
                            ]
                            if closed_by_agent:
                                self.notifier.notify_agent_complete(agent, closed_by_agent)

                self.state.update_assignee_tracking(issue, old_status)

            # Update tracking for assignee changes
            old_assignee = prev.get("assignee") if prev else None
            new_assignee = issue.assignee
            if old_assignee != new_assignee:
                self.state.update_assignee_tracking(issue, prev.get("status") if prev else None)

        # Update state with current issues (store as dicts for JSON serialization)
        self.state.previous_issues = {
            issue_id: {
                "id": issue.id,
                "status": issue.status,
                "assignee": issue.assignee,
                "title": issue.title,
            }
            for issue_id, issue in current_issues.items()
        }
        self.state.save()


def run_daemon(config: SlackConfig, issues_path: Path, foreground: bool = False):
    """Run the file watcher daemon."""
    # Setup file logging
    if not foreground:
        file_handler = logging.FileHandler(LOG_FILE)
        file_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
        file_handler.addFilter(SensitiveDataFilter())
        logger.addHandler(file_handler)

    logger.info("Starting Beads Slack Notifier (hardened)")
    logger.info(f"Watching: {issues_path}")
    logger.info(f"Webhook configured: {'Yes' if config.webhook_url else 'No'}")
    logger.info(f"Rate limit: {RATE_LIMIT_MAX}/{RATE_LIMIT_WINDOW}s")

    # Initialize state and notifier
    state = NotifierState(STATE_FILE)
    notifier = SlackNotifier(config)

    # Load initial state
    current_issues = parse_issues_jsonl(issues_path)
    for issue_id, issue in current_issues.items():
        if issue_id not in state.previous_issues:
            # Add to state without notifying (initial load)
            state.previous_issues[issue_id] = {
                "id": issue.id,
                "status": issue.status,
                "assignee": issue.assignee,
                "title": issue.title,
            }
            state.update_assignee_tracking(issue, None)
    state.save()

    # Setup file watcher
    event_handler = IssueFileHandler(notifier, state, issues_path)
    observer = Observer()
    observer.schedule(event_handler, str(issues_path.parent), recursive=False)

    # Handle signals for graceful shutdown
    def signal_handler(signum, frame):
        logger.info("Received shutdown signal")
        observer.stop()
        if PID_FILE.exists():
            PID_FILE.unlink()
        sys.exit(0)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Write PID file with restricted permissions
    PID_FILE.write_text(str(os.getpid()))
    enforce_file_permissions(PID_FILE)

    # Start watching
    observer.start()
    logger.info("File watcher started")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        observer.stop()
        observer.join()
        if PID_FILE.exists():
            PID_FILE.unlink()
        logger.info("Notifier stopped")


def init_secrets_file() -> bool:
    """Initialize the secrets file with proper permissions."""
    secrets_dir = SECRETS_FILE.parent

    # Create secrets directory if needed
    if not secrets_dir.exists():
        try:
            secrets_dir.mkdir(parents=True, mode=0o700)
            print(f"Created secrets directory: {secrets_dir}")
        except OSError as e:
            print(f"Failed to create secrets directory: {e}")
            return False

    # Check if secrets file already exists
    if SECRETS_FILE.exists():
        print(f"Secrets file already exists: {SECRETS_FILE}")
        enforce_file_permissions(SECRETS_FILE)
        print("Permissions verified/updated.")
        return True

    # Create placeholder secrets file
    try:
        SECRETS_FILE.write_text("# Paste your Slack webhook URL here (replace this line)\n")
        os.chmod(SECRETS_FILE, REQUIRED_FILE_MODE)
        print(f"Created secrets file: {SECRETS_FILE}")
        print(f"Permissions set to {oct(REQUIRED_FILE_MODE)}")
        print("\nNext steps:")
        print(f"  1. Edit {SECRETS_FILE}")
        print("  2. Replace the placeholder with your Slack webhook URL")
        print("  3. Run: python python/beads_slack_notifier.py --check")
        return True
    except OSError as e:
        print(f"Failed to create secrets file: {e}")
        return False


def check_config(config_path: Path) -> bool:
    """Check configuration and report status."""
    print("Configuration check:")
    print(f"  Config file: {config_path}")
    print(f"  Exists: {config_path.exists()}")

    print(f"\n  Secrets file: {SECRETS_FILE}")
    print(f"  Exists: {SECRETS_FILE.exists()}")
    if SECRETS_FILE.exists():
        mode = stat.S_IMODE(os.stat(SECRETS_FILE).st_mode)
        mode_ok = mode == REQUIRED_FILE_MODE
        print(f"  Permissions: {oct(mode)} {'(OK)' if mode_ok else '(INSECURE - should be 0o600)'}")

    if not config_path.exists() and not SECRETS_FILE.exists():
        print(f"\n  To create config, either:")
        print(f"    Option A (recommended): python python/beads_slack_notifier.py --init-secret")
        print(f"    Option B: cp docs/slack_config.yaml.example {config_path}")
        return False

    config = SlackConfig.load(config_path)

    # Mask the URL in output
    print(f"\n  Webhook URL: {mask_url(config.webhook_url) if config.webhook_url else 'NOT CONFIGURED'}")
    print(f"  Channel: {config.channel or '(default)'}")
    print(f"\n  Rate limit: {RATE_LIMIT_MAX} notifications per {RATE_LIMIT_WINDOW}s")
    print(f"\n  Notifications enabled:")
    print(f"    - Created: {config.notify_created}")
    print(f"    - In Progress: {config.notify_in_progress}")
    print(f"    - Closed: {config.notify_closed}")
    print(f"    - Agent Complete: {config.notify_agent_complete}")
    print(f"    - Review Request: {config.notify_review_request}")

    if not config.webhook_url:
        print(f"\n  WARNING: No webhook URL configured!")
        print(f"  Run: python python/beads_slack_notifier.py --init-secret")
        return False

    # Test webhook (don't log the actual URL)
    print(f"\n  Testing webhook connection...")
    try:
        response = requests.post(
            config.webhook_url,
            json={"text": "Beads Slack Notifier - Configuration test (hardened)"},
            timeout=10,
        )
        if response.status_code == 200:
            print(f"  SUCCESS: Test message sent to Slack!")
            return True
        else:
            print(f"  FAILED: Slack returned status {response.status_code}")
            return False
    except Exception as e:
        # Sanitize error to avoid leaking URL
        error_msg = str(e)
        error_msg = re.sub(r'https://hooks\.slack\.com/services/[A-Za-z0-9/]+', '[MASKED]', error_msg)
        print(f"  FAILED: {error_msg}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Beads Slack Notifier - Watch issues.jsonl and send Slack notifications (hardened)"
    )
    parser.add_argument(
        "--daemon", "-d",
        action="store_true",
        help="Run as background daemon",
    )
    parser.add_argument(
        "--foreground", "-f",
        action="store_true",
        help="Run in foreground (for debugging)",
    )
    parser.add_argument(
        "--check", "-c",
        action="store_true",
        help="Check configuration and exit",
    )
    parser.add_argument(
        "--init-secret",
        action="store_true",
        help="Initialize secrets file with proper permissions",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_FILE,
        help=f"Path to config file (default: {DEFAULT_CONFIG_FILE})",
    )
    parser.add_argument(
        "--issues",
        type=Path,
        default=DEFAULT_ISSUES_FILE,
        help=f"Path to issues.jsonl (default: {DEFAULT_ISSUES_FILE})",
    )

    args = parser.parse_args()

    if args.init_secret:
        success = init_secrets_file()
        sys.exit(0 if success else 1)

    if args.check:
        success = check_config(args.config)
        sys.exit(0 if success else 1)

    if not args.daemon and not args.foreground:
        parser.print_help()
        print("\nUse --daemon to run as background process or --foreground for debugging.")
        sys.exit(1)

    # Load configuration
    config = SlackConfig.load(args.config)

    if not config.webhook_url:
        logger.warning("No Slack webhook URL configured - notifications will be skipped")

    # Run the daemon
    if args.daemon:
        # Fork to background
        pid = os.fork()
        if pid > 0:
            print(f"Beads Slack Notifier started (PID: {pid})")
            print(f"Logs: {LOG_FILE}")
            sys.exit(0)

        # Detach from terminal
        os.setsid()

        # Redirect stdio
        sys.stdin = open(os.devnull, 'r')
        sys.stdout = open(os.devnull, 'w')
        sys.stderr = open(os.devnull, 'w')

    run_daemon(config, args.issues, foreground=args.foreground)


if __name__ == "__main__":
    main()
