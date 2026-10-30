# Development

Read [Architecture](architecture.md) for ownership and display behavior, and
[Contributing](../CONTRIBUTING.md) for contribution and diagnostics guidance.

## Toolchain and dependencies

Development requires macOS 26 and Xcode 26 with Swift 6.2. [Package.swift](../Package.swift)
defines the toolchain, deployment target, dependencies, and resource processing.
SwiftPM resolves MenuBarKit from GitHub by default. When a sibling MenuBarKit checkout
exists, the manifest selects that local package instead, which allows work on both
projects together.

The minimum remote MenuBarKit version is 1.2.0. Local builds use the sibling checkout's current contents, regardless of its tags; check its revision when validating a dependency update.

SwiftPM caches the evaluated manifest. Adding or removing the sibling checkout can
leave the old dependency choice cached even though the filesystem changed. Purge the
package cache and reset package state after switching; reset alone does not clear
the shared manifest cache.

## Building and running

Use [build.sh](../build.sh) to build and assemble the app. It produces a Universal
Binary for Apple Silicon and Intel in build/DisplayAnchor.app, copies localized
resource bundles, derives the app icon from AppIcon.png, embeds Sparkle, adds the
framework search path, and ad-hoc signs and verifies the bundle.

A plain SwiftPM build does not assemble these pieces. Notifications, launch at login,
and updates need the built app bundle; an unbundled run is insufficient for validating
those behaviors. Missing Sparkle embedding or its search path can prevent launch.
Missing resource copies can leave a build dependent on the source checkout.

Interactive builds offer installation to Applications and can replace an existing
copy. Decline the prompt to test from build/. Non-interactive builds skip installation.
The build script is the source of truth for packaging steps; avoid maintaining a
second assembly recipe in documentation.

## Validation

The project's automated check is the SwiftPM test suite; the bundle check is the
build script. Run both on macOS before requesting review, as required by Contributing.
The release workflow builds and packages the app but does not currently run the test
suite, so a successful workflow does not establish that the tests pass.

Existing tests use Swift Testing and live in [Tests/DisplayAnchorTests](../Tests/DisplayAnchorTests).
Use the matching test file when changing deterministic behavior.

| Test file                     | Coverage                                                                      |
| ----------------------------- | ----------------------------------------------------------------------------- |
| LayoutModelsTests.swift       | Identity preference, mode scaling, serialization, and apply result equality   |
| DisplayGeometryTests.swift    | Translation and order independence, drift detection, and ambiguous identities |
| DisplayMapGeometryTests.swift | Scaling, centering, adjacency, negative coordinates, and mixed orientations   |
| LayoutEditingTests.swift      | Snapping, overlap resolution, draft conversion, and stable identity           |
| DisplayCountIconTests.swift   | Template rendering and display-count bounds                                   |

Display writes and callback timing need real hardware. Select manual checks that
exercise the changed behavior:

- Reconnect a dock with a saved layout, both with automatic restore enabled and disabled.
  Confirm the saved profile is preserved and an already matching layout stays stable.
- Change the main display, rotate, and apply or cancel an editor draft. Check relative
  positions, resolution, and the temporary automatic-restore pause.
- Exercise multiple display sets and same-model monitors when changing identity logic.
  Treat indistinguishable hardware as the documented limitation.
- Test the built bundle for notifications, launch at login, and language/resource loading.
- Validate updater changes from an older installed bundle through a signed release,
  including download, verification, install, and relaunch. See [Releases](releases.md).

A Windows or Linux host can edit and review sources but cannot validate macOS display
configuration or the app bundle. State which checks remain unrun instead of treating
source inspection as a runtime test.

## UI and localization

MenuBarKit owns the shared panel foundation and components. Check its existing
capabilities before implementing reusable UI here. App-specific composition and
display interactions remain in the local Views directory.

English and Italian tables live under [Resources](../Sources/DisplayAnchor/Resources).
To add a language, copy the English language folder to a folder with the new language
code and translate the values in Localizable.strings. Keep keys and format specifiers
intact, including their argument types. The picker discovers bundled language folders
and lists languages in their own names; missing keys fall back to English.
Section labels are uppercased by the shared component, so write normal-case values.

AppResources.swift resolves the app's resource bundle and AppConfig.swift selects the
language. When adding UI text, update both existing language tables. Test both a forced
language and the system-language selection from the assembled app.

## Diagnostics and documentation

For display issues, start with the app's Display details copy action. Unified logs
use the subsystem listed in [Architecture](architecture.md); Log.swift defines
categories for event timing, policy decisions, display operations, storage, UI, and
updates. Use the category that owns the symptom before reading unrelated source.
Apply the privacy guidance in Contributing before sharing diagnostics or logs.

Screenshots live in docs/screenshots. Review them after visible UI changes; the
existing settings screenshot predates the Sparkle Install control and footer version.
Keep documentation conceptual, with references to owning files rather than copied
code or command blocks. No repository Markdown formatter is currently configured.
