#!/bin/zsh
# Plays every Bluetooth connect animation in turn, each to its end with a pause after it: the
# AirPods models (the Max in each of its colors, both models), the Beats, then the devices without
# a 3D model. They turn as Apple's own models of them, as for a real connection: the first run
# downloads those into build/demo, later runs reuse them.
# Runs a Debug copy under its own bundle ID and home folder, so the installed DyNotch, its
# settings, permissions, Shelf and downloaded AirPods pictures stay out of it, and quits it at the
# end.
# Usage: scripts/demo-bluetooth.sh [--gap seconds] [bt command …]
#   scripts/demo-bluetooth.sh                    everything, 1.5 s apart
#   scripts/demo-bluetooth.sh --gap 3 "max 0x12" pro
set -euo pipefail
cd "$(dirname "$0")/.."

gap=1.5
if [[ ${1:-} == --gap ]]; then gap=$2; shift 2; fi

ID=app.dynotch.DyNotch.demo
WORK=$PWD/build/demo
APP=$WORK/DyNotch-Demo.app
ART="$WORK/home/Library/Application Support/DyNotch/DeviceArt"

# Name shown here | debug `bt` command (DebugCommands.swift) | product and color ID of Apple's
# model to download first. Space Gray to Pink only came as the first AirPods Max (0x200A),
# Midnight to Purple only as the USB-C one (0x201F).
all=(
    "AirPods|airpods|0x200F"
    "AirPods 3|3|0x2013"
    "AirPods 4|4|0x2019"
    "AirPods Pro|pro|0x2024"
    "AirPods Max · Space Gray|max 0x200A 0x0F|0x200A 0x0F"
    "AirPods Max · Silver|max 0x200A 0x10|0x200A 0x10"
    "AirPods Max · Green|max 0x200A 0x11|0x200A 0x11"
    "AirPods Max · Sky Blue|max 0x200A 0x03|0x200A 0x03"
    "AirPods Max · Pink|max 0x200A 0x02|0x200A 0x02"
    "AirPods Max (USB-C) · Midnight|max 0x12|0x201F 0x12"
    "AirPods Max (USB-C) · Starlight|max 0x13|0x201F 0x13"
    "AirPods Max (USB-C) · Blue|max 0x14|0x201F 0x14"
    "AirPods Max (USB-C) · Orange|max 0x15|0x201F 0x15"
    "AirPods Max (USB-C) · Purple|max 0x16|0x201F 0x16"
    "Beats Studio Pro|beats|0x2017"
    "Beats Fit Pro|fitpro|0x2012"
    "Magic Mouse|mouse|"
    "iPhone|iphone|"
    "iPad|ipad|"
    "Apple Watch|watch|"
)
if (( $# )); then
    all=()
    for command in "$@"; do all+=("$command|$command|"); done
fi

# By name: macOS may run it from a translocated path. Its mediaremote-adapter child goes too.
quit_demo() { pkill -f "DyNotch-Demo.app/Contents/" 2>/dev/null || true; }
cleanup() {
    quit_demo
    defaults delete $ID 2>/dev/null || true
    rm -f ~/Library/Preferences/$ID.plist
}
models_here() { find "$ART" -name 'turntable-*.heic' 2>/dev/null | wc -l | tr -d ' '; }

echo "Building (Debug)…"
if ! xcodebuild -project DyNotch.xcodeproj -scheme DyNotch -configuration Debug \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; then
    echo "Build failed"
    exit 1
fi

quit_demo
rm -rf "$APP"
mkdir -p "$WORK/home/Library/Application Support"
ditto build/DerivedData/Build/Products/Debug/DyNotch.app "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" "$APP/Contents/Info.plist"
codesign --force --deep --sign - --entitlements Config/DyNotch.entitlements "$APP" 2>/dev/null
# Files made in a quarantined folder (an unpacked download) are quarantined too, and macOS would
# then run the app from a translocated copy.
xattr -dr com.apple.quarantine "$APP"
swiftc -O scripts/notch.swift -o "$WORK/notch"

trap cleanup EXIT
trap 'exit 130' INT TERM

# Nothing that asks for a permission or shows up beside the notch on its own.
defaults delete $ID 2>/dev/null || true
for key in hasCompletedOnboarding liveAirPodsAnimation liveBluetoothContinuity; do
    defaults write $ID $key -bool true
done
for key in liveBluetooth liveBattery liveMeetings liveFocus liveCapsLock liveSongChange \
    hudVolume hudBrightness hudKeyboard showMenuBarIcon showCompactMedia barsFollowMusic \
    hapticsEnabled weatherUseLocation; do
    defaults write $ID $key -bool false
done

open -n -g --env CFFIXED_USER_HOME="$WORK/home" "$APP"
for _ in {1..50}; do pgrep -f "DyNotch-Demo.app/Contents/MacOS/" >/dev/null && break; sleep 0.1; done
sleep 2

# Every model here before the first one shows: `bt` waits up to 5 s for one that isn't, which
# would cut the one before it short. Fetches go one at a time; give up on one stuck for a minute.
wanted=0
for entry in "${all[@]}"; do
    ids=${entry##*|}
    [[ -n $ids ]] || continue
    "$WORK/notch" art "$ids"
    (( wanted += 1 ))
done
if (( wanted > $(models_here) )); then
    last=$(models_here) since=$SECONDS
    while (( $(models_here) < wanted && SECONDS - since < 60 )); do
        printf "\rDownloading Apple's models… %d/%d" $(models_here) $wanted
        (( $(models_here) > last )) && last=$(models_here) since=$SECONDS
        sleep 1
    done
    printf "\rDownloading Apple's models… %d/%d\n" $(models_here) $wanted
fi

for entry in "${all[@]}"; do
    name=${entry%%|*}
    command=${${entry#*|}%%|*}
    # How long DebugCommands keeps each one up.
    case ${command%% *} in
        mouse|iphone|ipad|watch) duration=3.5 ;;
        *) duration=5 ;;
    esac
    echo "▶ $name"
    "$WORK/notch" bt "$command"
    sleep $(( duration + gap ))
done
