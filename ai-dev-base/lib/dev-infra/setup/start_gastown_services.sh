#!/usr/bin/env bash
# Devcontainer postStartCommand: credential setup + gastown services.
# Called from devcontainer postStartCommand (via image LABEL).
# Runs on every container start, including after initial creation.
# Idempotent: credential cache checks are non-blocking, gt up only starts
# services that aren't already running.
set -euo pipefail

# --- Credential cache setup ---
# Run before gastown services so credentials are available to agents.
# Interactive shells get this via lib/dev-infra/profile.sh (installed to /etc/profile.d/ai-dev-utils.sh);
# postStartCommand runs non-interactively, so we run it here too.
# Services default to "github cloudflare claude"; projects can override via env var.
#   e.g. in devcontainer.json containerEnv:
#     "CREDENTIAL_CACHE_SERVICES": "github claude"
if [ -f "/opt/dev-infra/credential_cache.sh" ]; then
  source "/opt/dev-infra/credential_cache.sh"
  IFS=' ' read -ra _services <<< "${CREDENTIAL_CACHE_SERVICES:-github cloudflare claude}"
  setup_credential_cache "${_services[@]}" || true
  unset _services
  # Verify credentials propagated correctly; re-import from shared if needed
  verify_credential_propagation || true
fi

# --- Gastown services ---
# Skip gastown services if disabled via env var (default: enabled)
if [ "${GASTOWN_ENABLED:-true}" = "false" ] || ! command -v gt >/dev/null 2>&1; then
  exit 0
fi

GASTOWN_HOME="${GASTOWN_HOME:-$HOME/gt}"

# Only start services if gastown HQ is initialized
if [ ! -f "$GASTOWN_HOME/mayor/town.json" ]; then
  exit 0
fi

# --- Pre-seed deacon heartbeat ---
# The daemon reads deacon/heartbeat.json on startup to decide if the deacon
# is alive. After a container restart, this file is either missing or stale,
# causing the daemon to parse it as max-duration (2562047h47m) and immediately
# restart-loop the deacon before it has time to boot. Writing a fresh timestamp
# here gives the deacon a full patrol interval (~5m) to initialize.
if [ -d "$GASTOWN_HOME/deacon" ]; then
  printf '{"timestamp":"%s","status":"booting","patrol_active":false}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$GASTOWN_HOME/deacon/heartbeat.json"
fi

# --- Ensure town root has a git repo ---
# The gt daemon's convoy watcher calls `bd activity` from the town root.
# bd requires a git repo to run its daemon; without one, bd falls back to
# no-daemon mode where `activity` is unsupported, causing a permanent 5s
# retry loop. New installs use `gt install --git` but older ones may not
# have this.
if [ -d "$GASTOWN_HOME/.beads" ] && [ ! -d "$GASTOWN_HOME/.git" ]; then
  git -C "$GASTOWN_HOME" init -b main >/dev/null 2>&1 || true
fi

# --- Start town-level beads daemon ---
# The gt daemon's convoy watcher and GUPP checks need bd daemon running
# for the town-level .beads/ database. BEADS_DIR must be unset here so bd
# discovers the town .beads/ instead of routing to the rig's beads.
if [ -d "$GASTOWN_HOME/.beads" ] && command -v bd >/dev/null 2>&1; then
  # Migrate legacy databases missing repo fingerprint (pre-0.17.5)
  if ! (cd "$GASTOWN_HOME" && BEADS_DIR= bd daemon status >/dev/null 2>&1); then
    # Clean stale lock files left by previous daemon instances
    rm -f "$GASTOWN_HOME/.beads/daemon.lock"
    (cd "$GASTOWN_HOME" && BEADS_DIR= bd migrate --update-repo-id >/dev/null 2>&1) || true
    (cd "$GASTOWN_HOME" && BEADS_DIR= bd daemon start >/dev/null 2>&1) || true
  fi
fi

# --- Clean stale PID files from previous container lifecycle ---
# The ~/gt/ volume survives container rebuilds but processes don't,
# leaving PID files that refer to dead processes. Removing them before
# gt up prevents the noisy "removed stale PID file" message.
for _pidfile in "$GASTOWN_HOME"/daemon/daemon.pid "$GASTOWN_HOME"/daemon/dolt.pid; do
  if [ -f "$_pidfile" ]; then
    _pid=$(cat "$_pidfile" 2>/dev/null)
    if [ -n "$_pid" ] && ! kill -0 "$_pid" 2>/dev/null; then
      rm -f "$_pidfile"
    fi
  fi
done
rm -f "$GASTOWN_HOME"/daemon/daemon.lock

# Unset BEADS_DIR so gt daemon's subprocess calls to bd discover town .beads/
cd "$GASTOWN_HOME" && BEADS_DIR= gt up -q 2>/dev/null || true
cd "$GASTOWN_HOME" && gt up -q 2>/dev/null || true

# --- Daemon health watchdog ---
# Runs in background to detect and restart crashed daemon.
# Idempotent: script checks its own PID file before starting.
WATCHDOG_SCRIPT="/opt/dev-infra/setup/daemon_watchdog.sh"
if [ -f "$WATCHDOG_SCRIPT" ]; then
  nohup "$WATCHDOG_SCRIPT" </dev/null >/dev/null 2>&1 &
  disown
fi
