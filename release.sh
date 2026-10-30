#!/bin/bash
# Builds DisplayAnchor.app, zips it and publishes it as a GitHub Release.
#
# The tag is derived from CFBundleShortVersionString in Info.plist — the same
# value the in-app update check compares against — so bump it (and CFBundleVersion,
# which Launch Services uses to notice the replaced bundle) before running this.
set -euo pipefail
cd "$(dirname "$0")"

command -v gh >/dev/null || { echo "gh (GitHub CLI) is required." >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
TAG="v$VERSION"
REPOSITORY="gabriarceus/DisplayAnchor"

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

./build.sh </dev/null

ZIP="build/DisplayAnchor-$VERSION.zip"
rm -f "$ZIP"
# ditto (not zip) preserves the bundle's symlinks and resource forks.
ditto -c -k --keepParent "build/DisplayAnchor.app" "$ZIP"

# The per-release appcast also supplies the signed item for the channel feed.
# Signing uses the local Keychain; archive signatures survive the feed merge.
GENERATE_APPCAST=$(find .build/artifacts -type f -name generate_appcast | head -1)
[[ -n "$GENERATE_APPCAST" ]] || { echo "generate_appcast not found — run 'swift package resolve'." >&2; exit 1; }
APPCAST_DIR="build/appcast"
rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp "$ZIP" "$APPCAST_DIR/"
"$GENERATE_APPCAST" \
	--download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
	--link "https://github.com/$REPOSITORY" \
	-o "$APPCAST_DIR/appcast.xml" \
	"$APPCAST_DIR"

# Publish the assets before the shared feed advertises their download URLs.
git push origin HEAD
RELEASE_FLAGS=(--target "$(git rev-parse HEAD)")
if [[ "$VERSION" == *-* ]]; then
	RELEASE_FLAGS+=(--prerelease --latest=false)
fi
gh release create "$TAG" "$ZIP" "$APPCAST_DIR/appcast.xml" --title "$VERSION" --generate-notes \
	"${RELEASE_FLAGS[@]}"
bash scripts/publish_appcast.sh "$APPCAST_DIR/appcast.xml"

echo "Published $TAG"
