#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Components live alongside setup/ under the same parent (/opt/dev-infra/)
COMPONENTS_DIR="${SCRIPT_DIR}/.."

source "${COMPONENTS_DIR}/directories.sh"
source "${COMPONENTS_DIR}/python_venv.sh"
source "${COMPONENTS_DIR}/worktrees.sh"
source "${COMPONENTS_DIR}/git_hooks.sh"
source "${COMPONENTS_DIR}/aliases.sh"

# Args: workspace_root directory_config requirements_file [worktree_dir]

dev_infra_project_setup() {
  local workspace_root=$1
  local directory_config=$2
  local requirements_file=$3
  local worktree_dir=${4:-"${workspace_root}-worktrees"}

  create_directories_from_file "$workspace_root" "$directory_config"
  setup_python_venv "$workspace_root" "$requirements_file"
  ensure_worktrees_dir "$worktree_dir"
  install_pre_push_hook "$workspace_root"
  configure_shell_aliases "${workspace_root}/temp/python_virtual_env"
  (cd "$workspace_root" && /opt/ai-coding-utils/beads/setup/ensure_beads.sh) || true
}
