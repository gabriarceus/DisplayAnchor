# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The update window shows these notes without the Maintenance entries.

## [1.2.1] - 2026-11-07

### Fixed

- The right-click Rotate menu on a display shows a checkmark for the currently active rotation angle.
- When the language setting is set to System, the app follows the macOS system language instead of defaulting to English.

### Maintenance

- Publish the version changelog to the GitHub Release body instead of auto-generating from pull requests.

## [1.2.0] - 2026-11-05

### Added

- In Display details, a Copy button appears when the pointer is over a display and copies the diagnostics of that display only. The button for every display is now called Copy all.
- The Settings footer shows the MenuBarKit version below the app version.

### Changed

- Action buttons and links in the panel, such as Display details, Copy all, delete, the layout editor controls, and the GitHub link, show an outline, so they no longer look like labels.
- Dates, display details, and tint names follow the language selected in the app. The built-in display shows the name macOS gives it.
- Display details list each value on its own labeled line. Hardware identifiers are no longer formatted like quantities, and a serial number the monitor does not report shows "—" instead of 0, also in copied diagnostics.
- In the layout editor, a display dropped away from the others moves next to the nearest display, because macOS cannot use a detached display. Displays stay inside the editor area, which centers on the arrangement after each move without changing the zoom.
- The Apply button of the layout editor looks disabled while there is nothing to apply.
- The delete confirmation of a saved layout appears faster, hides the other row details without moving the row, and stays for 5 seconds.
- The Display details bar, with Copy all, stays in place while you scroll the list of displays.
- The GitHub link in Settings shows the GitHub logo and the word GitHub instead of the repository name.
- The menu bar and saved-layout icons draw each display at its relative size and height in the arrangement, and the main display is no longer drawn smaller than the others.
- The update window shows what is new in the latest three versions, with formatted headings and lists, and lets you install the update, skip the version, or be reminded later.
- The wait setting in Settings has a shorter label and a smaller field.
- When you rename a saved layout, Escape cancels the change, a click on an empty part of the panel or closing the panel keeps the new name, and the row keeps its height.

### Fixed

- An unreadable saved-layouts file that cannot be backed up is no longer overwritten by the next save.
- Automatic restore also runs when the app starts, for example at login, if the displays differ from the saved layout.
- Automatic restore no longer reacts to the app's own display changes when two of them overlap, for example a restore during a rotation.
- Check now is disabled while an update waits to be installed, instead of doing nothing; Install shows that update.
- In the layout editor, two monitors that macOS cannot tell apart can be moved and made the main display separately.
- Launch at login explains when macOS needs approval, with a button that opens Login Items, and when macOS cannot register the app.
- Rotating one of two same-model monitors with different serial numbers no longer rotates the other one.
- Skipping a version in the update window removes the update indicator right away.
- The wait field in Settings stops editing on Escape or on a click elsewhere in the panel.

### Maintenance

- Added tests for event suppression during the app's own display changes, for display counts, and for skipped updates. A failed resolution change is logged.
- Added the Swift style and writing guides, a swift-format configuration, and a format check that runs with the tests for pull requests and releases.
- Panel tooltips, the Edit menu, launch at login, and the menu bar icon and panel placement use the shared MenuBarKit helpers.
- Release notes are built as Markdown from this changelog and leave out Maintenance entries.
- Removed the per-release appcast assets and the feed-override cleanup for release candidates 1 and 2.
- Rotation falls back to the first monitor with the same vendor and product when no monitor reports a matching serial number, as before 1.2.0.
- The release workflow is the only publication path. It runs the tests and stops when the tag does not match Info.plist or the release already exists; release.sh checks the version and pushes the tag.
- The saved-layout rename field and the wait field use the MenuBarKit helper that ends text editing on an outside click. Raised the minimum MenuBarKit version to 1.3.0.

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
