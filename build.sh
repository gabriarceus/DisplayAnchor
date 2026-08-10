#!/bin/bash
# Builds the release binary and assembles the DisplayAnchor.app bundle.
# The bundle (with a stable identifier and ad-hoc signature) is required for
# system notifications and launch-at-login to work.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/DisplayAnchor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DisplayAnchor "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

# SwiftPM resource bundles (localized .strings): Bundle.module resolves them
# from Contents/Resources; without this copy it falls back to the absolute
# .build path baked into the binary, reading the repo checkout at runtime.
mkdir -p "$APP/Contents/Resources"
cp -R .build/release/*.bundle "$APP/Contents/Resources/"

# App icon: derive AppIcon.icns from the 1024x1024 source PNG (when present)
# and place it in Resources/. macOS resolves it via CFBundleIconFile in Info.plist.
ICON_SRC="AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
	ICONSET="build/AppIcon.iconset"
	rm -rf "$ICONSET"
	mkdir -p "$ICONSET"
	sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
	sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
	sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
	sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
	sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
	sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
	sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
	sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
	sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
	sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
	mkdir -p "$APP/Contents/Resources"
	iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
	echo "Embedded app icon from $ICON_SRC"
else
	echo "WARNING: $ICON_SRC not found — building without an app icon."
fi

codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run it with: open \"$APP\""

# Optional install; skipped when stdin is not a terminal (CI, piped runs).
if [[ -t 0 ]]; then
	read -r -p "Install to /Applications, replacing any existing copy? [Y/n] " REPLY
	if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
		rm -rf "/Applications/$(basename "$APP")"
		cp -R "$APP" "/Applications/"
		echo "Installed /Applications/$(basename "$APP")"
	fi
fi
