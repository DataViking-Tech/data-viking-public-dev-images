#!/usr/bin/env bash
set -euo pipefail

ensure_worktrees_dir() {
  local worktree_dir=$1

  if [[ ! -d "$worktree_dir" ]]; then
    if ! mkdir -p "$worktree_dir" 2>/dev/null; then
      sudo mkdir -p "$worktree_dir"
      sudo chown "$(id -u):$(id -g)" "$worktree_dir" 2>/dev/null || true
    fi
    echo "  ✔ Worktrees directory created"
  else
    echo "  ✔ Worktrees directory already exists"
  fi
}
