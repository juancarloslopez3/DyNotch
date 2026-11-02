#!/bin/zsh
# Xcode "Install to /Applications" build phase: signs the fresh build with a stable identity,
# replaces /Applications/DyNotch.app and (via the scheme) Run launches that copy, so macOS keeps
# the privacy grants between builds.
#
# Identity, in order: $DYNOTCH_SIGN_IDENTITY, "DyNotch Local Signing" (scripts/setup-signing.sh),
# any "Apple Development" identity. Without one the build stays ad-hoc and grants are reset.
set -uo pipefail

[[ "${ACTION:-build}" == "build" ]] || exit 0
APP="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
[[ -d "$APP" ]] || exit 0
DEST=/Applications/DyNotch.app

IDENTITY="${DYNOTCH_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITIES=$(security find-identity -p codesigning)
    for name in "DyNotch Local Signing" "Apple Development"; do
        [[ "$IDENTITIES" == *"\"$name"* ]] && { IDENTITY=$name; break; }
    done
fi

cdhash() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
OLD=$([[ -d "$DEST" ]] && cdhash "$DEST" || true)

STAGE=$(mktemp -d)
# Entitlements come from the project file, never from the build product: Xcode signs it after
# this phase, so on a clean build it is not signed yet. Debug needs get-task-allow to attach.
cp "${SRCROOT}/Config/DyNotch.entitlements" "$STAGE/ent.plist"
[[ "${CONFIGURATION:-Debug}" == "Release" ]] ||
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" "$STAGE/ent.plist"
# A self-signed identity has no Team ID, so library validation would reject our own dylibs/frameworks.
/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$STAGE/ent.plist" 2>/dev/null
ditto "$APP" "$STAGE/DyNotch.app"
# A quarantine mark (inherited from an unzipped project) makes Gatekeeper translocate the app and refuse to launch it.
xattr -dr com.apple.quarantine "$STAGE/DyNotch.app" 2>/dev/null
if [[ -n "$IDENTITY" ]]; then
    # Inner code first, then the app with its entitlements and hardened runtime.
    # (Debug builds also keep DyNotch.debug.dylib and __preview.dylib next to the executable.)
    find "$STAGE/DyNotch.app/Contents/Frameworks" "$STAGE/DyNotch.app/Contents/MacOS" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) 2>/dev/null |
        while read -r f; do codesign --force --sign "$IDENTITY" --options runtime "$f"; done
    codesign --force --sign "$IDENTITY" --options runtime \
        --entitlements "$STAGE/ent.plist" "$STAGE/DyNotch.app" ||
        { echo "warning: signing with '$IDENTITY' failed"; IDENTITY=; }
fi

pkill -x DyNotch 2>/dev/null && sleep 0.5
rm -rf "$DEST"
ditto "$STAGE/DyNotch.app" "$DEST"
rm -rf "$STAGE"
echo "Installed $DEST (${IDENTITY:-ad-hoc})"

if [[ -z "$IDENTITY" && "$OLD" != "$(cdhash "$DEST")" ]]; then
    for s in Accessibility SystemPolicyAllFiles AudioCapture; do
        tccutil reset $s app.dynotch.DyNotch >/dev/null 2>&1
    done
    echo "warning: ad-hoc build, privacy grants reset. Run scripts/setup-signing.sh once to keep them."
fi
exit 0
