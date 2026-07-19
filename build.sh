#!/bin/bash
# Builds Porthole for arm64, x86_64, and universal.
# Run on any Mac with Xcode Command Line Tools:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

make_bundle () {   # $1 = binary path, $2 = output app name
    local APP="dist/$2.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS"
    cp Info.plist "$APP/Contents/"
    cp "$1" "$APP/Contents/MacOS/Porthole"
    codesign --force --sign - "$APP"     # ad-hoc signature
    echo "built $APP  ($(du -sh "$APP" | cut -f1))"
}

mkdir -p dist

swift build -c release --arch arm64
make_bundle ".build/arm64-apple-macosx/release/Porthole" "Porthole-arm64"

swift build -c release --arch x86_64
make_bundle ".build/x86_64-apple-macosx/release/Porthole" "Porthole-x86_64"

# Universal (single .app that runs native on both)
swift build -c release --arch arm64 --arch x86_64
make_bundle ".build/apple/Products/Release/Porthole" "Porthole-universal"
