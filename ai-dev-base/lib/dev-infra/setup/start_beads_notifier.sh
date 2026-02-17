#!/usr/bin/env bash
# Start beads Slack notifier daemon if configured.
# Called from devcontainer postStartCommand (via image LABEL).
# Runs on every container start, including after initial creation.
# Idempotent: skips if daemon is already running or not configured.
set -euo pipefail

# Need python3 for the notifier daemon
if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

NOTIFIER="/opt/ai-coding-utils/slack/beads_watcher_template.py"

# Notifier script must exist in the image
if [ ! -f "$NOTIFIER" ]; then
  exit 0
fi

# Need a .beads/ directory to watch
if [ ! -d .beads ]; then
  exit 0
fi

PID_FILE=".beads/slack_notifier.pid"

# Check if already running
if [ -f "$PID_FILE" ]; then
  pid=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    exit 0
  fi
  # Stale PID file - remove it
  rm -f "$PID_FILE"
fi

# Check if Slack notifications are configured (any source)
configured=false
if [ -f ".beads/slack_config.yaml" ]; then
  configured=true
elif [ -f ".secrets/slack_webhook" ]; then
  configured=true
elif [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  configured=true
fi

if [ "$configured" = false ]; then
  exit 0
fi

python3 "$NOTIFIER" --daemon 2>/dev/null || true
