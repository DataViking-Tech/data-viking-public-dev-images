#!/bin/bash
set -e

# Enhanced postCreateCommand for devcontainer setup
# Provides: ANSI progress indicators, toolchain validation,
#           MD5-based requirements caching, project_setup.sh integration
#
# Install location: /opt/dev-infra/postCreateCommand-enhanced.sh
# Usage: Source or call from your project's postCreateCommand

# === ANSI Colors and Symbols ===
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color
CHECK="${GREEN}✔${NC}"

# Set workspace root (caller may override via WORKSPACE_ROOT env var)
WORKSPACE_ROOT="${WORKSPACE_ROOT:-${PWD}}"

# Project name for display (defaults to directory name)
PROJECT_NAME="${PROJECT_NAME:-$(basename "$WORKSPACE_ROOT")}"

echo ""
echo -e "${BOLD}${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${BOLD}🚀 Setting up ${PROJECT_NAME}${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Validate base image tools
echo -e "${BOLD}Validating environment...${NC}"
echo ""

# Verify tools are available (soft checks - won't fail if tool missing)
command -v godot >/dev/null 2>&1 && echo -e "  ${CHECK} Godot $(godot --version 2>/dev/null | head -1)"
command -v python3 >/dev/null 2>&1 && echo -e "  ${CHECK} Python $(python3 --version 2>/dev/null | cut -d' ' -f2)"
command -v bun >/dev/null 2>&1 && echo -e "  ${CHECK} Bun $(bun --version 2>/dev/null)"
command -v claude >/dev/null 2>&1 && echo -e "  ${CHECK} Claude CLI $(claude --version 2>/dev/null || echo '(auth needed)')"
command -v bd >/dev/null 2>&1 && echo -e "  ${CHECK} beads $(bd --version 2>/dev/null)"

echo ""
echo -e "${BOLD}Setting up project dependencies...${NC}"
echo ""

# Project setup via dev-infra individual scripts
# dev-infra provided by ai-dev-base at /opt/dev-infra/*.sh
if [ -d "/opt/dev-infra" ]; then
  # Source available dev-infra modules
  [ -f /opt/dev-infra/directories.sh ] && source /opt/dev-infra/directories.sh
  [ -f /opt/dev-infra/python_venv.sh ] && source /opt/dev-infra/python_venv.sh
  [ -f /opt/dev-infra/git_hooks.sh ] && source /opt/dev-infra/git_hooks.sh
  [ -f /opt/dev-infra/aliases.sh ] && source /opt/dev-infra/aliases.sh
  [ -f /opt/dev-infra/worktrees.sh ] && source /opt/dev-infra/worktrees.sh

  # Directory setup (if config file exists)
  if [ -f "${WORKSPACE_ROOT}/.devcontainer/directory_config.txt" ]; then
    type -t create_directories_from_file >/dev/null 2>&1 && \
      create_directories_from_file "${WORKSPACE_ROOT}" ".devcontainer/directory_config.txt"
  fi

  # Python venv setup (if requirements file exists)
  if [ -f "${WORKSPACE_ROOT}/.devcontainer/requirements.txt" ]; then
    type -t setup_python_venv >/dev/null 2>&1 && \
      setup_python_venv "${WORKSPACE_ROOT}" ".devcontainer/requirements.txt"
  fi

  # Git hooks
  type -t install_pre_push_hook >/dev/null 2>&1 && \
    install_pre_push_hook "${WORKSPACE_ROOT}"

  # Shell aliases
  if [ -d "${WORKSPACE_ROOT}/temp/python_virtual_env" ]; then
    type -t configure_shell_aliases >/dev/null 2>&1 && \
      configure_shell_aliases "${WORKSPACE_ROOT}/temp/python_virtual_env"
  fi

  # Worktrees directory (configurable via WORKTREES_DIR)
  if [ -n "${WORKTREES_DIR:-}" ]; then
    type -t ensure_worktrees_dir >/dev/null 2>&1 && \
      ensure_worktrees_dir "${WORKTREES_DIR}"
  fi
else
  echo -e "  ${YELLOW}⚠${NC}  dev-infra not found at /opt/dev-infra, falling back to local setup"

  # Create required directories
  if [ -f "${WORKSPACE_ROOT}/.devcontainer/directory_config.txt" ]; then
    while read -r dir; do
      [ -n "$dir" ] && [ -d "$dir" ] || mkdir -p "$dir"
    done < "${WORKSPACE_ROOT}/.devcontainer/directory_config.txt"
    echo -e "  ${CHECK} Project directories created"
  fi

  # Python venv setup (project-specific requirements)
  if [ -f "${WORKSPACE_ROOT}/.devcontainer/requirements.txt" ]; then
    PYTHON_VENV="${WORKSPACE_ROOT}/temp/python_virtual_env"
    REQUIREMENTS_HASH=$(md5sum "${WORKSPACE_ROOT}/.devcontainer/requirements.txt" 2>/dev/null | cut -d' ' -f1)
    CACHED_HASH_FILE="${PYTHON_VENV}/.requirements_hash"

    if [ -f "${PYTHON_VENV}/bin/python" ] && [ -f "$CACHED_HASH_FILE" ] && [ "$(cat "$CACHED_HASH_FILE" 2>/dev/null)" = "$REQUIREMENTS_HASH" ]; then
      echo -e "  ${CHECK} Python virtual environment ${GREEN}already up to date${NC}"
    else
      echo -e "  ${CYAN}⠋${NC} Installing Python dependencies..."
      uv venv --clear "${PYTHON_VENV}" --python 3.11 >/dev/null 2>&1
      uv pip install -r "${WORKSPACE_ROOT}/.devcontainer/requirements.txt" --python "${PYTHON_VENV}/bin/python" --link-mode=copy --quiet >/dev/null 2>&1
      echo "$REQUIREMENTS_HASH" > "$CACHED_HASH_FILE"
      echo -e "\033[1A\033[K  ${CHECK} Python dependencies installed"
    fi
  fi
fi

# Run project-specific setup if it exists
if [ -f "${WORKSPACE_ROOT}/project_setup.sh" ]; then
  echo ""
  echo -e "${BOLD}Running project-specific setup...${NC}"
  source "${WORKSPACE_ROOT}/project_setup.sh"
fi

echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${BOLD}✨ Environment ready! Happy coding${NC}     ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "Startup time: $(date +%T) (container startup to ready)"
echo ""
