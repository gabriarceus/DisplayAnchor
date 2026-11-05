# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Dates, display details, and tint names follow the selected language. The built-in display shows the system's name for it.
- The release workflow is the only publication path. It runs the Swift tests and stops when the tag does not match Info.plist or the release already exists; release.sh now checks the version and pushes the tag.

### Fixed

- An unreadable saved-layouts file that cannot be backed up is no longer overwritten by the next save.
- Rotating one of two same-model monitors with different serial numbers no longer rotates the other one.

### Removed

- Per-release appcast assets and the feed-override cleanup for release candidates 1 and 2.

## [1.1.0] - 2026-11-04

### Added

- In-app updates through [Sparkle](https://github.com/sparkle-project/Sparkle), with signed downloads, installation, and relaunch.
- Menu bar update indicator and a notification shown once per available version.
- Settings footer with the running version and a link to the project on GitHub.
- Update channel selection: Stable by default, with an opt-in for release candidates.

### Changed

- Install replaces the manual Download link, with a compact confirmation and a scrollable changelog when release notes are available.
- Raised the minimum MenuBarKit version to 1.2.0.
- Release tooling publishes a shared Stable/RC appcast, preserves archive signatures, and rejects reused build numbers. Candidate releases are marked as prereleases.
- Shortened the README and moved usage, architecture, development, and release guidance into dedicated documents.
- Update checks run silently at launch and every six hours. Manual checks remain available when automatic checks are disabled.

### Fixed

- Switching update channels during an active session waits for completion and checks the latest selection without getting stuck on Checking.
- Up-to-date checks no longer show a failed result after Sparkle completes the check.

### Removed

- Custom GitHub release polling and the outdated Gatekeeper hint in update settings.

## [1.0.1] - 2026-08-20

### Added

- GitHub Actions CI/CD workflow to build and release universal binaries.
- Universal 2 Binary build (`arm64` + `x86_64`) supporting both Apple Silicon and Intel Macs natively.

### Fixed

- Fixed residual references to the old name "Display Layout" in the popover header and menu bar status item accessibility descriptions.

## [1.0.0] - 2026-08-11

### Added

- Automatic and manual display layout restoration on display reconnect / dock replug.
- Background update checker for GitHub Releases.
- Initial release of DisplayAnchor.
- Menu bar popover with display minimap, status badge, and multi-display arrangement editor.
