# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
