# DisplayAnchor

A tiny macOS menu bar utility that **remembers and restores your display arrangement**
when you disconnect/reconnect external monitors (typically through a Thunderbolt/USB-C
dock). It works around the well-known macOS bug where the relative positions of your
monitors, the main-display designation, and per-display resolution get scrambled on
replug.

It does only this one thing. No window-position management, no accounts, no telemetry
— and it needs **no special permissions** (no Accessibility, no Screen Recording). The
only thing it ever sends over the network is a check for a new release, which you can
turn off ([Updates](#updates)).

<p align="center">
  <img src="docs/screenshots/panel.png" alt="The DisplayAnchor panel: a mini-map of three displays, a badge confirming the arrangement matches the saved layout, and the list of saved layouts" width="360">
</p>

> [!IMPORTANT]
> **Requires macOS 26 or later**, and the app is **not signed with an Apple Developer ID**
> — the first launch takes two extra clicks. Both points are explained below
> ([Requirements](#requirements), [Opening an unsigned app](#opening-an-unsigned-app)).

> This first part is everything you need to run the app. Building it, its internals, and
> the release process live in [Development](#development), further down.

## What it does

- **Save** a layout manually (button in the popover) when your displays are arranged
  the way you like. The arrangement is captured per _set of connected displays_ and
  stored locally.
- **Restore** happens automatically: when you reconnect and the connected set matches a
  saved layout, the saved arrangement is re-applied (after the configuration settles).
  You can also restore on demand.
- Because saving is always manual, the broken layout macOS produces right after a
  reconnect can never overwrite your good saved layout.

## Requirements

- macOS 26 or later
- Apple Silicon (`arm64`) or Intel (`x86_64`) — pre-built releases are Universal Binaries supporting both architectures natively.

The macOS 26 floor comes from the UI layer (Liquid Glass panel chrome), not from the
display logic, which uses long-standing CoreGraphics APIs. Lowering the deployment
target hasn't been necessary so far, but support for earlier macOS versions may land
in a future release. If you'd find it useful, open an issue — it helps gauge demand.

## Install

Download `DisplayAnchor-x.y.z.zip` from the
[latest release](https://github.com/gabriarceus/DisplayAnchor/releases/latest), unzip it,
and drag **DisplayAnchor.app** into `/Applications`. The first launch takes two extra
clicks — see [Opening an unsigned app](#opening-an-unsigned-app) right below.

The app has no Dock icon and no window: it lives in the menu bar, and everything happens
in the panel that opens when you click its icon.

## Contributing and support

Bug reports and focused pull requests are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md), especially the privacy note before sharing display
diagnostics. Security-sensitive reports should use GitHub's private security advisory
flow rather than a public issue.

Prefer not to run a downloaded binary? [Build it from source](#build-from-source) —
locally built apps skip the Gatekeeper step entirely.

## Opening an unsigned app

DisplayAnchor is **ad-hoc signed**, not signed with a paid Apple Developer ID, and it
is not notarized. There's no developer account behind this project. Practically:

- **Downloading a release** puts macOS Gatekeeper in the way: the first launch is
  blocked with a "cannot be opened because Apple cannot check it for malicious
  software" message. To allow it, open **System Settings → Privacy & Security**,
  scroll to the security section, and click **Open Anyway** next to DisplayAnchor,
  then confirm. You only do this once.

  Equivalently, from the Terminal:

  ```bash
  xattr -d com.apple.quarantine /Applications/DisplayAnchor.app
  ```

- **Building from source** is the smoothest path — locally built apps carry no
  quarantine flag and just open.

Only the first install goes through this. From then on DisplayAnchor updates itself
through Sparkle, which removes the quarantine flag from the bundle it installs, so later
versions launch without the approval step ([Updates](#updates)).

This is the standard situation for any unsigned open-source macOS app. The source is
right here — read it, or build it yourself, if you'd rather not take the binary on
trust.

## Using it

|                                                                             Quick actions                                                                              |                                                                             Layout editor                                                                              |                                                                             Settings                                                                              |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------: | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------: | :---------------------------------------------------------------------------------------------------------------------------------------------------------------: |
| <img src="docs/screenshots/quick-actions.png" alt="Right-click menu on a display: Set as Main Display, Rotate with a 0/90/180/270° submenu, Edit Layout…" width="250"> | <img src="docs/screenshots/layout-editor.png" alt="The layout editor: three displays on a canvas, drag to rearrange, right-click to set the main display" width="250"> | <img src="docs/screenshots/settings.png" alt="Settings: automatic restore, appearance, tint, language, notifications, settle delay, launch at login" width="250"> |

The menu bar icon, the popover title, and each saved-layout row show a row of small
rectangles that mirrors the number of connected displays (up to four). The menu bar
icon still switches to a checkmark right after a restore and to an exclamation mark when
the current arrangement has drifted from the saved one.

Click the menu bar icon to open the popover:

- A **mini-map** of the current arrangement (main display highlighted; rotated
  displays are drawn with their real portrait/landscape footprint and labelled with
  the rotation angle). **Right-click a display** for quick actions:
  - **Set as Main Display** — applied immediately, preserving the relative arrangement.
  - **Rotate** — 0° / 90° / 180° / 270°, applied immediately; the display keeps the
    resolution it had before rotating.
  - **Edit Layout…** — opens the drag-and-drop layout editor (two or more displays).
- The **layout editor**: drag the displays around a canvas to rearrange them — they
  snap flush to their neighbours' edges and cannot overlap. Right-click a display to
  make it the main one. Everything happens on an in-memory draft: ✓ applies the drawn
  arrangement to the real displays, ✗ discards it. Restoring a saved layout also
  restores each display's saved rotation.
- **Display details** (expandable): per-monitor model / serial / vendor / unit / UUID,
  plus a **⚠︎ indistinguishable** badge when two monitors share the same EDID (identical
  model, equal/zero serial). A **Copy** button copies the full diagnostics to the
  clipboard and briefly confirms with a "Copied to clipboard" badge.
- **Save Layout** for a new display set, or **Update Layout** — enabled only when the
  current arrangement has drifted from the saved one.
- A **pause** control (shown only while auto-restore is enabled) that suspends
  automatic restore for 15 minutes so you can rearrange displays freely. Auto-restore
  also pauses itself — with a notification — whenever you change the layout manually
  (set main, rotate, apply an edited layout), so it won't immediately undo your edit.
- The list of **saved layouts**: **double-click a name to rename**, delete (with an
  inline two-step confirm so a stray click can't wipe a layout), and **Restore** the
  current set from its row.
- A footer with **Settings** and **Quit**.

## Settings

| Setting                              | Default | Description                                                                                                                                      |
| ------------------------------------ | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Automatically restore on reconnect   | off     | Re-apply a matching saved layout when displays settle after a change (skipped when the arrangement already matches).                             |
| Appearance                           | System  | Panel appearance: System, Dark, or Light                                                                                                         |
| Tint                                 | None    | Glass tint mode: None, Match macOS (system accent), or Custom with a swatch row (Blue, Purple, Pink, Red, Orange, Yellow, Green, Graphite, Teal) |
| Language                             | System  | UI language: _System_ follows macOS, or force English / Italian ([adding a language](#adding-a-language))                                        |
| Notify when a layout is restored     | on      | Post a notification after an automatic restore.                                                                                                  |
| Wait N seconds after displays change | 3       | How long to wait for the configuration to settle before restoring.                                                                               |
| Launch at login                      | —       | Registers the app via `SMAppService` (built `.app` bundle only).                                                                                 |
| Check for updates automatically      | on      | Let Sparkle poll the update feed in the background and notify you once per version. See [Updates](#updates).                                     |

Saved layouts are stored at
`~/Library/Application Support/DisplayAnchor/profiles.json`
(a versioned JSON document keyed by display-set fingerprint). Settings live in
UserDefaults under `io.github.gabriarceus.DisplayAnchor`.

## Updates

DisplayAnchor updates itself through [Sparkle](https://github.com/sparkle-project/Sparkle):
it reads a signed feed and installs a new version from inside the app, with no manual
download.

- **Where it shows up**: when an update exists you get a notification (once per
  version), a dot next to the menu bar icon, an orange dot on the settings gear in the
  main panel, and an **Install** button in Settings → Updates. The running version sits
  in the footer at the bottom of Settings.
- **How it works**: Sparkle polls `appcast.xml`, published as an asset of the newest
  release, and compares its `sparkle:version` against the running bundle's
  `CFBundleVersion`. A background check runs at launch and every 6 hours, and never
  opens a window of its own — the dot and the notification are the whole reminder
  (Sparkle calls this "gentle reminders"). Its standard flow — release notes, download,
  install, relaunch — appears only when you press **Install**.
- **What is verified**: every update carries an EdDSA (ed25519) signature, checked
  against the public key baked into the app. This is what makes in-app updates possible
  with no Apple Developer ID: Sparkle accepts an update on a valid EdDSA signature
  alone and does not require a code-signing identity to match.
- **Gatekeeper**: Sparkle strips the `com.apple.quarantine` flag from the bundle it
  installs, and macOS gates the first-launch approval prompt on that flag — so an update
  installed from inside the app does not ask you to approve it again. That approval is
  still needed once, for the very first install from a downloaded zip (see
  [Opening an unsigned app](#opening-an-unsigned-app)).
- **Turning it off**: the automatic-check toggle. Nothing is sent beyond the feed
  request itself: no identifier, no telemetry, no account.

## Known limitations

1. **Same-model monitors** are distinguished by their ColorSync UUID, which is derived
   from the full EDID and usually differs between two units of the same model even when
   the numeric serial is `0`. Only monitors whose EDID is _byte-identical_ are truly
   indistinguishable; in that case the app falls back to a port-order heuristic and the
   display-details list flags them with a ⚠︎ badge. Truly-identical displays are a
   fundamental macOS limitation, not an app bug.
2. **Rotation** is written through an IOKit framebuffer probe rather than a public
   CoreGraphics call. It works on standard configurations, but the display-to-service
   matching is EDID-based: two _byte-identical_ monitors resolve to the first match,
   so rotating one of two truly indistinguishable displays may rotate the other.
3. **Not sandboxable** ([why](#design-constraints)), so no Mac App Store distribution.
4. **GPU switching** (e.g. eGPU connect/disconnect) can invalidate display UUIDs more
   aggressively; you may need to re-save the layout afterwards.
5. If a monitor reports a different set of modes after reconnect, the closest matching
   resolution is applied.

---

# Development

Everything below is for building, modifying, or releasing the app. You don't need any
of it to use DisplayAnchor.

## Build from source

Requires **Xcode 26 (Swift 6.2)** on macOS 26.

```bash
git clone https://github.com/gabriarceus/DisplayAnchor.git
cd DisplayAnchor
./build.sh
```

`build.sh` asks whether to install to `/Applications` (replacing any existing
copy); answer `n` to keep the app in `build/` and run it from there with
`open "build/DisplayAnchor.app"`. In non-interactive runs (CI, piped)
the question is skipped.

The app is ad-hoc signed and runs as a menu-bar-only accessory app (no Dock icon).
Notifications, launch-at-login and the updater only work from the built `.app` bundle,
not under `swift run`.

`build.sh` also embeds `Sparkle.framework` into `Contents/Frameworks` and links the
executable with an `@executable_path/../Frameworks` rpath — a plain `swift build`
provides neither, so the app would crash on launch without it. It then verifies the
bundle's signature: Sparkle rejects an update whose own signature does not verify, so a
broken ad-hoc signature would ship a version that can never update itself.

The UI foundation (panel, chrome, design tokens, reusable components) lives in the
[`MenuBarKit`](https://github.com/gabriarceus/MenuBarKit) package, shared with the
other menu bar apps; the panel chrome uses Liquid Glass. It is resolved from GitHub by
default — if a `MenuBarKit` checkout sits next to this repo, that local copy is used
instead so you can edit both at once. SwiftPM caches the evaluated manifest keyed by
its contents, which don't change when the sibling appears or disappears — so after
adding or removing it, run `swift package purge-cache && swift package reset` once
(`reset` alone clears `.build` but not the shared manifest cache).

## Under the hood

The app uses public CoreGraphics / Quartz Display Services APIs
(`CGGetActiveDisplayList`, `CGDisplayBounds`, `CGConfigureDisplay*`,
`CGCompleteDisplayConfiguration`) and identifies displays by their ColorSync UUID
(`CGDisplayCreateUUIDFromDisplayID`) with a vendor/model/serial fallback. Connect and
disconnect events are detected with `CGDisplayRegisterReconfigurationCallback`,
debounced until the configuration settles. Rotation is the one thing CoreGraphics
exposes read-only: it is written through the IOKit framebuffer transform
(`IOServiceRequestProbe` with `kIOFBSetTransform`, the fb-rotate technique) and,
because the transform resets the display mode, the previous mode is re-applied once
the rotation settles.

## Design constraints

- The app must remain **non-sandboxed** — writing display configuration is blocked under
  the App Sandbox, so this cannot ship via the Mac App Store.
- It must keep working **without an Apple Developer ID**: ad-hoc signing is the baseline.
  In-app updates are still possible because Sparkle validates them with its own EdDSA
  signature rather than with a code-signing identity — see [Updates](#updates).

## Project layout

| File                                                      | Responsibility                                                                                                                                                                                                                  |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `main.swift`                                              | AppKit bootstrap (accessory activation policy)                                                                                                                                                                                  |
| `AppDelegate.swift`                                       | Status item, panel, dynamic display-count icon                                                                                                                                                                                  |
| `AppConfig.swift`                                         | UserDefaults-backed settings model                                                                                                                                                                                              |
| `LayoutModels.swift`                                      | `Codable` types: identity, mode, snapshot, profile                                                                                                                                                                              |
| `DisplayEngine.swift`                                     | CoreGraphics/ColorSync/IOKit: snapshot, apply, rotation, fingerprint, diagnostics                                                                                                                                               |
| `DisplayMonitor.swift`                                    | Reconfiguration callback, debounce, restore-loop guard                                                                                                                                                                          |
| `LayoutEditing.swift`                                     | Pure editor helpers: draft model, snapping, overlap resolution                                                                                                                                                                  |
| `ProfileStore.swift`                                      | JSON persistence of saved profiles                                                                                                                                                                                              |
| `LayoutStore.swift`                                       | Save/restore policy, live edits (main/rotate/rearrange), published state                                                                                                                                                        |
| `UpdateController.swift`                                  | Sparkle wiring behind [Updates](#updates): silent feed check, own affordances, install hand-off                                                                                                                                  |
| `Views/PanelRootView.swift`                               | Panel navigation between main view, settings, and editor; glass chrome + tint                                                                                                                                                   |
| `Views/PopoverView.swift`                                 | Root popover                                                                                                                                                                                                                    |
| `Views/DisplayMapView.swift`                              | Proportional mini-map with right-click quick actions                                                                                                                                                                            |
| `Views/DisplayMapGeometry.swift`                          | Display-space ↔ view-space transform shared by map and editor                                                                                                                                                                   |
| `Views/LayoutEditorView.swift`                            | Drag-and-drop layout editor (draft, apply/cancel)                                                                                                                                                                               |
| `Views/DisplayDetailView.swift`                           | Per-display diagnostics + indistinguishable badge                                                                                                                                                                               |
| `Views/ProfileRowView.swift`                              | One saved-layout row                                                                                                                                                                                                            |
| `Views/SettingsView.swift`                                | Settings form + launch-at-login                                                                                                                                                                                                 |
| `Views/DisplayCountIcon.swift`                            | Template icon of N rectangles for the display count                                                                                                                                                                             |
| `Views/HoverTip.swift`                                    | Fast-appearing hover tooltip modifier                                                                                                                                                                                           |
| `Resources/*.lproj`                                       | Per-language `Localizable.strings` tables (see [Adding a language](#adding-a-language))                                                                                                                                         |
| [`Sparkle`](https://github.com/sparkle-project/Sparkle)   | Update framework: appcast feed, EdDSA validation, download/install/relaunch. Embedded into the bundle by `build.sh`                                                                                                              |
| [`MenuBarKit`](https://github.com/gabriarceus/MenuBarKit) | Shared package: `MenuBarPanel`, Liquid Glass `PanelChrome` (optional tint), `PanelNavigation`, `Notifier`, `Localizer` + `Bundle.languageOptions`, `Theme` tokens, `PanelHeader`/`SectionLabel`/`GlassIconButton`/`inputChrome` |

## Adding a language

The app ships in **English** and **Italian**. Adding another needs **no code**:

1. Duplicate the folder `Sources/DisplayAnchor/Resources/en.lproj` and rename the copy with your language code, e.g. `fr.lproj` (`de.lproj`, `es.lproj`, …).
2. In the copied `Localizable.strings`, translate only the **right-hand** side of each line — keep the keys (left of `=`) unchanged:
   ```
   "common_settings" = "Réglages";
   ```
3. Keep the format specifiers (`%@`, `%d`, `%%`) intact; you may reorder them if the sentence needs it.
4. Rebuild — the new language appears automatically in the Language picker (listed in its own name).

The picker is populated from the bundled `.lproj` folders, so it grows on its own. Missing keys fall back to English. The `SectionLabel` fields render uppercase automatically, so write them in normal case.

## Cutting a release

```bash
# 1. bump CFBundleShortVersionString (and CFBundleVersion) in Info.plist, commit
./release.sh
```

`release.sh` refuses to run on a dirty tree or an existing tag, builds the app, zips it
with `ditto`, generates the **signed appcast**, pushes, and creates the GitHub Release
tagged `v<version>` with both the zip and `appcast.xml` attached — which is what existing
installs then see through the update feed.

> [!IMPORTANT]
> Bump **`CFBundleVersion`** too, not just `CFBundleShortVersionString`. Sparkle compares
> `CFBundleVersion`, so a release that leaves it untouched is invisible to existing
> installs no matter what the tag says.

Signing the appcast locally uses the EdDSA private key in your Keychain. Attaching an
unsigned or missing `appcast.xml` means existing installs never see the release, so both
paths fail loudly rather than publishing a release nobody can update to.

Alternatively, you can push a tag directly (e.g. `git tag v1.0.1 && git push origin v1.0.1`)
and the GitHub Actions workflow will automatically build the universal binary, sign the
appcast and publish the release. The workflow reads the private key from the
`SPARKLE_PRIVATE_KEY` repository secret.

Running `release.sh` twice for the same version can emit a wrong `sparkle:version` from a
stale cache; clear it with `rm -rf ~/Library/Caches/Sparkle_generate_appcast` first. CI
runners start clean, so this only affects local runs.

## Update signing keys

Publishing needs an EdDSA (ed25519) key pair, generated once:

```bash
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

The private key lands in your login Keychain and the tool prints the public half — put
that in `Info.plist` under `SUPublicEDKey`. `release.sh` signs the appcast straight from
the Keychain. For CI, export the key and store it as a repository secret:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
gh secret set SPARKLE_PRIVATE_KEY < sparkle-private-key.txt
rm sparkle-private-key.txt
```

> [!WARNING]
> **The key cannot be rotated.** Sparkle only accepts a new key when the transition is
> signed with a code-signing identity carrying a Team ID, which an ad-hoc signed app does
> not have. Generate it once, back it up, and keep it — losing it means existing installs
> can never be updated again.

## Finishing the update setup

The Sparkle integration is in place but not yet operable: `SUPublicEDKey` in `Info.plist`
is empty, so `SPUUpdater.start()` fails, the failure is logged, and the app runs exactly
as it did before — without in-app updates. What is left:

- [ ] Generate the EdDSA key pair on a machine you trust and put the public half in
      `SUPublicEDKey` (see [Update signing keys](#update-signing-keys)).
- [ ] Export the private key and store it as the `SPARKLE_PRIVATE_KEY` repository secret,
      so the workflow can sign the appcast.
- [ ] Bump both `CFBundleShortVersionString` and `CFBundleVersion`, then cut a release and
      confirm `appcast.xml` is attached to it.
- [ ] Verify the update end to end from an older build: feed read, EdDSA validation,
      install, relaunch. None of that path can be exercised before a signed release
      exists.
- [ ] Re-take `docs/screenshots/settings.png` — it still shows the version row inside
      Updates and the old **Download** button.

The first release carrying Sparkle only reaches people who install it by hand: installs
running an earlier version have no updater, so that one upgrade stays manual for everyone.

## License

[MIT](LICENSE) © 2026 Gabriarceus
