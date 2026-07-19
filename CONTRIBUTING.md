# Contributing

Thanks for your interest in Porthole.

## Building

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`):

```bash
./build.sh
```

Release bundles land in `dist/`. To run the full end-to-end suite:

```bash
./scripts/test-e2e.sh
```

To build only:

```bash
./build.sh
open dist/Porthole-universal.app
```

## Linting and formatting

Install [pre-commit](https://pre-commit.com/) once, then enable hooks:

```bash
pip install pre-commit
pre-commit install
```

Hooks format Swift files, run shellcheck on shell scripts, then run
`./scripts/lint.sh` (strict swift-format). To run the same checks manually:

```bash
pre-commit run --all-files
```

Swift-only strict lint:

```bash
./scripts/lint.sh
```

To format Swift without committing:

```bash
swift format format --in-place --recursive --configuration .swift-format Sources Tests
```

## Pull requests

1. Open an issue first for large changes so we can agree on scope — Porthole
   stays small by design.
2. Keep changes focused. Prefer small extensions in `Sources/Porthole/` over
   new dependencies or project structure. Capture-session work belongs in
   `CaptureSessionCoordinator`; window/UI wiring stays in `main.swift`.
3. CI must pass (`pre-commit run --all-files` and `./scripts/test-e2e.sh` on macOS).
4. Match existing style: run `pre-commit run --all-files` before pushing; use
   `./scripts/lint.sh` for Swift-only checks while iterating. System frameworks
   only, no storyboards or nibs.

## Releases

Maintainers publish pre-built `.app` bundles from `dist/` on GitHub Releases.
If you are building for your own use, change `CFBundleIdentifier` in
`Info.plist` and sign with your Developer ID.

## License

By contributing, you agree that your contributions are licensed under the
[Apache License, Version 2.0](LICENSE).
