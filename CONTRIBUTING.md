# Contributing to DisplayAnchor

Thanks for helping improve DisplayAnchor. Small, focused changes are easiest to review.

## Before opening an issue

Search existing issues first. For a display-layout problem, include the output from
**Display details → Copy** in the app and explain the expected and actual layout.
Please remove monitor names, UUIDs, serial numbers, or any other details you do not
want to share: the diagnostics are useful but can identify specific hardware.

## Pull requests

- Create a branch from `main`; do not commit directly to `main`.
- Keep each pull request scoped to one change and explain how you tested it.
- Add or update tests for deterministic logic where practical.
- Run `swift test` and `./build.sh` on macOS before requesting review.
- Do not commit generated `build/`, `.build/`, secrets, or Sparkle private keys.

The app needs macOS 26 and Xcode 26 (Swift 6.2). Display configuration behavior must
be tested manually with real monitor/dock configurations.

By contributing, you agree that your contributions are licensed under the MIT License.
