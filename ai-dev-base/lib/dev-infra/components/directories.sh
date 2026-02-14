#!/usr/bin/env bash
set -euo pipefail

create_directories_from_file() {
  local workspace_root=$1
  local directory_file=$2
  local gitignore="${workspace_root}/.gitignore"
  local section_header="# Project directories (added by dev-infra)"
  local needs_gitignore_update=false
  local dirs_to_add=()

  while read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ -d "$dir" ]] || mkdir -p "$dir"

    # Normalize to basename with trailing slash for gitignore
    local entry
    entry="$(basename "$dir")/"

    # Check if already in .gitignore
    if [ ! -f "$gitignore" ] || ! grep -qx "$entry" "$gitignore" 2>/dev/null; then
      dirs_to_add+=("$entry")
      needs_gitignore_update=true
    fi
  done < "$directory_file"

  # Append new entries to .gitignore under a section header
  if $needs_gitignore_update && [ ${#dirs_to_add[@]} -gt 0 ]; then
    # Add section header if not already present
    if [ ! -f "$gitignore" ] || ! grep -qxF "$section_header" "$gitignore" 2>/dev/null; then
      # Add blank line separator if file exists and doesn't end with newline/blank
      if [ -f "$gitignore" ] && [ -s "$gitignore" ]; then
        echo "" >> "$gitignore"
      fi
      echo "$section_header" >> "$gitignore"
    fi

    for entry in "${dirs_to_add[@]}"; do
      echo "$entry" >> "$gitignore"
    done
  fi

  echo "  ✔ Project directories created"
}
