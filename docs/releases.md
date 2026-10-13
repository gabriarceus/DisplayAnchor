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

Local appcast generation caches archive metadata. Repeating generation for the same
version can reuse stale metadata and produce the wrong feed version. If that happens,
clear Sparkle's generate-appcast cache in the user's Library/Caches before generating
again. Fresh CI runners avoid that local-cache issue.

## Signing setup and release validation

The updater integration is implemented, but its initial signing setup and end-to-end
rollout remain pending validation. Keep this status current after the maintainer
completes the setup and verifies the first signed release.

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
