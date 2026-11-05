# Swift style

These rules apply to every Swift change in this repository. swift-format handles layout (see [Development](development.md#validation)); this guide covers what a formatter cannot check. For comments and documentation, read the [Writing guide](writing-guide.md).

## Scope and reuse

- Make the smallest change that solves the task completely. Do not add options, abstractions, or "for later" code that nobody asked for.
- Before writing a helper, search this repository and [MenuBarKit](https://github.com/gabriarceus/MenuBarKit). MenuBarKit owns panel chrome, navigation, design tokens, controls, notifications, and localization. Reuse what exists, or extend it there when the helper is generic.
- Keep the app focused on display configuration. Window placement, accounts, and telemetry are out of scope.
- Touch only what the task needs. Do not refactor or reformat unrelated code. Mention dead code you notice instead of deleting it.

## Naming

- Name a type or function after its technical behavior, not after the screen or feature that first uses it. DisplayMapGeometry serves both the mini-map and the editor; a name such as EditorGeometry would have been wrong.
- Follow the Swift API Design Guidelines: clear call sites, no abbreviations except well-known ones (ID, UUID, EDID, URL).
- Shared extensions live in a file named after their purpose, such as LocalizedText.swift, not in the first file that needed them.

## Types and branching

- Branch on enums with an exhaustive `switch`, without `default`, so a new case causes a compile error everywhere it matters.
- For system enums that can grow, use `@unknown default` and make the unknown case visible: fail fast or log it.
- Do not hide invalid states behind silent fallbacks. A fallback is acceptable at a persistence boundary, such as an unknown raw value in UserDefaults, and the property documents it (see AppConfig.swift).
- Pick the collection by its invariant: Set for membership, Dictionary for keyed lookup, Array when order or duplicates matter.
- Force unwraps are for values that cannot fail, such as a URL built from a constant. Use `guard` everywhere else.
- Keep a single owner for every constant and format. When two places need the same value, expose it from its owner, as LayoutStore does for the pause duration.

## Concurrency

- Stores, controllers, and views are `@MainActor`. DisplayEngine functions that read NSScreen are `@MainActor` too.
- C and Objective-C callbacks may arrive on any thread. Hop to the main actor before touching state, as DisplayMonitor does.
- Delayed work uses `Task.sleep`, keeps its task handle, cancels the previous task, and checks `Task.isCancelled` after sleeping.
- Every display configuration write runs inside the monitor's `performApplying`, so the app's own changes cannot trigger an automatic restore.

## Errors, data, and logging

- Return the outcome of an operation that can fail (LayoutApplyResult, a Bool plus a ProfileStoreIssue). Do not log a warning and continue as if it worked.
- Never overwrite user data that could not be read safely. ProfileStore blocks writes in that case.
- Log through the category in Log.swift that owns the behavior. Interpolated values are private by default; mark a value `.public` only when a bug report needs it, and remember that display identifiers can identify hardware.
- Saving a layout is always a user action. Restores and reconnect handling must never replace a saved layout.

## SwiftUI and AppKit

- Views read state from LayoutStore, AppConfig, or UpdateController and call their methods. Views never call DisplayEngine to write a configuration.
- All user-visible text goes through the localizer with a key that exists in every Localizable.strings table. LocalizationTests checks keys and format specifiers.
- A small private helper stays in the view that uses it. Move it to its own file when a second file needs it.
- Code that depends on platform behavior, such as gesture handling or menu-bar image rendering, gets an inline comment that names the behavior.

## Tests

- Tests use Swift Testing and live in Tests/DisplayAnchorTests. Each test file covers one source owner; the list is in [Development](development.md#validation).
- Test deterministic logic: geometry, editing, matching, persistence, localization, and update state. A view that only lays out content gets no test.
- Name a test after the behavior it protects, for example `indistinguishableDisplaysKeepSeparateDrafts`.
- A bug fix comes with a test that fails without the fix, when the logic can run without real displays.
- Display writes and callback timing need real hardware. List the manual checks you did not run instead of claiming them.
