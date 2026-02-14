#!/usr/bin/env bash
set -euo pipefail

install_pre_push_hook() {
  local workspace_root=$1

  local hook_path="${workspace_root}/.git/hooks/pre-push"
  if [[ -f "$hook_path" ]]; then
    chmod +x "$hook_path"
    echo "  ✔ Git pre-push hook installed"
    return 0
  fi

  cat > "$hook_path" << 'HOOK_EOF'
#!/bin/bash
# Pre-push hook: Warn about direct main commits

current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)

if [[ "$current_branch" == "main" ]]; then
  # Derive worktree directory name from workspace folder name
  workspace_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  worktrees_dir="../${workspace_name}-worktrees"

  echo ""
  echo "⚠️  WARNING: You're pushing directly to main from the main worktree"
  echo ""
  echo "Consider using a git worktree for isolated development:"
  echo "  git worktree add ${worktrees_dir}/feature/<branch> -b feature/<branch>"
  echo ""
  echo "Benefits of worktrees:"
  echo "  - Physical isolation (separate directory per branch)"
  echo "  - No branch switching needed"
  echo "  - Main worktree stays clean on main branch"
  echo "  - Zero file system conflicts between agents"
  echo ""
  echo "See AGENTS.md 'Git Worktrees for Multi-Agent Development' section for details."
  echo ""
  echo "Proceeding with push to main..."
  echo ""
fi

exit 0
HOOK_EOF

  chmod +x "$hook_path"
  echo "  ✔ Git pre-push hook created and installed"
}
