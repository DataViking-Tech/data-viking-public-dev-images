#!/usr/bin/env python3
"""
Direct Slack Notification CLI - Send messages directly to Slack from agents.
"""

import argparse
import os
import socket
import stat
import sys
from pathlib import Path
from typing import Optional

from .notifier import (
    get_webhook_url,
    mask_url,
    sanitize_for_slack,
    get_secrets_file,
    REQUIRED_FILE_MODE,
)


def get_agent_id() -> str:
    return os.environ.get("BEADS_AGENT_ID", socket.gethostname())


def get_current_issue() -> Optional[str]:
    return os.environ.get("BEADS_ISSUE_ID")


def send_slack_message(webhook_url: str, text: str, blocks: Optional[list] = None) -> bool:
    from .notifier import SlackConfig, SlackNotifier

    config = SlackConfig(webhook_url=webhook_url)
    notifier = SlackNotifier(config)
    return notifier.send(text, blocks)


def notify_review(message: str, issue_id: Optional[str] = None) -> bool:
    webhook_url = get_webhook_url()
    if not webhook_url:
        print("Error: No Slack webhook URL configured", file=sys.stderr)
        return False

    agent = sanitize_for_slack(get_agent_id(), 100)
    issue = sanitize_for_slack(issue_id or get_current_issue() or "", 100)
    safe_message = sanitize_for_slack(message, 1000)

    issue_text = f"\n   Issue: {issue}" if issue else ""
    text = f"Review Requested\n   Agent: {agent}{issue_text}\n   Message: {safe_message}"

    blocks = [
        {"type": "section", "text": {"type": "mrkdwn", "text": ":eyes: *Review Requested*"}},
        {"type": "section", "fields": [{"type": "mrkdwn", "text": f"*Agent:*\n{agent}"}]},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*Message:*\n{safe_message}"}},
    ]

    if issue:
        blocks[1]["fields"].append({"type": "mrkdwn", "text": f"*Issue:*\n`{issue}`"})

    return send_slack_message(webhook_url, text, blocks)


def notify_blocked(message: str, issue_id: Optional[str] = None) -> bool:
    webhook_url = get_webhook_url()
    if not webhook_url:
        print("Error: No Slack webhook URL configured", file=sys.stderr)
        return False

    agent = sanitize_for_slack(get_agent_id(), 100)
    issue = sanitize_for_slack(issue_id or get_current_issue() or "", 100)
    safe_message = sanitize_for_slack(message, 1000)

    issue_text = f"\n   Issue: {issue}" if issue else ""
    text = f"Agent Blocked\n   Agent: {agent}{issue_text}\n   Blocker: {safe_message}"

    blocks = [
        {"type": "section", "text": {"type": "mrkdwn", "text": ":no_entry: *Agent Blocked*"}},
        {"type": "section", "fields": [{"type": "mrkdwn", "text": f"*Agent:*\n{agent}"}]},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*Blocker:*\n{safe_message}"}},
    ]

    if issue:
        blocks[1]["fields"].append({"type": "mrkdwn", "text": f"*Issue:*\n`{issue}`"})

    return send_slack_message(webhook_url, text, blocks)


def notify_message(message: str, issue_id: Optional[str] = None) -> bool:
    webhook_url = get_webhook_url()
    if not webhook_url:
        print("Error: No Slack webhook URL configured", file=sys.stderr)
        return False

    agent = sanitize_for_slack(get_agent_id(), 100)
    issue = sanitize_for_slack(issue_id or get_current_issue() or "", 100)
    safe_message = sanitize_for_slack(message, 2000)

    issue_text = f" ({issue})" if issue else ""
    text = f"Agent Update [{agent}]{issue_text}: {safe_message}"

    blocks = [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f":speech_balloon: *Agent Update*\n*Agent:* {agent}" + (f" | *Issue:* `{issue}`" if issue else ""),
            },
        },
        {"type": "section", "text": {"type": "mrkdwn", "text": safe_message}},
    ]

    return send_slack_message(webhook_url, text, blocks)


def notify_complete(message: str, issue_id: Optional[str] = None) -> bool:
    webhook_url = get_webhook_url()
    if not webhook_url:
        print("Error: No Slack webhook URL configured", file=sys.stderr)
        return False

    agent = sanitize_for_slack(get_agent_id(), 100)
    issue = sanitize_for_slack(issue_id or get_current_issue() or "", 100)
    safe_message = sanitize_for_slack(message, 1000)

    issue_text = f"\n   Issue: {issue}" if issue else ""
    text = f"Work Complete\n   Agent: {agent}{issue_text}\n   {safe_message}"

    blocks = [
        {"type": "section", "text": {"type": "mrkdwn", "text": ":white_check_mark: *Work Complete*"}},
        {"type": "section", "fields": [{"type": "mrkdwn", "text": f"*Agent:*\n{agent}"}]},
        {"type": "section", "text": {"type": "mrkdwn", "text": safe_message}},
    ]

    if issue:
        blocks[1]["fields"].append({"type": "mrkdwn", "text": f"*Issue:*\n`{issue}`"})

    return send_slack_message(webhook_url, text, blocks)


def main():
    parser = argparse.ArgumentParser(
        description="Send direct Slack notifications from coding agents (hardened)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python -m slack.cli review "Need human input on API design"
    python -m slack.cli blocked "Waiting on frontline-15s.1"
    python -m slack.cli message "Status update: 50% complete"
    python -m slack.cli complete "Finished implementing feature X"
""",
    )

    subparsers = parser.add_subparsers(dest="command", help="Notification type")

    review_parser = subparsers.add_parser("review", help="Request human review")
    review_parser.add_argument("message", help="Description of what needs review")
    review_parser.add_argument("--issue", "-i", help="Issue ID (overrides BEADS_ISSUE_ID)")

    blocked_parser = subparsers.add_parser("blocked", help="Report a blocker")
    blocked_parser.add_argument("message", help="Description of the blocker")
    blocked_parser.add_argument("--issue", "-i", help="Issue ID (overrides BEADS_ISSUE_ID)")

    message_parser = subparsers.add_parser("message", help="Send status update")
    message_parser.add_argument("message", help="Status message")
    message_parser.add_argument("--issue", "-i", help="Issue ID (overrides BEADS_ISSUE_ID)")

    complete_parser = subparsers.add_parser("complete", help="Report work complete")
    complete_parser.add_argument("message", help="Completion message")
    complete_parser.add_argument("--issue", "-i", help="Issue ID (overrides BEADS_ISSUE_ID)")

    subparsers.add_parser("check", help="Check configuration")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "check":
        webhook_url = get_webhook_url()
        print(f"Agent ID: {get_agent_id()}")
        print(f"Current Issue: {get_current_issue() or '(not set)'}")
        secrets_file = get_secrets_file()
        print(f"Secrets file: {secrets_file}")
        print(f"  Exists: {secrets_file.exists()}")
        if secrets_file.exists():
            mode = stat.S_IMODE(os.stat(secrets_file).st_mode)
            mode_ok = mode == REQUIRED_FILE_MODE
            print(f"  Permissions: {oct(mode)} {'(OK)' if mode_ok else '(INSECURE)'}")
        print(f"Webhook URL: {mask_url(webhook_url) if webhook_url else 'NOT CONFIGURED'}")

        if not webhook_url:
            print("\nTo configure:")
            print("  python -m slack.cli check")
            sys.exit(1)
        print("\nConfiguration OK!")
        sys.exit(0)

    issue_id = getattr(args, "issue", None)
    success = False
    if args.command == "review":
        success = notify_review(args.message, issue_id)
    elif args.command == "blocked":
        success = notify_blocked(args.message, issue_id)
    elif args.command == "message":
        success = notify_message(args.message, issue_id)
    elif args.command == "complete":
        success = notify_complete(args.message, issue_id)

    if success:
        print("Notification sent successfully")
        sys.exit(0)
    print("Failed to send notification", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
