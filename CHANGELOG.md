# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- In-app updates through [Sparkle](https://github.com/sparkle-project/Sparkle): a new version is downloaded, verified against an EdDSA signature and installed from within the app, replacing the manual download-and-drag routine.
- Dot next to the menu bar icon while an update is pending.
- Notification when a check finds a new version, posted once per version.
- Status footer in Settings with the running version and a link to the project on GitHub.
- Releases carry a signed `appcast.xml` asset, which is the feed the app reads.

### Changed

- Update checks run on Sparkle's schedule — at launch and every 6 hours — instead of a hand-rolled poll of the GitHub API at launch and on panel open. Sparkle never opens a window on its own: the menu bar dot and the notification are the reminder.
- Settings → Updates offers **Install** in place of the **Download** button that opened the release page.
- Settings → Updates no longer repeats the running version, which moved to the footer.
- `release.sh` refuses to publish a release whose `CFBundleVersion` was not bumped, since that is the value Sparkle compares.

### Removed

- The hand-written GitHub Releases poll and its version parsing, superseded by Sparkle's feed.
- The Gatekeeper hint under the update button. It described the manual download Sparkle replaces, and its advice (right-click → Open) no longer works on the macOS versions this app supports.

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
