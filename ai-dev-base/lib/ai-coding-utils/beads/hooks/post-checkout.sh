#!/usr/bin/env bash
set -euo pipefail

if command -v bd >/dev/null 2>&1; then
  bd sync || true
fi
