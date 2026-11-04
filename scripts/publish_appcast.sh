#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
CURRENT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
WORK="$(mktemp -d)"
rmdir "$WORK"
TEMP_BRANCH="appcast-publish-$$"
CREATED_BRANCH=false

cleanup() {
	git -C "$ROOT" worktree remove --force "$WORK" >/dev/null 2>&1 || true
	if [[ "$CREATED_BRANCH" == true ]]; then
		git -C "$ROOT" branch -D "$TEMP_BRANCH" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

REMOTE_REF="$(git -C "$ROOT" ls-remote --heads origin refs/heads/updates)"
if [[ -n "$REMOTE_REF" ]]; then
	git -C "$ROOT" fetch --no-tags origin refs/heads/updates
	git -C "$ROOT" worktree add --detach "$WORK" FETCH_HEAD
else
	git -C "$ROOT" worktree add --detach "$WORK" HEAD
	git -C "$WORK" switch --orphan "$TEMP_BRANCH"
	CREATED_BRANCH=true
fi

python3 "$SCRIPT_DIR/merge_appcast.py" "$CURRENT" "$WORK/appcast.xml" "$WORK/appcast.xml"
git -C "$WORK" add appcast.xml
if git -C "$WORK" diff --cached --quiet; then
	exit 0
fi
git -C "$WORK" commit -m "Update Sparkle appcast"
git -C "$WORK" push origin HEAD:refs/heads/updates
