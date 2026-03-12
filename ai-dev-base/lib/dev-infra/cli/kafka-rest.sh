#!/usr/bin/env bash
# kafka-rest — Kafka REST proxy wrapper for AI agents.
# Requires KAFKA_REST_URL (or fetches from Doppler).
# Optionally uses KAFKA_REST_KEY and KAFKA_REST_SECRET for auth.
#
# Usage: kafka-rest {topics} [args...]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_dop-helpers.sh"
_require_cmd curl
_require_cmd jq
_load_registry

_resolve_kafka_creds() {
  if [ -z "${KAFKA_REST_URL:-}" ]; then
    local project="${KAFKA_PROJECT:-}"
    local config="${KAFKA_CONFIG:-prd}"
    [ -z "$project" ] && _die "KAFKA_REST_URL not set and KAFKA_PROJECT not configured"
    KAFKA_REST_URL=$(_dop_get "$project" "$config" "KAFKA_REST_URL") \
      || _die "Failed to fetch KAFKA_REST_URL from Doppler"
  fi
  # Optional auth credentials
  if [ -z "${KAFKA_REST_KEY:-}" ]; then
    local project="${KAFKA_PROJECT:-}"
    local config="${KAFKA_CONFIG:-prd}"
    if [ -n "$project" ]; then
      KAFKA_REST_KEY=$(_dop_get "$project" "$config" "KAFKA_REST_KEY" 2>/dev/null) || true
      KAFKA_REST_SECRET=$(_dop_get "$project" "$config" "KAFKA_REST_SECRET" 2>/dev/null) || true
    fi
  fi
}

_kafka_api() {
  local endpoint="$1"
  local auth_args=()
  if [ -n "${KAFKA_REST_KEY:-}" ] && [ -n "${KAFKA_REST_SECRET:-}" ]; then
    auth_args=(-u "${KAFKA_REST_KEY}:${KAFKA_REST_SECRET}")
  fi
  curl -s "${auth_args[@]}" \
    -H "Content-Type: application/vnd.kafka.v2+json" \
    "${KAFKA_REST_URL}${endpoint}"
}

case "${1:-}" in
  topics)
    _resolve_kafka_creds
    _kafka_api "/topics" | jq -r '.[]? // .'
    ;;
  --help|-h)
    cat <<'EOF'
Usage: kafka-rest {topics} [args...]

Commands:
  topics    List available Kafka topics

Environment:
  KAFKA_REST_URL       REST proxy URL (or fetched from Doppler)
  KAFKA_REST_KEY       Optional auth key (or fetched from Doppler)
  KAFKA_REST_SECRET    Optional auth secret (or fetched from Doppler)
  KAFKA_PROJECT        Doppler project for credential lookup
  KAFKA_CONFIG         Doppler config (default: prd)
EOF
    ;;
  *)
    _usage "Usage: kafka-rest {topics} [args...]"
    ;;
esac
