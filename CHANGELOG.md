# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Dot next to the menu bar icon while an update is pending.
- In-app updates through [Sparkle](https://github.com/sparkle-project/Sparkle): a new version is downloaded, verified against an EdDSA signature and installed from within the app, replacing the manual download-and-drag routine. The update verification public key is embedded in the app; local and CI archive signatures are verified, while end-to-end rollout validation remains pending.
- Notification when a check finds a new version, posted once per version.
- Releases carry a signed `appcast.xml` asset, which is the feed the app reads.
- Status footer in Settings with the running version and a link to the project on GitHub.

### Changed

- `release.sh` refuses to publish a release whose `CFBundleVersion` was not bumped, since that is the value Sparkle compares. Both publication paths target the built commit and mark candidate versions as prereleases.
- Raised the minimum MenuBarKit version to 1.2.0, retaining the sibling-checkout workflow for local development.
- Settings → Updates no longer repeats the running version, which moved to the footer.
- Settings → Updates offers **Install** in place of the **Download** button that opened the release page.
- Shortened the README to a project overview and moved usage, architecture, development, and release guidance into dedicated documents, with an agent context entry point.
- Update checks run on Sparkle's schedule — at launch and every 6 hours — instead of a hand-rolled poll of the GitHub API at launch and on panel open. Sparkle never opens a window on its own: the menu bar dot and the notification are the reminder.

### Removed

- The Gatekeeper hint under the update button. It described the manual download Sparkle replaces, and its advice (right-click → Open) no longer works on the macOS versions this app supports.
- The hand-written GitHub Releases poll and its version parsing, superseded by Sparkle's feed.

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
