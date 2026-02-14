#!/usr/bin/env bash
set -euo pipefail

if ! command -v bd >/dev/null 2>&1; then
  echo "bd not found in PATH" >&2
  exit 1
fi

bd init
