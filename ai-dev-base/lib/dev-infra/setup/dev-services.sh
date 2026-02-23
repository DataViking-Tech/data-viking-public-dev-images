#!/usr/bin/env bash
# Unified service management for ai-dev-base devcontainers.
# Usage: dev-services {start|stop|restart|status}
#
# Manages all dev-infra services as a cohesive unit:
#   1. Credential cache setup (one-shot, not a daemon)
#   2. Town-level beads daemon (bd daemon)
#   3. Gastown services (gt up/down)
#   4. Daemon health watchdog (background loop)
#   5. Beads Slack notifier (optional python daemon)
#
# Environment variables:
#   GASTOWN_ENABLED  (default "true")  — set "false" to disable gastown services
#   GASTOWN_HOME     (default $HOME/gt) — gastown data directory
#   CREDENTIAL_CACHE_SERVICES (default "github cloudflare claude")
#   DAEMON_WATCHDOG_INTERVAL  (default 60) — watchdog check interval in seconds
set -uo pipefail

GASTOWN_HOME="${GASTOWN_HOME:-$HOME/gt}"

# ── Utility functions ────────────────────────────────────────────────

_gastown_enabled() {
  [ "${GASTOWN_ENABLED:-true}" != "false" ] && command -v gt >/dev/null 2>&1
}

_gastown_initialized() {
  [ -f "$GASTOWN_HOME/mayor/town.json" ]
}

_check_pid() {
  local pidfile="$1"
  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
      return 0
    fi
  fi
  return 1
}

_kill_by_pidfile() {
  local pidfile="$1"
  local pid
  if pid=$(_check_pid "$pidfile"); then
    kill "$pid" 2>/dev/null || true
    local i=0
    while [ $i -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
      sleep 0.1
      i=$((i + 1))
    done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$pidfile"
}

# ── Service: credentials (one-shot) ─────────────────────────────────

svc_start_credentials() {
  if [ -f "/opt/dev-infra/credential_cache.sh" ]; then
    source "/opt/dev-infra/credential_cache.sh"
    local _services
    IFS=' ' read -ra _services <<< "${CREDENTIAL_CACHE_SERVICES:-github cloudflare claude}"
    setup_credential_cache "${_services[@]}" || true
    verify_credential_propagation || true
  fi
}

svc_stop_credentials() { :; }

svc_status_credentials() {
  if [ -f "/opt/dev-infra/credential_cache.sh" ]; then
    printf "  %-16s %s\n" "credentials" "configured"
  else
    printf "  %-16s %s\n" "credentials" "not-installed"
  fi
}

# ── Service: beads-daemon (town-level bd daemon) ────────────────────

svc_start_beads_daemon() {
  _gastown_enabled || return 0
  _gastown_initialized || return 0
  [ -d "$GASTOWN_HOME/.beads" ] || return 0
  command -v bd >/dev/null 2>&1 || return 0

  if ! (cd "$GASTOWN_HOME" && BEADS_DIR= bd daemon status >/dev/null 2>&1); then
    rm -f "$GASTOWN_HOME/.beads/daemon.lock"
    (cd "$GASTOWN_HOME" && BEADS_DIR= bd migrate --update-repo-id >/dev/null 2>&1) || true
    (cd "$GASTOWN_HOME" && BEADS_DIR= bd daemon start >/dev/null 2>&1) || true
  fi
}

svc_stop_beads_daemon() {
  _gastown_enabled || return 0
  [ -d "$GASTOWN_HOME/.beads" ] || return 0
  command -v bd >/dev/null 2>&1 || return 0
  (cd "$GASTOWN_HOME" && BEADS_DIR= bd daemon stop >/dev/null 2>&1) || true
}

svc_status_beads_daemon() {
  if ! _gastown_enabled; then
    printf "  %-16s %s\n" "beads-daemon" "disabled"
    return
  fi
  if [ ! -d "$GASTOWN_HOME/.beads" ] || ! command -v bd >/dev/null 2>&1; then
    printf "  %-16s %s\n" "beads-daemon" "not-configured"
    return
  fi
  local pid
  if pid=$(_check_pid "$GASTOWN_HOME/.beads/daemon.pid"); then
    printf "  %-16s %s\n" "beads-daemon" "running (pid $pid)"
  else
    printf "  %-16s %s\n" "beads-daemon" "stopped"
  fi
}

# ── Service: gastown (gt up/down) ───────────────────────────────────

svc_start_gastown() {
  _gastown_enabled || return 0
  _gastown_initialized || return 0

  # Pre-seed deacon heartbeat so daemon doesn't restart-loop the deacon
  if [ -d "$GASTOWN_HOME/deacon" ]; then
    printf '{"timestamp":"%s","status":"booting","patrol_active":false}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$GASTOWN_HOME/deacon/heartbeat.json"
  fi

  # Ensure town root has a git repo (bd daemon requires one)
  if [ -d "$GASTOWN_HOME/.beads" ] && [ ! -d "$GASTOWN_HOME/.git" ]; then
    git -C "$GASTOWN_HOME" init -b main >/dev/null 2>&1 || true
  fi

  # Clean stale PID files from previous container lifecycle
  for _pidfile in "$GASTOWN_HOME"/daemon/daemon.pid "$GASTOWN_HOME"/daemon/dolt.pid; do
    if [ -f "$_pidfile" ]; then
      local _pid
      _pid=$(cat "$_pidfile" 2>/dev/null)
      if [ -n "$_pid" ] && ! kill -0 "$_pid" 2>/dev/null; then
        rm -f "$_pidfile"
      fi
    fi
  done
  rm -f "$GASTOWN_HOME"/daemon/daemon.lock

  # Start gastown services (both calls match existing start_gastown_services.sh)
  (cd "$GASTOWN_HOME" && BEADS_DIR= gt up -q 2>/dev/null) || true
  (cd "$GASTOWN_HOME" && gt up -q 2>/dev/null) || true
}

svc_stop_gastown() {
  _gastown_enabled || return 0
  _gastown_initialized || return 0
  (cd "$GASTOWN_HOME" && gt down -q 2>/dev/null) || true
}

svc_status_gastown() {
  if ! _gastown_enabled; then
    printf "  %-16s %s\n" "gastown" "disabled"
    return
  fi
  if ! _gastown_initialized; then
    printf "  %-16s %s\n" "gastown" "not-initialized"
    return
  fi
  if (cd "$GASTOWN_HOME" && gt daemon status >/dev/null 2>&1); then
    printf "  %-16s %s\n" "gastown" "running"
  else
    printf "  %-16s %s\n" "gastown" "stopped"
  fi
}

# ── Service: watchdog (daemon_watchdog.sh) ──────────────────────────

svc_start_watchdog() {
  _gastown_enabled || return 0
  _gastown_initialized || return 0

  local watchdog_script="/opt/dev-infra/setup/daemon_watchdog.sh"
  [ -f "$watchdog_script" ] || return 0

  # The watchdog script itself handles idempotency via its PID file
  nohup "$watchdog_script" </dev/null >/dev/null 2>&1 &
  disown
}

svc_stop_watchdog() {
  _kill_by_pidfile "$GASTOWN_HOME/.daemon_watchdog.pid"
}

svc_status_watchdog() {
  if ! _gastown_enabled; then
    printf "  %-16s %s\n" "watchdog" "disabled"
    return
  fi
  local pid
  if pid=$(_check_pid "$GASTOWN_HOME/.daemon_watchdog.pid"); then
    printf "  %-16s %s\n" "watchdog" "running (pid $pid)"
  else
    printf "  %-16s %s\n" "watchdog" "stopped"
  fi
}

# ── Service: notifier (beads Slack notifier) ────────────────────────

svc_start_notifier() {
  local notifier_script="/opt/dev-infra/setup/start_beads_notifier.sh"
  [ -f "$notifier_script" ] || return 0
  "$notifier_script" || true
}

svc_stop_notifier() {
  _kill_by_pidfile ".beads/slack_notifier.pid"
}

svc_status_notifier() {
  local pid
  if pid=$(_check_pid ".beads/slack_notifier.pid"); then
    printf "  %-16s %s\n" "notifier" "running (pid $pid)"
  else
    if [ -f ".beads/slack_config.yaml" ] || [ -f ".secrets/slack_webhook" ] || [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
      printf "  %-16s %s\n" "notifier" "stopped"
    else
      printf "  %-16s %s\n" "notifier" "not-configured"
    fi
  fi
}

# ── Main dispatch ───────────────────────────────────────────────────

cmd_start() {
  svc_start_credentials
  svc_start_beads_daemon
  svc_start_gastown
  svc_start_watchdog
  svc_start_notifier
}

cmd_stop() {
  svc_stop_notifier
  svc_stop_watchdog
  svc_stop_gastown
  svc_stop_beads_daemon
  svc_stop_credentials
}

cmd_restart() {
  cmd_stop
  cmd_start
}

cmd_status() {
  local has_stopped=false
  echo "dev-infra service status:"

  # Capture status output while checking for stopped services
  local output
  output=$(
    svc_status_credentials
    svc_status_beads_daemon
    svc_status_gastown
    svc_status_watchdog
    svc_status_notifier
  )
  echo "$output"

  # Exit non-zero if any expected service is stopped
  if echo "$output" | grep -q "stopped"; then
    return 1
  fi
  return 0
}

usage() {
  cat <<'EOF'
Usage: dev-services {start|stop|restart|status}

Manage all dev-infra services for ai-dev-base devcontainers.

Commands:
  start    Start all services (idempotent, safe to call repeatedly)
  stop     Gracefully stop all services
  restart  Stop then start all services
  status   Show running state of each service
EOF
}

case "${1:-}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_restart ;;
  status)  cmd_status ;;
  --help|-h) usage ;;
  *)
    usage >&2
    exit 1
    ;;
esac
