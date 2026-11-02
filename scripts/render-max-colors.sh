#!/bin/zsh
# Renders the AirPods Max turning, in each of its colors, into DyNotch/Resources from the 3D model
# in airpods-max/ (scripts/render-turntable.swift). The colors were measured off the pictures
# macOS shows of each Max (CoreBluetoothUI's B515*.icns) and corrected for this lighting: cups,
# cushions, then the canopy and the headband over it.
# Usage: scripts/render-max-colors.sh [model folder]
set -e
cd "$(dirname "$0")/.."
model=${1:-airpods-max}
textures="$model/textures"

while read -r name cups cushions top; do
    swift scripts/render-turntable.swift "$model/source/Airpods MAX.fbx" "DyNotch/Resources/AirPodsMax-$name.turntable.heic" \
        --base "$textures/Airpod Max Base Color.png" --normal "$textures/Airpod Max Normal MAp.png" \
        --roughness "$textures/Airpod Max Roughness.png" --metallic "$textures/Airpod_Max_Metallic.png" \
        --opacity "$textures/Airpod Max Opacity.png" \
        --split 0.54 --cups "$cups" --cushions "$cushions" --top "$top"
done <<'COLORS'
SpaceGray #444446 #0D0D0D #323231
Silver #ABADAE #707171 #E2E0DD
Green #8C9588 #565F51 #E9F0E3
SkyBlue #76828C #3A4956 #2C4C63
Pink #B38D83 #844D46 #C2403D
Midnight #3F4147 #0D0D0D #3A4046
Starlight #B0A295 #726457 #F7EADD
Blue #7A8E92 #3B5258 #677D8C
Orange #CE9784 #8A5239 #FFC8A7
Purple #988F9F #60596C #FBF2FE
COLORS
