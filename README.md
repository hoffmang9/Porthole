# Porthole

Minimal macOS viewer for UVC video inputs (capture cards, webcams). No
recording, no overhead — it just displays the input, the way QuickTime's
"New Movie Recording" preview does, without the recording machinery.

Frames flow from the UVC driver into an IOSurface, are decoded in hardware
by VideoToolbox, and composited directly by WindowServer via
`AVCaptureVideoPreviewLayer`. The app process never touches pixel data, so
it idles at roughly zero CPU with a live stream.

## Features

- Auto-selects the first external video device on launch — zero-touch on boot
- Hot-plug aware: devices appear/disappear from the picker as they connect
- Device picker fades out when the mouse leaves the window
- Window aspect lock follows the selected device’s active capture format
  (4:3, 16:9, …), falling back to 4:3 with no input
- No dependencies beyond system frameworks

## Window menu

| Command | Shortcut | Action |
| --- | --- | --- |
| Actual Size | ⌘1 | Content size = active capture resolution |
| Double Size | ⌘2 | Content size = 2× capture resolution |
| Enter Full Screen | ⌘F | Toggle full screen |

Sizes clamp to the visible screen when needed. Actual Size and Double Size
are unavailable with no video input or while full screen.

## Building

Requires Xcode Command Line Tools (`xcode-select --install`). No Xcode IDE
needed.

    ./build.sh

This produces three ad-hoc-signed bundles in `dist/`:

- `Porthole-arm64.app` — Apple Silicon
- `Porthole-x86_64.app` — Intel
- `Porthole-universal.app` — both, in one bundle

## Testing

End-to-end tests build all release bundles, validate bundle metadata and
architectures, verify code signatures, smoke-launch the universal app, and
run XCTest checks:

    ./scripts/test-e2e.sh

To re-run XCTest checks and the launch smoke test against an existing `dist/`
build:

    ./scripts/run-tests.sh

## Notes

- macOS 13+ (Ventura or later)
- Camera permission is requested on first launch (`NSCameraUsageDescription`
  is in Info.plist; the binary must run from inside the .app bundle for the
  permission prompt to work)
- To distribute under your own identity, change `CFBundleIdentifier` in
  Info.plist and sign with your Developer ID instead of the ad-hoc signature
  in build.sh
- To launch at login: System Settings → General → Login Items. Enter full
  screen once and macOS restores it on relaunch.

## Releases

Pre-built `.app` bundles are published on GitHub Releases. Each
release includes the three variants from `./build.sh`:

- `Porthole-arm64.app` — Apple Silicon
- `Porthole-x86_64.app` — Intel
- `Porthole-universal.app` — both architectures in one bundle

Bundles are ad-hoc signed. macOS may show a Gatekeeper warning on first
launch; open System Settings → Privacy & Security and choose **Open Anyway**,
or build from source and sign with your own Developer ID.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
