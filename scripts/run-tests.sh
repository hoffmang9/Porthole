#!/usr/bin/env bash
# Run E2E checks against an existing dist/ build. Requires ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Running bundle and build verification tests"
swift test

echo "==> Smoke-launching universal app"
BIN="dist/Porthole-universal.app/Contents/MacOS/Porthole"
if [[ ! -x "$BIN" ]]; then
    echo "error: missing $BIN — run ./build.sh first" >&2
    exit 1
fi

"$BIN" &
APP_PID=$!

cleanup() {
    if kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

for _ in $(seq 1 50); do
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        echo "error: Porthole exited early during smoke launch" >&2
        exit 1
    fi
    sleep 0.1
done

echo "==> All tests passed"
