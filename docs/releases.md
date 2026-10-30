# Releases and updates

This guide explains distribution and update concepts. [build.sh](../build.sh),
[release.sh](../release.sh), and the [release workflow](../.github/workflows/build-and-release.yml)
define the executable steps. Publishing, pushing, tagging, and credential operations
require explicit authorization; this guide is not that authorization.

## App signing and update trust

DisplayAnchor is ad-hoc signed, without an Apple Developer ID or notarization.
Downloaded bundles require first-launch approval through macOS Privacy & Security.
Locally built bundles normally have no download quarantine. See the
[User guide](user-guide.md#opening-a-downloaded-app) for installation.

Sparkle validates update archives using EdDSA signatures and a public key embedded in
the app. This is separate from the app's ad-hoc code signature. Keep Sparkle's nested
helpers and signatures intact during packaging, sign the outer bundle last, and
verify the complete bundle. A damaged framework signature can prevent future updates.
The build script uses bundle-preserving copies and verifies the result.

The primary feed is appcast.xml on the dedicated updates branch, served through raw.githubusercontent.com. It retains the newest stable item and the newest RC item. Stable items use Sparkle’s default channel; RC items use its rc channel. The app allows only the default channel unless the user opts into Stable and RC. Archive signatures remain unchanged when the signed items are merged into this feed.

Each GitHub release still carries its own appcast.xml beside the versioned archive. These per-release feeds remain usable for migrating older updater-enabled builds; channel labels are applied to the shared feed. New clients read the shared feed without querying the GitHub Releases API.

## In-app update behavior

UpdateController.swift bridges Sparkle to app-owned state. Scheduled checks are silent:
the menu bar indicator, settings indicator, and a notification announce an update.
Notifications are deduplicated by version. A failed check preserves a known pending
update rather than removing its reminder.

CompactUpdateUserDriver supplies a compact Install/Cancel confirmation and keeps scheduled update offers silent. Sparkle’s standard user driver handles download progress, extraction, errors, installation, and relaunch. Release notes are linked from Settings instead of embedded in the confirmation. Informational and major-upgrade notices keep Sparkle’s standard presentation when the user opens them.

Automatic updates are disabled through SUAllowsAutomaticUpdates. The automatic-check toggle controls discovery only; download and installation start after the user chooses Install. This also prevents an automatic-install preference left by the older standard alert from bypassing the compact confirmation.

The app supports disabling automatic checks while retaining manual checks. Channel changes clear old offers and queue a fresh check; responses from the previous selection cannot restore an RC offer after switching to Stable. The change never requests a downgrade. Unbundled runs have no updater, and startup errors are logged without blocking display management.

Sparkle removes download quarantine from the bundle it installs, so in-app updates
avoid repeating the downloaded app's first-launch approval. Apps from before the
Sparkle integration still need one manual upgrade to an updater-enabled release.

## Versioning and publication paths

Info.plist owns the displayed version and build version. Sparkle compares the build
version, CFBundleVersion. Changing only CFBundleShortVersionString or the Git tag does
not make an update visible. Increase both for a release, and keep the build version
greater than the previous published build.

Record pending changes under Unreleased in [CHANGELOG.md](../CHANGELOG.md). Use a release
candidate version for changes awaiting validation; promotion to stable is a separate
maintainer decision.

The local release script requires a clean working tree and a new version tag. It
checks the build version against the latest local tag, builds the app, creates a
bundle-preserving archive, and generates the signed appcast using the local Keychain.
It then pushes the current commit, creates a GitHub release with the archive and per-release feed, and publishes the merged channel feed to the updates branch. Running it is a publication action, not a build-only check.

The GitHub workflow is the alternative publication path. A version tag triggers it;
manual dispatch can build an artifact without publishing or explicitly request a
release. It derives the release version from Info.plist, builds the Universal Binary,
packages it, and signs the appcast when publishing. It uses the repository signing
secret configured by the maintainer. Keep tags, bundle versions, feed version, and
asset URLs consistent. The workflow does not repeat the local script's clean-tree
and previous-build checks.

Both publication paths mark versions with a prerelease suffix as GitHub prereleases and create new tags at the built commit. After release assets are available, [merge_appcast.py](../scripts/merge_appcast.py) classifies RC versions, retains the newest item for each channel, and rejects conflicting archives that reuse a build number. [publish_appcast.sh](../scripts/publish_appcast.sh) commits the merged feed in a temporary worktree and pushes only the updates branch. It creates that branch on first publication. Workflow runs are serialized; feed pushes never force-overwrite a concurrent publication. The temporary worktree is removed without changing the development branch.

### Candidate feed testing

New clients use the shared feed and the channel picker for candidate testing. Stable must ignore RC items; Stable and RC must include both channels. Check pending indicators, confirmation, download, install, relaunch, and an up-to-date result after installation. Also check channel changes during a running check, silent scheduled checks, and the automatic-check toggle.

Versions rc1 and rc2 use the former latest-release feed, which returns HTTP 404 while the latest stable release has no appcast. To migrate one of those clients, quit it, temporarily override SUFeedURL with the version-specific newer release appcast, and reopen it. The first channel-aware build clears old overrides under this repository’s releases URL at startup, then uses the shared feed and Stable default. Other custom test-feed URLs remain unchanged.

A shared feed containing only RC items is valid: Stable users receive no update offer until a stable item is published. The updates branch must exist before the new feed can be checked. Source integration and a successful build do not establish that the live channel feed or installation UI has been verified.

Local appcast generation caches archive metadata. Repeating generation for the same
version can reuse stale metadata and produce the wrong feed version. If that happens,
clear Sparkle's generate-appcast cache in the user's Library/Caches before generating
again. Fresh CI runners avoid that local-cache issue.

## Signing setup and release validation

The updater integration and maintainer-supplied public key are in place. [Version 1.1.0-rc1](https://github.com/gabriarceus/DisplayAnchor/releases/tag/v1.1.0-rc1), build 3, was published as a prerelease on 2026-10-30 from commit cafc162. The maintainer reports a private-key export outside the repository and the GitHub Actions signing secret configured. Both the local archive and the downloaded CI archive have valid Ed25519 signatures matching the embedded public key. The published appcast's versions, archive URL, and size match the CI archive; its Universal Binary and complete bundle signature also pass verification. [The release workflow](https://github.com/gabriarceus/DisplayAnchor/actions/runs/41035698227) completed successfully, and v1.0.1 remains the latest stable release. The maintainer confirmed the manual installed rc1-to-rc2 update on 2026-10-30. A separate encrypted backup, silent scheduled-check and automatic-check-toggle validation, and stable-feed rollout remain pending.

### Remaining rollout checkpoints

The original AutoUpdateScriptverse plan covers two apps and uses their former names and paths. DisplayAnchor already has the dependency, controller, settings, framework packaging, release script, and CI appcast generation. Continue from that implementation and the decisions in this guide: retain ad-hoc signing and use the shared channel feed introduced in rc3. The other app has its own rollout.

1. Configure update trust. The maintainer supplied the public key for SUPublicEDKey on 2026-10-30 and reports the local export and CI secret configured. Local and published CI archive signatures have been verified against that key. Keep a separate encrypted backup of the private key; a copy on the same disk as the Keychain does not protect against disk loss.
2. Prepare the first updater-enabled release candidate. Version 1.1.0-rc1, build 3, is published and verified as described above. Older releases without Sparkle need a manual upgrade to this baseline. Future publication still requires explicit authorization.
3. Verify an actual update between two updater-enabled builds. From the older installed bundle, confirm manual checking, silent scheduled checks, the automatic-check toggle, pending indicators, download, signature validation, installation, and relaunch into the newer version. A successful build alone does not complete this checkpoint.

The maintainer installed 1.1.0-rc1 and confirmed that the instructed update to rc2 worked on 2026-10-30. [Version 1.1.0-rc2](https://github.com/gabriarceus/DisplayAnchor/releases/tag/v1.1.0-rc2), build 4, was published from commit f518d7b and fixes the no-update result being overwritten by Sparkle's completion callback. All 40 local tests and the local bundle build passed. [The rc2 release workflow](https://github.com/gabriarceus/DisplayAnchor/actions/runs/41037046872) succeeded; the downloaded archive's Ed25519 signature, embedded public key, appcast metadata, Universal Binary, and complete bundle signature were verified. Version v1.0.1 remains the latest stable release. An rc1 check against its own candidate feed can still show failure because rc1 has that bug; the newer rc2 feed was used for the successful update test. Silent scheduled checks and the automatic-check toggle have not yet been manually verified.

Before the first updater-enabled release, the maintainer must configure a signing
key pair, embed the public key through SUPublicEDKey, and provide the matching private
key to the local Keychain and CI signing setup. Use Sparkle's supplied key tools for
the maintainer's authorized setup. Never put a private key in the repository, logs,
or documentation, and never inspect or presence-check signing credentials as part
of ordinary project work.

Key continuity matters: Sparkle's key-transition path requires a code-signing identity
with a Team ID, which an ad-hoc signed app lacks. Treat the established signing key
as permanent and keep a secure backup. Losing it prevents updates to existing installs.

Before considering the update path verified, confirm that a release has a signed
appcast and the correct archive URL, and test from an older installed build through
signature validation, installation, and relaunch. Also confirm silent scheduled
checks and the automatic-check toggle. Source integration alone does not establish
that signing setup or end-to-end updates work.

Version 1.1.0-rc3, build 5, prepares the compact confirmation and shared stable/RC feed. Its publication, first updates-branch creation, migration from rc2, and manual channel/UI checks remain pending.
