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

[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean." >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
	echo "Tag $TAG already exists — bump CFBundleShortVersionString in Info.plist." >&2
	exit 1
fi

./build.sh </dev/null

ZIP="build/DisplayAnchor-$VERSION.zip"
rm -f "$ZIP"
# ditto (not zip) preserves the bundle's symlinks and resource forks.
ditto -c -k --keepParent "build/DisplayAnchor.app" "$ZIP"

# Push first: gh creates the tag at the remote HEAD, and the update check starts
# advertising this version the moment the release is published.
git push origin HEAD
gh release create "$TAG" "$ZIP" --title "$VERSION" --generate-notes

echo "Published $TAG"
