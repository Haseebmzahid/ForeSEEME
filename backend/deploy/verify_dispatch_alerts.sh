#!/usr/bin/env bash
# Explicit dispatch cloud operation; prerequisites must already exist.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python}" -B "${SCRIPT_DIR}/dispatch_alerts_control.py" verify "$@"
