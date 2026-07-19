# Contributing

Thanks for your interest in Porthole.

## Building

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`):

```bash
./build.sh
```

Release bundles land in `dist/`. To run locally during development:

```bash
swift build -c release
open dist/Porthole-universal.app   # after build.sh
```

## Pull requests

1. Open an issue first for large changes so we can agree on scope — Porthole
   stays small by design.
2. Keep changes focused. Prefer extending the single source file over adding
   dependencies or project structure.
3. CI must pass (`./build.sh` on macOS).
4. Match existing style: minimal comments, system frameworks only, no
   storyboards or nibs.

## Releases

Maintainers publish pre-built `.app` bundles from `dist/` on GitHub Releases.
If you are building for your own use, change `CFBundleIdentifier` in
`Info.plist` and sign with your Developer ID.

## License

By contributing, you agree that your contributions are licensed under the
[Apache License, Version 2.0](LICENSE).
