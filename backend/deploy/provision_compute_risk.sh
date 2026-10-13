#!/usr/bin/env bash
# Explicit cloud operation: requires pre-existing image, APIs, accounts and IAM.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$#:${1:-}" in
  0:) MODE=provision ;;
  1:--one-time) MODE=one-time ;;
  *) echo "Usage: $0 [--one-time]" >&2; exit 2 ;;
esac
exec "${PYTHON:-python}" -B "${SCRIPT_DIR}/compute_risk_control.py" "$MODE"
