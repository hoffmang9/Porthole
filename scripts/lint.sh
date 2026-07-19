#!/usr/bin/env bash
# Strict Swift lint checks. Shell scripts are checked by pre-commit's shellcheck hook.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift-format"
swift format lint --strict --recursive --configuration .swift-format Sources Tests

echo "==> All lint checks passed"
