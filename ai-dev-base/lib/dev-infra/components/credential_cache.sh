#!/bin/bash
# Generic Credential Caching Framework for Devcontainers
#
# Usage:
#   source devcontainer/components/credential_cache.sh
#   setup_credential_cache "github" "cloudflare"
#
# Supported services: github, cloudflare, claude
#
# Each service follows three-tier authentication:
#   1. Check for cached credentials (bind-mounted directory)
#   2. Auto-convert environment variables (e.g., GITHUB_TOKEN)
#   3. Interactive fallback with user instructions

# Resolve project auth directory lazily (not at source time).
# Falls back to $HOME if not inside a git repo.
_get_project_auth_dir() {
  local repo
  repo=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$repo" ]; then
    printf '%s/temp/auth\n' "$repo"
  else
    printf '%s/.local/share/dev-infra/auth\n' "$HOME"
  fi
}

# State directory for sentinels (always under $HOME, never workspace)
_get_state_dir() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dev-infra"
}

# Credential cache logging - writes to stderr for debugging
# Set CREDENTIAL_CACHE_DEBUG=1 to enable verbose logging
_cred_log() {
  local level="$1"
  shift
  if [ "${CREDENTIAL_CACHE_DEBUG:-0}" = "1" ] || [ "$level" = "WARN" ]; then
    echo "[credential_cache] $level: $*" >&2
  fi
}

# Main entry point - setup credentials for requested services
# Usage: setup_credential_cache "github" "cloudflare"
setup_credential_cache() {
  local services=("$@")
  local failed_services=()

  # Create base auth directory (sudo fallback for root-owned workspace mounts)
  local AUTH_DIR
  AUTH_DIR="$(_get_project_auth_dir)"
  if ! mkdir -p "$AUTH_DIR" 2>/dev/null; then
    sudo mkdir -p "$AUTH_DIR" 2>/dev/null && \
      sudo chown -R "$(id -u):$(id -g)" "$AUTH_DIR" 2>/dev/null || true
  fi

  # Validate and setup each service
  for service in "${services[@]}"; do
    if declare -f "setup_${service}_auth" >/dev/null 2>&1; then
      if ! "setup_${service}_auth"; then
        failed_services+=("$service")
      fi
    else
      echo "⚠ Unknown service: $service (skipping)"
      failed_services+=("$service")
    fi
  done

  # Report failures but don't block startup
  if [ ${#failed_services[@]} -gt 0 ]; then
    echo "⚠ Some credentials not configured: ${failed_services[*]}"
    echo "  Container will start, but some features may require authentication"
  fi

  return 0  # Never block container startup
}

# GitHub CLI authentication
# Primary config in $HOME/.config/gh (owned by vscode, not affected by bind mounts).
# Supports import from shared volume and legacy workspace cache.
setup_github_auth() {
  export GH_CONFIG_DIR="${GH_CONFIG_DIR:-$HOME/.config/gh}"
  local SENTINEL_FILE
  SENTINEL_FILE="$(_get_state_dir)/gh-auth-checked"
  local SHARED_GH_DIR="/home/vscode/.shared-auth/gh"

  # Ensure directories exist with correct ownership
  mkdir -p "$(dirname "$SENTINEL_FILE")" "$GH_CONFIG_DIR" 2>/dev/null || true
  chmod 700 "$GH_CONFIG_DIR" 2>/dev/null || true

  local HOSTS_FILE="$GH_CONFIG_DIR/hosts.yml"

  # Fix Docker volume ownership: Docker creates named volumes as root:root
  if [ -d "$SHARED_GH_DIR" ] && [ ! -w "$SHARED_GH_DIR" ]; then
    sudo chown -R "$(id -u):$(id -g)" "$SHARED_GH_DIR" 2>/dev/null || true
  fi

  # One-time migration from legacy workspace-local cache (temp/auth/gh-config)
  if [ ! -f "$HOSTS_FILE" ]; then
    local LEGACY_GH_DIR
    LEGACY_GH_DIR="$(_get_project_auth_dir)/gh-config"
    if [ -d "$LEGACY_GH_DIR" ]; then
      _cred_log INFO "Migrating gh credentials from legacy workspace cache → $GH_CONFIG_DIR"
      for f in hosts.yml config.yml; do
        if sudo test -f "$LEGACY_GH_DIR/$f" 2>/dev/null; then
          sudo cp "$LEGACY_GH_DIR/$f" "$GH_CONFIG_DIR/$f"
          sudo chown "$(id -u):$(id -g)" "$GH_CONFIG_DIR/$f"
        fi
      done
      chmod 600 "$GH_CONFIG_DIR/hosts.yml" 2>/dev/null || true
    fi
  fi

  # Defensive re-check: re-import from shared if local is empty but shared has credentials
  if [ -f "$SENTINEL_FILE" ]; then
    if [ ! -f "$HOSTS_FILE" ] && [ -d "$SHARED_GH_DIR" ] && [ -f "$SHARED_GH_DIR/hosts.yml" ]; then
      _cred_log INFO "Re-importing gh credentials from shared volume (local was empty)"
      cp "$SHARED_GH_DIR/hosts.yml" "$HOSTS_FILE"
      chmod 600 "$HOSTS_FILE"
      if [ -f "$SHARED_GH_DIR/config.yml" ] && [ ! -f "$GH_CONFIG_DIR/config.yml" ]; then
        cp "$SHARED_GH_DIR/config.yml" "$GH_CONFIG_DIR/config.yml"
      fi
      echo "✓ GitHub CLI authenticated (re-imported from shared)"
    fi
    return 0
  fi

  # Ensure gh CLI is installed
  if ! command -v gh >/dev/null 2>&1; then
    echo "⚠ GitHub CLI (gh) not installed, skipping GitHub auth"
    return 1
  fi

  # Shared auth volume: import credentials from shared volume
  if [ -d "$SHARED_GH_DIR" ] && [ -f "$SHARED_GH_DIR/hosts.yml" ] && [ ! -f "$HOSTS_FILE" ]; then
    _cred_log INFO "Importing gh credentials from shared volume → $GH_CONFIG_DIR"
    cp "$SHARED_GH_DIR/hosts.yml" "$HOSTS_FILE"
    chmod 600 "$HOSTS_FILE"
    if [ -f "$SHARED_GH_DIR/config.yml" ] && [ ! -f "$GH_CONFIG_DIR/config.yml" ]; then
      cp "$SHARED_GH_DIR/config.yml" "$GH_CONFIG_DIR/config.yml"
    fi
  fi

  # Tier 1: Check for cached credentials
  if [ -f "$HOSTS_FILE" ]; then
    echo "✓ GitHub CLI authenticated (cached)"
    # Shared auth volume: propagate to shared for other containers
    if [ -d "$SHARED_GH_DIR" ] && [ ! -f "$SHARED_GH_DIR/hosts.yml" ]; then
      _cred_log INFO "Exporting gh credentials → shared volume"
      cp "$HOSTS_FILE" "$SHARED_GH_DIR/hosts.yml"
      chmod 600 "$SHARED_GH_DIR/hosts.yml"
      [ -f "$GH_CONFIG_DIR/config.yml" ] && cp "$GH_CONFIG_DIR/config.yml" "$SHARED_GH_DIR/config.yml" 2>/dev/null || true
    fi
    touch "$SENTINEL_FILE"
    return 0
  fi

  # Tier 2: Auto-convert GITHUB_TOKEN if available
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "Converting GITHUB_TOKEN to cached OAuth credentials..."
    if echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null; then
      echo "✓ GitHub CLI authenticated automatically via GITHUB_TOKEN"
      _cred_log INFO "Converted GITHUB_TOKEN to cached credentials"
      # Shared auth volume: propagate to shared for other containers
      if [ -d "$SHARED_GH_DIR" ] && [ -f "$HOSTS_FILE" ] && [ ! -f "$SHARED_GH_DIR/hosts.yml" ]; then
        _cred_log INFO "Exporting converted credentials → shared volume"
        cp "$HOSTS_FILE" "$SHARED_GH_DIR/hosts.yml"
        chmod 600 "$SHARED_GH_DIR/hosts.yml"
        [ -f "$GH_CONFIG_DIR/config.yml" ] && cp "$GH_CONFIG_DIR/config.yml" "$SHARED_GH_DIR/config.yml" 2>/dev/null || true
      fi
      touch "$SENTINEL_FILE"
      return 0
    else
      echo "⚠ Failed to authenticate with GITHUB_TOKEN"
      return 1
    fi
  fi

  # Tier 2.5: Check if gh is authenticated via other mechanisms
  # (credential helpers, codespace token forwarding, keyring, etc.)
  if gh auth status >/dev/null 2>&1; then
    echo "✓ GitHub CLI authenticated"
    _cred_log INFO "gh authenticated via external mechanism (credential helper, keyring, etc.)"
    touch "$SENTINEL_FILE"
    return 0
  fi

  # Tier 3: Interactive fallback - only warn in interactive terminals
  if [ -t 1 ]; then
    echo ""
    echo "⚠ GitHub CLI not authenticated. Please run:"
    echo "  gh auth login"
    echo ""
    echo "Your credentials will be cached across container rebuilds."
    echo ""
  fi

  _cred_log WARN "No gh credentials found after full auth check"

  # Write sentinel even for unauthenticated state to avoid repeated warnings
  touch "$SENTINEL_FILE"

  return 0
}

# Verify and repair credential propagation
# Call from postStartCommand or session startup to ensure credentials
# are available. Re-imports from shared volume if local is empty.
verify_credential_propagation() {
  local GH_DIR="${GH_CONFIG_DIR:-$HOME/.config/gh}"
  local SHARED_GH_DIR="/home/vscode/.shared-auth/gh"
  local repaired=0

  local HOSTS_FILE="$GH_DIR/hosts.yml"

  # GitHub: re-import from shared if local is missing
  if [ ! -f "$HOSTS_FILE" ] && [ -d "$SHARED_GH_DIR" ] && [ -f "$SHARED_GH_DIR/hosts.yml" ]; then
    _cred_log INFO "verify: Re-importing gh credentials from shared volume"
    mkdir -p "$GH_DIR"
    chmod 700 "$GH_DIR" 2>/dev/null || true
    cp "$SHARED_GH_DIR/hosts.yml" "$HOSTS_FILE"
    chmod 600 "$HOSTS_FILE"
    if [ -f "$SHARED_GH_DIR/config.yml" ] && [ ! -f "$GH_DIR/config.yml" ]; then
      cp "$SHARED_GH_DIR/config.yml" "$GH_DIR/config.yml"
    fi
    repaired=$((repaired + 1))
  fi

  # Claude: re-import from shared if local is missing
  local SHARED_CLAUDE_DIR="/home/vscode/.shared-auth/claude"
  local CLAUDE_CREDS="$HOME/.claude/.credentials.json"
  if [ ! -f "$CLAUDE_CREDS" ] && [ -d "$SHARED_CLAUDE_DIR" ] && [ -f "$SHARED_CLAUDE_DIR/.credentials.json" ]; then
    _cred_log INFO "verify: Re-importing Claude credentials from shared volume"
    mkdir -p "$HOME/.claude"
    cp "$SHARED_CLAUDE_DIR/.credentials.json" "$CLAUDE_CREDS"
    chmod 600 "$CLAUDE_CREDS"
    repaired=$((repaired + 1))
  fi

  if [ $repaired -gt 0 ]; then
    _cred_log INFO "verify: Repaired $repaired credential(s)"
  fi

  return 0
}

# Claude shared auth volume sync
# Syncs ONLY .credentials.json between local and shared volume.
# NEVER syncs projects/, history.jsonl, or other per-project data.
setup_claude_shared_auth() {
  local SHARED_CLAUDE_DIR="/home/vscode/.shared-auth/claude"
  local CLAUDE_CREDS="$HOME/.claude/.credentials.json"

  # Skip if shared volume not mounted
  [ -d "$SHARED_CLAUDE_DIR" ] || return 0

  # Fix Docker volume ownership: Docker creates named volumes as root:root
  if [ ! -w "$SHARED_CLAUDE_DIR" ]; then
    sudo chown -R "$(id -u):$(id -g)" "$SHARED_CLAUDE_DIR" 2>/dev/null || true
  fi

  # Import: shared → local (pick up auth from another container)
  if [ -f "$SHARED_CLAUDE_DIR/.credentials.json" ] && [ ! -f "$CLAUDE_CREDS" ]; then
    _cred_log INFO "Importing Claude credentials from shared volume → local"
    mkdir -p "$HOME/.claude"
    cp "$SHARED_CLAUDE_DIR/.credentials.json" "$CLAUDE_CREDS"
    chmod 600 "$CLAUDE_CREDS"
  fi

  # Export: local → shared (first-auth propagation)
  if [ -f "$CLAUDE_CREDS" ] && [ ! -f "$SHARED_CLAUDE_DIR/.credentials.json" ]; then
    _cred_log INFO "Exporting Claude credentials → shared volume"
    cp "$CLAUDE_CREDS" "$SHARED_CLAUDE_DIR/.credentials.json"
    chmod 600 "$SHARED_CLAUDE_DIR/.credentials.json"
  fi

  return 0
}

# Claude Code authentication
# Checks for cached credentials or ANTHROPIC_API_KEY
setup_claude_auth() {
  # Sync with shared auth volume before checking local credentials
  setup_claude_shared_auth

  local CLAUDE_CREDS="$HOME/.claude/.credentials.json"

  # Check cached credentials first (works regardless of CLI)
  if [ -f "$CLAUDE_CREDS" ]; then
    echo "✓ Claude Code authenticated"
    return 0
  fi

  # API key is sufficient without CLI installed
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    echo "✓ Claude Code: ANTHROPIC_API_KEY detected"
    return 0
  fi

  if ! command -v claude >/dev/null 2>&1; then
    echo "⚠ Claude CLI not installed, skipping Claude auth"
    return 0
  fi

  echo ""
  echo "⚠ Claude Code not authenticated. Please run:"
  echo "  claude login"
  echo ""
  return 0
}

# Cloudflare authentication
# Supports both API token and Wrangler OAuth
setup_cloudflare_auth() {
  local AUTH_DIR
  AUTH_DIR="$(_get_project_auth_dir)"
  local CF_TOKEN_FILE="$AUTH_DIR/cloudflare_api_token"
  local WRANGLER_CONFIG_DIR="$AUTH_DIR/wrangler"

  # Create wrangler config directory
  mkdir -p "$WRANGLER_CONFIG_DIR"
  chmod 700 "$WRANGLER_CONFIG_DIR"

  # Tier 1: Check for cached credentials (API token or Wrangler config)
  if [ -f "$CF_TOKEN_FILE" ]; then
    echo "✓ Cloudflare API token found in cache"
    export CLOUDFLARE_API_TOKEN="$(cat "$CF_TOKEN_FILE")"
    # Load cached account ID if available
    if [ -f "$AUTH_DIR/cloudflare_account_id" ]; then
      export CLOUDFLARE_ACCOUNT_ID="$(cat "$AUTH_DIR/cloudflare_account_id")"
    fi
    return 0
  fi

  # Check for cached Wrangler config
  if [ -f "$WRANGLER_CONFIG_DIR/default.toml" ]; then
    echo "✓ Wrangler config found in cache"
    mkdir -p ~/.wrangler/config
    ln -sf "$WRANGLER_CONFIG_DIR/default.toml" ~/.wrangler/config/default.toml
    return 0
  fi

  # Tier 2: Auto-cache CLOUDFLARE_API_TOKEN if set
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    echo "${CLOUDFLARE_API_TOKEN}" > "$CF_TOKEN_FILE"
    chmod 600 "$CF_TOKEN_FILE"
    echo "✓ Cloudflare API token cached from environment"
    # Cache account ID if provided
    if [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
      echo "${CLOUDFLARE_ACCOUNT_ID}" > "$AUTH_DIR/cloudflare_account_id"
      chmod 600 "$AUTH_DIR/cloudflare_account_id"
      export CLOUDFLARE_ACCOUNT_ID
    fi
    return 0
  fi

  # Tier 3: Interactive fallback
  echo "⚠ Cloudflare credentials not found. Options:"
  echo "  1. Set CLOUDFLARE_API_TOKEN environment variable"
  echo "  2. Run: wrangler login"
  echo ""

  return 0
}
