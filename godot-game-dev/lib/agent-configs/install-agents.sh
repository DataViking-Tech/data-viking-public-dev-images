#!/bin/bash
# Install agent configs from the base image into the current project.
# Called from postCreateCommand — only copies agents that don't already exist,
# so downstream projects can override individual agents by providing their own.

# Claude Code agents (.claude/agents/)
if [ -d /opt/agent-configs/claude-agents ]; then
  mkdir -p .claude/agents
  for f in /opt/agent-configs/claude-agents/*.md; do
    name=$(basename "$f")
    [ -f ".claude/agents/$name" ] || cp "$f" ".claude/agents/$name"
  done
fi

# GitHub Copilot workspace agents (.github/agents/)
if [ -d /opt/agent-configs/github-agents ]; then
  mkdir -p .github/agents
  for f in /opt/agent-configs/github-agents/*.md; do
    name=$(basename "$f")
    [ -f ".github/agents/$name" ] || cp "$f" ".github/agents/$name"
  done
fi

# Roo debug rules (.roo/rules-debug/)
if [ -d /opt/agent-configs/roo-rules ]; then
  mkdir -p .roo/rules-debug
  for f in /opt/agent-configs/roo-rules/*.md; do
    name=$(basename "$f")
    [ -f ".roo/rules-debug/$name" ] || cp "$f" ".roo/rules-debug/$name"
  done
fi

# Copilot instructions (.github/copilot-instructions.md)
if [ -f /opt/agent-configs/copilot-instructions.md ]; then
  mkdir -p .github
  [ -f ".github/copilot-instructions.md" ] || cp /opt/agent-configs/copilot-instructions.md .github/copilot-instructions.md
fi
