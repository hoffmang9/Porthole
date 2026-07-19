#!/usr/bin/env bash
# End-to-end test entry point: build release bundles, then run all checks.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building release bundles"
./build.sh

"$(dirname "$0")/run-tests.sh"

echo "==> All end-to-end tests passed"
