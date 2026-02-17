#!/usr/bin/env bash
set -euo pipefail

# Setup python venv with requirements hash caching
# Args: workspace_root requirements_file

setup_python_venv() {
  local workspace_root=$1
  local requirements_file=$2

  local python_venv="${workspace_root}/temp/python_virtual_env"
  local requirements_hash
  requirements_hash=$(md5sum "$requirements_file" 2>/dev/null | cut -d' ' -f1)
  local cached_hash_file="${python_venv}/.requirements_hash"

  if [[ -f "${python_venv}/bin/python" ]] && [[ -f "$cached_hash_file" ]] && [[ "$(cat "$cached_hash_file" 2>/dev/null)" == "$requirements_hash" ]]; then
    echo "  ✔ Python virtual environment already up to date"
    return 0
  fi

  echo "  ⠋ Installing Python dependencies..."
  uv venv --clear "${python_venv}" --python 3.11 >/dev/null 2>&1
  uv pip install -r "$requirements_file" --python "${python_venv}/bin/python" --link-mode=copy --quiet >/dev/null 2>&1
  echo "$requirements_hash" > "$cached_hash_file"
  echo "  ✔ Python dependencies installed"
}
