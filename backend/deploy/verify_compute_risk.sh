#!/usr/bin/env bash
# Explicit cloud operation: requires pre-existing image, APIs, accounts and IAM.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python}" -B "${SCRIPT_DIR}/compute_risk_control.py" verify
