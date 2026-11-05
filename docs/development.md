# Development

Read [Architecture](architecture.md) for ownership and display behavior, and [Contributing](../CONTRIBUTING.md) for contribution and diagnostics guidance.

## Toolchain and dependencies

Development requires macOS 26 and Xcode 26 with Swift 6.2. [Package.swift](../Package.swift) defines the toolchain, deployment target, dependencies, and resource processing. SwiftPM resolves MenuBarKit from GitHub by default. When a sibling MenuBarKit checkout exists, the manifest selects that local package instead, which allows work on both projects together.

The minimum remote MenuBarKit version is 1.2.0. Local builds use the sibling checkout's current contents, regardless of its tags; check its revision when validating a dependency update.

SwiftPM caches the evaluated manifest. Adding or removing the sibling checkout can leave the old dependency choice cached even though the filesystem changed. Purge the package cache and reset package state after switching; reset alone does not clear the shared manifest cache.

## Building and running

Use [build.sh](../build.sh) to build and assemble the app. It produces a Universal Binary for Apple Silicon and Intel in build/DisplayAnchor.app, copies localized resource bundles, derives the app icon from AppIcon.png, embeds Sparkle, adds the framework search path, and ad-hoc signs and verifies the bundle.

A plain SwiftPM build does not assemble these pieces. Notifications, launch at login, and updates need the built app bundle; an unbundled run is insufficient for validating those behaviors. Missing Sparkle embedding or its search path can prevent launch. Missing resource copies can leave a build dependent on the source checkout.

Interactive builds offer installation to Applications and can replace an existing copy. Decline the prompt to test from build/. Non-interactive builds skip installation. The build script is the source of truth for packaging steps.

## Validation

The project's automated checks are the SwiftPM test suite and swift-format; the bundle check is the build script. Run them on macOS before requesting review, as required by Contributing. The workflow in .github/workflows runs the format check, the Swift tests, and the release-tool tests for pull requests to main and before every release build.

swift-format ships with the Swift toolchain. [.swift-format](../.swift-format) holds the configuration: four-space indentation and 120-column lines. Format the files you change in place and run the strict lint over Package.swift, Sources, and Tests; the workflow fails on any lint finding.

The Python standard-library suite in [scripts/test_appcast.py](../scripts/test_appcast.py) covers changelog extraction, embedded-note and signature preservation, stable/RC feed merging, duplicate-build rejection, and publication to an isolated temporary Git remote. It runs through unittest discovery in the scripts directory and does not publish to GitHub or access credentials.

The scripts directory contains release tooling and its tests. Merging the XML feed uses Python 3's standard library; publishing uses Git and Bash. No Python packages need installation, and these scripts are not copied into DisplayAnchor.app. Users of the distributed app need neither Python nor Git.

Existing tests use Swift Testing and live in [Tests/DisplayAnchorTests](../Tests/DisplayAnchorTests). Use the matching test file when changing deterministic behavior.

| Test file                           | Coverage                                                                       |
| ----------------------------------- | ------------------------------------------------------------------------------ |
| LayoutModelsTests.swift             | EDID key format and the pinned display-set fingerprint                         |
| ProfileStoreTests.swift             | Reload, corrupt-file backup, blocked writes, and failed-write recovery         |
| LocalizationTests.swift             | Same keys and format specifiers in every bundled language, and display counts  |
| DisplayGeometryTests.swift          | Translation and order independence, drift detection, and ambiguous identities  |
| DisplayMapGeometryTests.swift       | Scaling, centering, adjacency, negative coordinates, and mixed orientations    |
| LayoutEditingTests.swift            | Snapping, overlap resolution, draft conversion, and indistinguishable displays |
| DisplayCountIconTests.swift         | Template rendering and display-count bounds                                    |
| UpdateControllerTests.swift         | No-update completion, update-check error handling, and skipped versions        |
| UpdateChannelTests.swift            | Stable defaults, persisted opt-in, channel filtering, and stale RC responses   |
| DeferredUpdateUserDriverTests.swift | Silent scheduled offers, single dismissal, and channel filtering of offers     |
| DisplayMonitorTests.swift           | Event suppression while overlapping display changes of the app are applied     |

Display writes and callback timing need real hardware. Select manual checks that exercise the changed behavior:

- Reconnect a dock with a saved layout, both with automatic restore enabled and disabled. Confirm the saved profile is preserved and an already matching layout stays stable.
- Change the main display, rotate, and apply or cancel an editor draft. Check relative positions, resolution, and the temporary automatic-restore pause.
- Exercise multiple display sets and same-model monitors when changing identity logic. Treat indistinguishable hardware as the documented limitation.
- Test the built bundle for notifications, launch at login, and language/resource loading.
- Validate updater changes from an older installed bundle through a signed release, including download, verification, install, and relaunch. See [Releases](releases.md).

A Windows or Linux host can edit and review sources but cannot validate macOS display configuration or the app bundle.

## UI and localization

MenuBarKit owns the shared panel foundation and components. Check its existing capabilities before implementing reusable UI here. App-specific composition and display interactions remain in the local Views directory.

English and Italian tables live under [Resources](../Sources/DisplayAnchor/Resources). To add a language, copy the English language folder to a folder with the new language code and translate the values in Localizable.strings. Keep keys and format specifiers intact, including their argument types. The picker discovers bundled language folders and lists languages in their own names; missing keys fall back to English. Section labels are uppercased by the shared component, so write normal-case values.

AppResources.swift resolves the app's resource bundle and AppConfig.swift selects the language. When adding UI text, update both existing language tables. Test both a forced language and the system-language selection from the assembled app.

## Diagnostics and documentation

For display issues, start with the app's Display details copy action. Unified logs use the subsystem listed in [Architecture](architecture.md); Log.swift defines categories for event timing, policy decisions, display operations, storage, UI, and updates. Use the category that owns the symptom before reading unrelated source. Apply the privacy guidance in Contributing before sharing diagnostics or logs.

Screenshots live in docs/screenshots. Retake them after visible UI changes. Conventions for code and writing are in [Swift style](swift-style.md) and the [Writing guide](writing-guide.md).
