#!/usr/bin/env bash
set -euo pipefail

ensure_worktrees_dir() {
  local worktree_dir=$1

  if [[ ! -d "$worktree_dir" ]]; then
    sudo mkdir -p "$worktree_dir"
    echo "  ✔ Worktrees directory created"
  else
    echo "  ✔ Worktrees directory already exists"
  fi
}
