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

The feed is appcast.xml attached to the latest GitHub release. It points to the
versioned archive and carries the update signature. Both assets are needed for the
release to reach installed apps through Sparkle.

## In-app update behavior

UpdateController.swift bridges Sparkle to app-owned state. Scheduled checks are silent:
the menu bar indicator, settings indicator, and a notification announce an update.
Notifications are deduplicated by version. A failed check preserves a known pending
update rather than removing its reminder.

The standard Sparkle release-notes, download, install, and relaunch flow starts when
the user chooses Install. The app supports disabling automatic checks while retaining
manual checks. It runs without an updater outside a built app bundle, and logs startup
configuration errors without raising a modal alert or blocking display management.

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
It then pushes the current commit and creates a GitHub release with the archive and
feed. Running it is a publication action, not a build-only check.

The GitHub workflow is the alternative publication path. A version tag triggers it;
manual dispatch can build an artifact without publishing or explicitly request a
release. It derives the release version from Info.plist, builds the Universal Binary,
packages it, and signs the appcast when publishing. It uses the repository signing
secret configured by the maintainer. Keep tags, bundle versions, feed version, and
asset URLs consistent. The workflow does not repeat the local script's clean-tree
and previous-build checks.

Both publication paths mark versions with a prerelease suffix as GitHub prereleases and create new tags at the built commit. The production feed uses GitHub's latest stable release, so it does not expose prereleases. Test a candidate with a separate test feed before promoting a version to stable; publishing a candidate alone does not verify the production update path.

### Candidate feed testing

Before the first updater-enabled stable release, the production feed returns HTTP 404 because the previous stable release has no appcast. This makes Check for Updates report failure even when candidate signing is correct. The version-specific appcast attached to a candidate release is the test feed.

For a manual candidate test, quit the installed app, override only SUFeedURL in its preferences with the version-specific candidate appcast URL, and reopen it. Sparkle supports this override for testing. Pointing an installed candidate at its own appcast should report that it is up to date. Pointing it at a newer candidate should expose the update for installation. The update must still verify against the public key embedded in the installed app.

Quit the app and remove the SUFeedURL preference after testing, then reopen it to return to the production feed. The test override takes priority over Info.plist and persists across updates until removed. It changes neither the embedded feed nor the update signature requirements.

Local appcast generation caches archive metadata. Repeating generation for the same
version can reuse stale metadata and produce the wrong feed version. If that happens,
clear Sparkle's generate-appcast cache in the user's Library/Caches before generating
again. Fresh CI runners avoid that local-cache issue.

## Signing setup and release validation

The updater integration and maintainer-supplied public key are in place. [Version 1.1.0-rc1](https://github.com/gabriarceus/DisplayAnchor/releases/tag/v1.1.0-rc1), build 3, was published as a prerelease on 2026-10-30 from commit cafc162. The maintainer reports a private-key export outside the repository and the GitHub Actions signing secret configured. Both the local archive and the downloaded CI archive have valid Ed25519 signatures matching the embedded public key. The published appcast's versions, archive URL, and size match the CI archive; its Universal Binary and complete bundle signature also pass verification. [The release workflow](https://github.com/gabriarceus/DisplayAnchor/actions/runs/41035698227) completed successfully, and v1.0.1 remains the latest stable release. The maintainer confirmed the manual installed rc1-to-rc2 update on 2026-10-30. A separate encrypted backup, silent scheduled-check and automatic-check-toggle validation, and stable-feed rollout remain pending.

### Remaining rollout checkpoints

The original AutoUpdateScriptverse plan covers two apps and uses their former names and paths. DisplayAnchor already has the dependency, controller, settings, framework packaging, release script, and CI appcast generation. Continue from that implementation and the decisions in this guide: retain ad-hoc signing and the release-asset feed. The other app has its own rollout.

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
