#!/bin/bash
# env_hydrate.sh — Doppler-first environment variable hydration
#
# Priority order:
#   1. Doppler (if authenticated and project configured) — source of truth
#   2. .env file in project root — local fallback
#
# Sourced by profile.sh on shell startup. Exports vars into the current shell.
# Only runs once per shell session (guarded by _ENV_HYDRATED).

# Skip if already hydrated this session
[ -n "${_ENV_HYDRATED:-}" ] && return 0 2>/dev/null

_env_hydrate() {
    local project_root=""

    # Find project root (look for .git)
    if [ -d "/workspaces" ]; then
        for d in /workspaces/*/; do
            [ -d "$d/.git" ] && project_root="$d" && break
        done
    fi
    [ -z "$project_root" ] && return 0

    # Try Doppler first — requires both authentication and project setup
    if command -v doppler >/dev/null 2>&1; then
        # Check if doppler is authenticated (has a token)
        if doppler me >/dev/null 2>&1; then
            # Check if project is configured in this directory
            if (cd "$project_root" && doppler secrets download --no-file --format env 2>/dev/null) | head -1 | grep -q '='; then
                eval "$(cd "$project_root" && doppler secrets download --no-file --format env-no-quotes 2>/dev/null | sed 's/^/export /')"
                export _ENV_SOURCE="doppler"
                export _ENV_HYDRATED=1
                return 0
            fi
        fi
    fi

    # Fallback: source .env file
    local envfile="$project_root/.env"
    if [ -f "$envfile" ]; then
        # Export each VAR=value line, skipping comments and blanks
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            case "$line" in
                \#*|"") continue ;;
            esac
            # Only export lines that look like KEY=VALUE
            if echo "$line" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*='; then
                export "$line"
            fi
        done < "$envfile"
        export _ENV_SOURCE="dotenv"
        export _ENV_HYDRATED=1
        return 0
    fi

    # Nothing to hydrate
    export _ENV_HYDRATED=1
}

_env_hydrate
unset -f _env_hydrate
