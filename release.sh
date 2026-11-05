#!/bin/bash
# Checks the release version and pushes its tag. The tag starts the release
# workflow, which builds, signs, and publishes the release and the update feed.
#
# The tag is derived from CFBundleShortVersionString in Info.plist — the same
# value the in-app update check compares against — so bump it (and CFBundleVersion,
# which Launch Services uses to notice the replaced bundle) before running this.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
TAG="v$VERSION"

[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean." >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
	echo "Tag $TAG already exists — bump CFBundleShortVersionString in Info.plist." >&2
	exit 1
fi

# Sparkle compares CFBundleVersion, not the marketing version, so a release that
# leaves it untouched is invisible to every existing install. Caught here rather
# than after publishing.
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [[ -n "$LAST_TAG" && "$BUILD" =~ ^[0-9]+$ ]]; then
	PREV_BUILD=$(git show "$LAST_TAG:Info.plist" 2>/dev/null | plutil -extract CFBundleVersion raw -o - -- - 2>/dev/null || echo 0)
	if [[ "$PREV_BUILD" =~ ^[0-9]+$ ]] && ((BUILD <= PREV_BUILD)); then
		echo "CFBundleVersion is $BUILD, but $LAST_TAG already published $PREV_BUILD — bump it in Info.plist." >&2
		exit 1
	fi
fi

swift test

git tag -a "$TAG" -m "$VERSION"
git push origin "$TAG"

echo "Pushed $TAG — the release workflow publishes it."
