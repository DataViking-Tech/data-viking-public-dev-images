#!/usr/bin/env bash
set -euo pipefail

HOOK_DIR=${1:-""}
if [[ -z "$HOOK_DIR" ]]; then
  GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)
  if [[ -z "$GIT_DIR" ]]; then
    echo "Error: not a git repository" >&2
    exit 1
  fi
  HOOK_DIR="$GIT_DIR/hooks"
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

install_hook() {
  local name="$1"
  local target="$HOOK_DIR/$name"
  cp "$SCRIPT_DIR/$name.sh" "$target"
  chmod +x "$target"
  echo "Installed $name hook -> $target"
}

install_hook pre-commit
install_hook post-checkout
