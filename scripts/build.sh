#!/bin/zsh
# Builds DyNotch (Release), installs it to /Applications (or ~/Applications) and relaunches it.
# Usage: scripts/build.sh [--no-launch]
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project DyNotch.xcodeproj -scheme DyNotch -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build | grep -E "error:|warning: .*DyNotch|BUILD (SUCCEEDED|FAILED)" || true

APP=build/DerivedData/Build/Products/Release/DyNotch.app
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }

DEST=/Applications
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"

cdhash() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
OLD_CDHASH=$([[ -d "$DEST/DyNotch.app" ]] && cdhash "$DEST/DyNotch.app" || true)

pkill -x DyNotch 2>/dev/null && sleep 0.5 || true
rm -rf "$DEST/DyNotch.app"
ditto "$APP" "$DEST/DyNotch.app"
echo "Installed to $DEST/DyNotch.app"

# An ad-hoc grant is pinned to the binary's cdhash: after a rebuild the Accessibility and
# Full Disk Access switches stay on in System Settings but no longer apply, so the HUD key
# tap and Focus status fail (and the music bars hear only silence). Clear the stale entries so
# DyNotch asks again instead of looking allowed.
SIGNATURE=$(codesign -dv "$DEST/DyNotch.app" 2>&1)
if [[ "$SIGNATURE" == *"Signature=adhoc"* && "$OLD_CDHASH" != "$(cdhash "$DEST/DyNotch.app")" ]]; then
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$DEST/DyNotch.app/Contents/Info.plist")
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset SystemPolicyAllFiles "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset AudioCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
    echo "Ad-hoc build: allow DyNotch again in System Settings › Privacy & Security › Accessibility"
    echo "and › Full Disk Access (or set up Config/Signing.local.xcconfig, see README › Signing)."
    echo "System Audio Recording (for the music bars) is asked for again the next time music plays."
fi

[[ "${1:-}" == "--no-launch" ]] || open "$DEST/DyNotch.app"
