# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The update window shows these notes without the Maintenance entries.

## [Unreleased]

### Changed

- Dates, display details, and tint names follow the language selected in the app. The built-in display shows the name macOS gives it.
- The update window shows what is new in the latest three versions, with formatted headings and lists, and lets you install the update, skip the version, or be reminded later.

### Fixed

- An unreadable saved-layouts file that cannot be backed up is no longer overwritten by the next save.
- Automatic restore no longer reacts to the app's own display changes when two of them overlap, for example a restore during a rotation.
- In the layout editor, two monitors that macOS cannot tell apart can be moved and made the main display separately.
- Rotating one of two same-model monitors with different serial numbers no longer rotates the other one.

### Maintenance

- Added the Swift style and writing guides, a swift-format configuration, and a format check that runs with the tests for pull requests and releases.
- Release notes are built as Markdown from this changelog and leave out Maintenance entries.
- Removed the per-release appcast assets and the feed-override cleanup for release candidates 1 and 2.
- The release workflow is the only publication path. It runs the tests and stops when the tag does not match Info.plist or the release already exists; release.sh checks the version and pushes the tag.

## [1.1.0] - 2026-11-04

### Added

- In-app updates through [Sparkle](https://github.com/sparkle-project/Sparkle), with signed downloads, installation, and relaunch.
- Menu bar update indicator and a notification shown once per available version.
- Settings footer with the running version and a link to the project on GitHub.
- Update channel selection: Stable by default, with an opt-in for release candidates.

### Changed

- Install replaces the manual Download link, with a compact confirmation and a scrollable changelog when release notes are available.
- Update checks run silently at launch and every six hours. Manual checks remain available when automatic checks are disabled.

### Fixed

- Switching update channels during an active check waits for it to finish and checks the latest selection without getting stuck on Checking.
- Up-to-date checks no longer show a failed result.

### Maintenance

- Raised the minimum MenuBarKit version to 1.2.0.
- Release tooling publishes a shared Stable/RC appcast, preserves archive signatures, and rejects reused build numbers. Candidate releases are marked as prereleases.
- Shortened the README and moved usage, architecture, development, and release guidance into dedicated documents.

### Removed

- The previous update check based on GitHub releases, and the outdated Gatekeeper hint in update settings.

## [1.0.1] - 2026-08-20

### Added

- Native support for both Apple Silicon and Intel Macs in one app.

### Fixed

- The panel header and the menu bar icon description no longer use the old name "Display Layout".

### Maintenance

- GitHub Actions workflow that builds and releases Universal 2 binaries (`arm64` and `x86_64`).

## [1.0.0] - 2026-08-11

### Added

- Automatic and manual restore of the display layout when displays or a dock reconnect.
- Background check for new releases on GitHub.
- Initial release of DisplayAnchor.
- Menu bar panel with a display mini-map, a status badge, and a multi-display arrangement editor.
