# Releases and updates

This guide explains distribution and update concepts. [build.sh](../build.sh), [release.sh](../release.sh), and the [release workflow](../.github/workflows/build-and-release.yml) define the executable steps. Publishing, pushing, tagging, and credential operations require explicit authorization; this guide is not that authorization.

## App signing and update trust

DisplayAnchor is ad-hoc signed, without an Apple Developer ID or notarization. macOS can require first-launch approval for downloaded bundles. Locally built bundles normally have no download quarantine. See the [User guide](user-guide.md#opening-a-downloaded-app) for installation.

Sparkle validates update archives using EdDSA signatures and the public key embedded in Info.plist. This is separate from the app's ad-hoc code signature. Preserve Sparkle's nested helpers and signatures during packaging, sign the outer bundle last, and verify the complete bundle. The build script uses bundle-preserving copies and verifies the result.

The maintainer manages the matching private key in the local Keychain and the GitHub Actions signing secret. Keep private material outside the repository and retain a separate encrypted backup. Never inspect or presence-check signing credentials during ordinary project work.

An ad-hoc signed app has no Team ID for Sparkle's key-transition path. Treat the established signing key as permanent: losing it prevents future updates to existing installs. A copy on the same disk as the Keychain does not protect against disk loss.

## Update feeds and channels

The primary feed is appcast.xml on the dedicated updates branch, served through raw.githubusercontent.com. It retains the newest stable item and the newest RC item. Stable items use Sparkle's default channel; RC items use its rc channel. Stable is the app's default selection. Stable and RC includes both channels. New clients read this feed without querying the GitHub Releases API.

Each GitHub release also carries its own appcast.xml beside the versioned archive. These per-release feeds remain usable for migrating older updater-enabled builds. Channel labels are applied when the items enter the shared feed. Archive signatures remain unchanged during the merge.

The updates branch must exist before clients can check the shared feed. A feed containing only RC items is valid: Stable users receive no offer until a stable item is published.

## In-app update behavior

UpdateController.swift bridges Sparkle to app-owned state. Scheduled checks are silent. The menu bar indicator, settings indicator, and a notification announce an update; notifications are deduplicated by version. A failed check preserves a known pending update. Channel changes clear old offers and queue a fresh check after any active session finishes. Switching to Stable does not request a downgrade.

CompactUpdateUserDriver supplies an Install/Cancel confirmation with embedded plain-text release notes in a selectable, scrollable area of bounded height. Missing or empty notes add no space. Sparkle's standard user driver handles download progress, extraction, errors, installation, and relaunch. Informational and major-upgrade notices keep Sparkle's standard presentation when the user opens them. The Settings link opens the full release history.

Both release paths use [release_notes.py](../scripts/release_notes.py) to extract the matching version section from CHANGELOG.md, or Unreleased when the version has no section yet. It converts the project's Markdown headings, links, emphasis, and bullets to plain text. Sparkle embeds the companion text file in the per-release appcast; the shared-feed merge preserves it. Empty or missing notes stop release preparation. Notes follow the changelog's English language; labels follow the app's selected language. No separate notes download is needed.

SUAllowsAutomaticUpdates is false, which disables automatic downloads and installations. The automatic-check toggle controls discovery only; manual checks remain available. Download and installation begin after the user chooses Install. Unbundled runs have no updater, and startup errors are logged without blocking display management.

Sparkle removes download quarantine from the app it installs. Apps from before the Sparkle integration need one manual upgrade to an updater-enabled release.

## Versioning and publication

Info.plist owns the displayed version and build version. Sparkle compares CFBundleVersion. Changing only the display version or Git tag does not make an update visible. Increase both for a release and keep the build number greater than every published build, including RCs.

Keep pending work under Unreleased in [CHANGELOG.md](../CHANGELOG.md). When preparing an approved stable release, move its notes into the matching version section and remove an empty Unreleased heading. Keep category headings and entries in alphabetical order. Work awaiting promotion uses an RC version; preparing a stable version does not itself publish a release.

The local release script requires a clean working tree and a version tag that does not yet exist. It compares the build number with the latest local tag, builds the app, creates a bundle-preserving archive, and generates the signed per-release appcast through the Keychain. It then pushes the current commit, creates the GitHub release, and publishes the merged channel feed. Running it is a publication action.

The GitHub workflow is the alternative publication path. A version tag triggers publication. Manual dispatch can build an artifact without publishing or explicitly request a release. It tests the feed tools, builds the Universal app, and generates the signed appcast when publishing. It does not run the Swift test suite or repeat the local script's clean-tree and previous-build checks.

Both publication paths mark versions with prerelease suffixes as GitHub prereleases and target the built commit when creating a new tag. Keep tag names, bundle versions, and asset URLs consistent. For the first stable release, merge the reviewed PR before creating its version tag on main. Merging the PR alone does not trigger publication.

Once release assets are available, [merge_appcast.py](../scripts/merge_appcast.py) retains the newest signed archive item for each channel and rejects conflicting archives that reuse a build number. [publish_appcast.sh](../scripts/publish_appcast.sh) commits the feed in a temporary worktree and pushes only the updates branch. It creates that branch on first publication and removes its temporary worktree afterward. Workflow runs are serialized; feed pushes never force-overwrite concurrent changes. If release creation succeeds but feed publication fails, installed clients keep seeing the previous feed until publication is completed.

Sparkle's appcast generator caches archive metadata. Regenerating the same version can reuse stale metadata. If the generated feed has an incorrect version, clear Sparkle's generate-appcast cache in Library/Caches before generating it again. Fresh CI runners avoid this local-cache issue.

## Validation and rollout status

Version 1.1.0, build 6, is prepared for the first stable release with the shared feed and release notes. As of 2026-11-04, all 50 Swift tests, 10 release-tool tests, and the Universal bundle build pass. The independent branch review found a channel-switch race; the fix has regression coverage and passed a follow-up review.

Candidate releases rc1 through rc3 were published through CI. Their downloaded archives and appcast metadata passed signature and packaging checks, and rc3 created the shared channel feed. The maintainer confirmed the installed rc1-to-rc2 update and later reported installing rc3. These checks establish the signed update path; they do not establish manual validation of every feature added afterward.

Before considering the stable rollout fully verified, confirm the following against the final build and published feed:

- Stable ignores RC items; Stable and RC includes both channels. Changing channels during a check does not leave a stale offer or a stuck status.
- Scheduled checks remain silent, the automatic-check toggle controls scheduling, and manual checks work with scheduling disabled.
- The final confirmation displays the release changelog correctly. Download, signature validation, installation, and relaunch succeed from an older installed updater-enabled build.
- The stable appcast advertises the intended version, build number, archive URL, and signature. Initial publication of the stable item remains separate from source validation.

Older rc1 and rc2 clients use the former latest-release feed. If it has no appcast, their checks fail. A temporary SUFeedURL preference can point them at a newer release's per-release appcast for migration. The channel-aware app clears old overrides under this repository's releases URL at startup and returns to the shared feed with Stable as the default. Other custom test feeds remain unchanged.
