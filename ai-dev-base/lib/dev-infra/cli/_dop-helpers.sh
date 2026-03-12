#!/usr/bin/env bash
# Shared helpers for CLI wrappers.
# Source this file; do not execute directly.
#
# Provides:
#   _load_registry  — read service-registry.conf (env vars override)
#   _dop_get        — fetch a single Doppler secret
#   _die            — print error and exit
#   _usage          — print usage and exit
#   _require_cmd    — assert a command exists

set -uo pipefail

_REGISTRY_FILE="${CLI_REGISTRY:-/opt/dev-infra/cli/service-registry.conf}"

# Load service-registry.conf — sets variables only if not already in env.
_load_registry() {
  [ -f "$_REGISTRY_FILE" ] || return 0
  while IFS='=' read -r key value; do
    # Skip comments and blanks
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    # Only set if not already in environment
    if [ -z "${!key:-}" ]; then
      export "$key=$value"
    fi
  done < "$_REGISTRY_FILE"
}

# Fetch a single secret from Doppler.
# Usage: _dop_get <project> <config> <key>
_dop_get() {
  local project="$1" config="$2" key="$3"
  doppler secrets get "$key" --project "$project" --config "$config" --plain 2>/dev/null
}

_die() {
  echo "ERROR: $*" >&2
  exit 1
}

_usage() {
  echo "$*" >&2
  exit 1
}

_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || _die "'$1' is required but not found in PATH"
}
