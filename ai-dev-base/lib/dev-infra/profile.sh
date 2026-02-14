#!/bin/bash
# AI Dev Utilities - Auto-sourced on shell startup
# Provides dev-infra components and extensible aliases

# Double-source guard: skip if already loaded in this shell session
if [ -n "${_AI_DEV_UTILS_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
_AI_DEV_UTILS_LOADED=1

# Source dev-infra components if available
# Note: dev-infra scripts use 'set -euo pipefail' which would pollute the
# interactive shell. We save/restore shell options to prevent this.
if [ -d "/opt/dev-infra" ]; then
    # Save current shell options
    _ai_dev_old_opts=$(set +o)
    _ai_dev_old_shopt=$(shopt -p 2>/dev/null || true)

    # Credential caching framework (github, cloudflare, claude auth)
    # Note: setup runs non-interactively via postStartCommand (start_gastown_services.sh).
    # This interactive-shell call catches credentials added mid-session.
    if [ -f "/opt/dev-infra/credential_cache.sh" ]; then
        source "/opt/dev-infra/credential_cache.sh" 2>/dev/null || true
        setup_credential_cache "github" "claude" || true
    fi

    # Gastown environment (init handled by ensure_gastown.sh at container create)
    # Only set up gastown context when enabled (default: true)
    if [ "${GASTOWN_ENABLED:-true}" != "false" ] && command -v gt >/dev/null 2>&1; then
        export GASTOWN_HOME="${GASTOWN_HOME:-$HOME/gt}"
        # Source rig env to set BEADS_DIR for correct beads location.
        # Without this, bd auto-discovers .beads/ in the project directory
        # instead of using the rig's beads at $GASTOWN_HOME/<rig>/.beads/.
        if [ -z "${BEADS_DIR:-}" ] && [ -f "$GASTOWN_HOME/.rig_env" ]; then
            source "$GASTOWN_HOME/.rig_env" 2>/dev/null || true
        fi
    fi

    # Directory creation component
    if [ -f "/opt/dev-infra/directories.sh" ]; then
        source "/opt/dev-infra/directories.sh" 2>/dev/null || true
    fi

    # Python venv component
    if [ -f "/opt/dev-infra/python_venv.sh" ]; then
        source "/opt/dev-infra/python_venv.sh" 2>/dev/null || true
    fi

    # Git hooks component
    if [ -f "/opt/dev-infra/git_hooks.sh" ]; then
        source "/opt/dev-infra/git_hooks.sh" 2>/dev/null || true
    fi

    # Restore original shell options (prevents 'set -u' from persisting)
    eval "$_ai_dev_old_opts" 2>/dev/null || true
    eval "$_ai_dev_old_shopt" 2>/dev/null || true
    unset _ai_dev_old_opts _ai_dev_old_shopt
fi

# Standard bash aliases
alias bd-ready='bd ready'
alias bd-sync='bd sync'
alias bd-list='bd list'
alias py='python3'
alias pip='pip3'
if [ "${GASTOWN_ENABLED:-true}" != "false" ]; then
    alias gt-status='gt status'
    alias gt-doctor='gt doctor'
fi

# Extensible - projects can add their own aliases
# Place project-specific aliases in /workspace/.devcontainer/aliases.sh
if [ -f "/workspace/.devcontainer/aliases.sh" ]; then
    source "/workspace/.devcontainer/aliases.sh" 2>/dev/null || true
fi
