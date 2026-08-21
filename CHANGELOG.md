# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Dot next to the menu bar icon while an update is pending.
- Notification when a check finds a new version, posted once per version.
- Status footer in Settings with the running version and a link to the project on GitHub.

### Changed

- Background update checks also run every 6 hours and on wake from sleep, instead of only at launch and when the panel is opened.
- A pending update is remembered across launches, so it stays visible while the daily gate holds off the next check.
- Settings → Updates no longer repeats the running version, which moved to the footer.

### Fixed

- A failed background update check no longer hides an update found by an earlier one.

## [1.0.1] - 2026-08-20

### Added

- Universal 2 Binary build (`arm64` + `x86_64`) supporting both Apple Silicon and Intel Macs natively.
- GitHub Actions CI/CD workflow to build and release universal binaries.

### Fixed

- Fixed residual references to the old name "Display Layout" in the popover header and menu bar status item accessibility descriptions.

## [1.0.0] - 2026-08-11

### Added

- Initial release of DisplayAnchor.
- Automatic and manual display layout restoration on display reconnect / dock replug.
- Menu bar popover with display minimap, status badge, and multi-display arrangement editor.
- Background update checker for GitHub Releases.
