#!/usr/bin/env bash
set -euo pipefail

configure_shell_aliases() {
  local python_venv=$1
  local bashrc="${HOME}/.bashrc"
  local marker="# >>> dev-infra aliases >>>"

  if ! grep -q "$marker" "$bashrc" 2>/dev/null; then
    cat >> "$bashrc" << EOF_ALIAS
$marker
alias python='${python_venv}/bin/python'
alias python3='${python_venv}/bin/python3'
# <<< dev-infra aliases <<<
EOF_ALIAS
    echo "  ✔ Shell aliases configured"
  else
    echo "  ✔ Shell aliases already configured"
  fi
}
