#!/bin/zsh
# Builds DyNotch (Release) and packs it into a drag-to-install disk image: build/DyNotch-<version>.dmg.
# The window layout and background come from scripts/make-dmg.swift.
# Usage: scripts/make-dmg.sh [--no-build]
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/DerivedData/Build/Products/Release/DyNotch.app
if [[ "${1:-}" != "--no-build" ]]; then
    mkdir -p build
    if ! xcodebuild -project DyNotch.xcodeproj -scheme DyNotch -configuration Release \
            -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build > build/xcodebuild.log; then
        grep -E "error:" build/xcodebuild.log || tail -20 build/xcodebuild.log
        echo "Build failed (full log: build/xcodebuild.log)"
        exit 1
    fi
fi
[[ -d "$APP" ]] || { echo "No app at $APP"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
VOLNAME=DyNotch
WORK=build/dmg
DMG=build/DyNotch-$VERSION.dmg
rm -rf "$WORK" && mkdir -p "$WORK"

# Lay out a read-write HFS+ image, then compress it. The background alias in .DS_Store points at
# file IDs on this volume, and `hdiutil convert` keeps them.
SIZE_MB=$(( $(du -sm "$APP" | cut -f1) + 20 ))
hdiutil create -quiet -size ${SIZE_MB}m -fs HFS+ -volname "$VOLNAME" "$WORK/rw.dmg"
MOUNT=$(diskutil image attach --nobrowse "$WORK/rw.dmg" | sed -n 's|^/dev/.*\(/Volumes/.*\)$|\1|p')
[[ -d "$MOUNT" ]] || { echo "Couldn't mount $WORK/rw.dmg"; exit 1; }
trap 'hdiutil detach -quiet -force "$MOUNT" 2>/dev/null || true' EXIT

ditto "$APP" "$MOUNT/DyNotch.app"
ln -s /Applications "$MOUNT/Applications"
swift scripts/make-dmg.swift "$MOUNT" DyNotch.app
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
xcrun SetFile -c icnC "$MOUNT/.VolumeIcon.icns"
xcrun SetFile -a C "$MOUNT"
rm -rf "$MOUNT/.fseventsd"

hdiutil detach -quiet "$MOUNT"
trap - EXIT
hdiutil convert -quiet "$WORK/rw.dmg" -format ULMO -o "$DMG" -ov
rm -rf "$WORK"
echo "Wrote $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
