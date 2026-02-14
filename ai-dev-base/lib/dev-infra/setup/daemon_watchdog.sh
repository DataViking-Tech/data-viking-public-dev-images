#!/usr/bin/env bash
# Daemon health watchdog: periodically checks gt daemon and restarts if dead.
# Runs as a background process, started by start_gastown_services.sh.
# Idempotent: uses PID file to prevent duplicate watchdogs.
set -uo pipefail

GASTOWN_HOME="${GASTOWN_HOME:-$HOME/gt}"
WATCHDOG_INTERVAL="${DAEMON_WATCHDOG_INTERVAL:-60}"
WATCHDOG_PID_FILE="$GASTOWN_HOME/.daemon_watchdog.pid"
LOG_FILE="$GASTOWN_HOME/logs/daemon_watchdog.log"
MAX_LOG_BYTES=102400  # 100KB, then rotate

# --- Idempotency check ---
if [ -f "$WATCHDOG_PID_FILE" ]; then
  existing_pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    exit 0  # Watchdog already running
  fi
  rm -f "$WATCHDOG_PID_FILE"
fi

# --- Setup ---
mkdir -p "$(dirname "$LOG_FILE")"
echo $$ > "$WATCHDOG_PID_FILE"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" >> "$LOG_FILE"
}

rotate_log() {
  if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_BYTES" ]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
    log "Log rotated"
  fi
}

cleanup() {
  rm -f "$WATCHDOG_PID_FILE"
  log "Watchdog stopped (PID $$)"
  exit 0
}

trap cleanup SIGTERM SIGINT

log "Watchdog started (PID $$, interval ${WATCHDOG_INTERVAL}s)"

# --- Main loop ---
while true; do
  sleep "$WATCHDOG_INTERVAL" &
  wait $! 2>/dev/null || break  # Allow signal interruption during sleep

  # Skip if gastown is disabled or gt is missing
  if [ "${GASTOWN_ENABLED:-true}" = "false" ] || ! command -v gt >/dev/null 2>&1; then
    continue
  fi

  # Skip if gastown HQ not initialized
  if [ ! -f "$GASTOWN_HOME/mayor/town.json" ]; then
    continue
  fi

  # Check daemon health
  if ! gt daemon status >/dev/null 2>&1; then
    log "Daemon not running - attempting restart"
    if cd "$GASTOWN_HOME" && gt daemon start >/dev/null 2>&1; then
      log "Daemon restarted successfully"
    else
      log "Daemon restart failed (exit $?)"
    fi
  fi

  rotate_log
done

cleanup
