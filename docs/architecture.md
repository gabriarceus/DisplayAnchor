# Architecture

DisplayAnchor uses AppKit for the menu bar and app lifecycle, SwiftUI for the panel,
and CoreGraphics, ColorSync, and IOKit for display configuration. It is a SwiftPM
executable, assembled into an app bundle by the build script.

## Source map

Paths in this table are relative to [Sources/DisplayAnchor](../Sources/DisplayAnchor).
Start with the owner of the behavior you need to change.

| Area                    | Files                                                      | Responsibility                                                                               |
| ----------------------- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Bootstrap and lifecycle | main.swift, AppDelegate.swift                              | Accessory activation, service wiring, status item, panel, and menu bar indicators            |
| Settings and resources  | AppConfig.swift, AppResources.swift                        | UserDefaults settings and app resource bundle lookup                                         |
| Display data            | LayoutModels.swift                                         | Saved identities, mode descriptors, display snapshots, profiles, and apply results           |
| Display access          | DisplayEngine.swift                                        | Live snapshots, fingerprints, display matching, configuration, rotation, and diagnostics     |
| Display events          | DisplayMonitor.swift                                       | Reconfiguration callbacks, settle debounce, and suppression of events caused by the app      |
| Restore policy          | LayoutStore.swift                                          | Current state, saved-layout selection, save/restore actions, live edits, and temporary pause |
| Persistence             | ProfileStore.swift                                         | Versioned profile document, atomic writes, and storage issues                                |
| Editor logic            | LayoutEditing.swift                                        | Draft conversion, edge snapping, and overlap resolution                                      |
| Updates                 | UpdateController.swift                                     | Sparkle lifecycle, silent checks, pending state, and install hand-off                        |
| Logging                 | Log.swift                                                  | Unified log categories for restore, engine, monitor, UI, updates, and profiles               |
| Panel navigation        | Views/PanelRootView.swift                                  | Navigation between the main panel, settings, and editor; appearance and tint                 |
| Main panel              | Views/PopoverView.swift, Views/ProfileRowView.swift        | Current-layout summary and saved-layout actions                                              |
| Display map             | Views/DisplayMapView.swift, Views/DisplayMapGeometry.swift | Mini-map, quick actions, and the coordinate transform shared with the editor                 |
| Editor UI               | Views/LayoutEditorView.swift                               | Drag interaction and draft apply/cancel controls                                             |
| Diagnostics UI          | Views/DisplayDetailView.swift                              | Hardware details, copy action, and ambiguous-identity badge                                  |
| Settings UI             | Views/SettingsView.swift                                   | Preferences, launch at login, and update controls                                            |
| Small UI helpers        | Views/DisplayCountIcon.swift, Views/HoverTip.swift         | Display-count icon and hover tips                                                            |
| Translations            | Resources/\*.lproj/Localizable.strings                     | Bundled language tables                                                                      |

External dependencies are declared in [Package.swift](../Package.swift).
[MenuBarKit](https://github.com/gabriarceus/MenuBarKit) owns reusable panel chrome,
navigation, design tokens, controls, notifications, and localization.
[Sparkle](https://github.com/sparkle-project/Sparkle) owns update feed handling,
signature validation, download, installation, and relaunch.

## Display identity and layout selection

A display-set fingerprint selects the profile for the connected hardware. It is an
order-independent hash of vendor, model, serial, and built-in status, with duplicate
identities retained. It does not encode arrangement or ColorSync UUIDs.

Matching a saved display to a live display is a separate step. It prefers an exact
ColorSync UUID, then the vendor/model/serial/built-in identity. Ambiguous groups use
an ordinal based on port order and current position. Each saved display consumes a
distinct live match; an unresolved display makes the restore unmatched.

Two units of the same model can have distinct UUIDs even with zero serial numbers.
Truly indistinguishable hardware still needs a heuristic. Do not treat runtime
display IDs or port order as a permanent hardware identity.

Layout equality compares positions relative to the main display, the main-display
flag, logical and backing-pixel dimensions, and rotation. It ignores enumeration
order and a common translation. This comparison controls drift indicators and
skipping unnecessary restores; it is distinct from both the fingerprint and the
full mode descriptor.

## Reconnect and restore flow

1. DisplayMonitor receives display changes and waits for a quiet period. A dock can
   produce several callbacks for one physical reconnect.
2. LayoutStore refreshes the live snapshot and selects a saved profile by fingerprint.
3. Automatic restore proceeds only when enabled, unpaused, and the layout differs.
   A missing profile or an already matching layout needs no configuration write.
4. DisplayEngine resolves saved displays, applies the configuration, and reports
   applied, already matching, unmatched, or failed. LayoutStore refreshes UI state
   and handles feedback.

App-generated changes pass through the monitor's apply guard. Suppression continues
briefly after the operation because macOS can deliver late callbacks. Keep this guard
around restores and live edits to avoid feedback loops.

Saving is separate from applying. Successful manual edits pause automatic restore so
the app does not immediately undo them. Applying an editor draft changes the live
layout; saving that layout remains an explicit user action.

## Configuration order and geometry

CoreGraphics configures mirroring, modes, and origins in a transaction. Rotation is
written through an IOKit framebuffer probe before that transaction because it can
reset the mode. Allow rotation to settle before restoring resolution and positions.
A rejected rotation is best effort: the geometry transaction can still proceed.

Within the transaction, configure mirroring first, modes second, and origins last.
Mirrored displays follow their master. Translate origins so the chosen main display
lands at the origin while relative positions stay intact. Skip unchanged origins:
reapplying them can make the system call stall. Configuration errors cancel the
transaction rather than completing a partial transaction.

Mode selection prefers matching logical and pixel dimensions, including swapped
dimensions for quarter-turn rotation, then considers refresh rate, flags, and size.
The live list of modes can change after reconnect, so exact restoration is not always
possible. See DisplayEngine.swift for the current selection details.

The editor works on an in-memory draft. LayoutEditing owns display-space snapping
and overlap handling. DisplayMapGeometry owns the transform between display space
and view space. Preserve logical points versus backing pixels, negative origins,
and rotated footprints when changing either map or editor behavior.

## Persistence and settings

ProfileStore stores a versioned JSON document keyed by fingerprint at
`~/Library/Application Support/DisplayAnchor/profiles.json`. Mutations write the
document atomically and publish new in-memory state only after the write succeeds.
Unsupported document versions block writes to avoid discarding unknown data.
Unreadable documents trigger a timestamped backup attempt and a reported issue;
storage errors are also exposed to the UI and logged.

AppConfig writes settings through to UserDefaults. Its defaults and compatibility
handling are the source of truth for preferences. Keep persisted keys and profile
compatibility in mind when changing models. The defaults domain and log subsystem
are `io.github.gabriarceus.DisplayAnchor`.

## Platform and product constraints

- The app is an accessory app with a menu bar panel and no Dock icon.
- The macOS deployment floor comes from the Liquid Glass UI. Display APIs are older;
  lowering the target also requires checking the UI and shared package.
- Display configuration writes require a non-sandboxed app. This rules out the
  current design's distribution through the Mac App Store.
- Ad-hoc signing is the baseline; a paid Apple Developer ID is not required.
  Update trust and packaging constraints are explained in [Releases](releases.md).
- Display operations require neither Accessibility nor Screen Recording access.
  Notifications and launch at login use their own system services.
- Hardware diagnostics can identify a user's monitors. Follow the privacy guidance
  in [Contributing](../CONTRIBUTING.md) when handling reports or log output.

For checks and hardware validation, read [Development](development.md). For user
behavior and hardware limitations, read the [User guide](user-guide.md).
