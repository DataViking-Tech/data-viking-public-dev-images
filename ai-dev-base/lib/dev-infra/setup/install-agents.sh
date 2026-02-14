#!/usr/bin/env bash
# Install agent config files into the current project workspace.
# Called from devcontainer postCreateCommand (via image LABEL).
# Idempotent: does not overwrite existing project files.
set -euo pipefail

GITHUB_AGENTS_SRC="/opt/agent-configs/github-agents"
GITHUB_AGENTS_DST=".github/agents"

# Install GitHub Copilot workspace agents
if [ -d "$GITHUB_AGENTS_SRC" ] && [ "$(ls -A "$GITHUB_AGENTS_SRC" 2>/dev/null)" ]; then
  mkdir -p "$GITHUB_AGENTS_DST"
  for f in "$GITHUB_AGENTS_SRC"/*; do
    basename="$(basename "$f")"
    if [ ! -e "$GITHUB_AGENTS_DST/$basename" ]; then
      cp "$f" "$GITHUB_AGENTS_DST/$basename"
    fi
  done
fi
