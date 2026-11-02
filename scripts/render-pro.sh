#!/bin/zsh
# Renders the AirPods Pro turning into DyNotch/Resources from the 3D model in air-pods-pro/
# (scripts/render-turntable.swift): the two buds without their case, side by side and facing each
# other, stems straight down, ear tips turned a little towards the camera. The materials are the
# model's own (read off its Blender node trees), except the shell's baked light, which shades it
# as occlusion instead of glowing.
# Usage: scripts/render-pro.sh [model folder]
set -e
cd "$(dirname "$0")/.."
model=${1:-air-pods-pro}
t="$model/textures"

# Left bud, right bud.
buds=(BdivLmWINaLOdYj DKkbhpWklrEaECz)
# The pair is about twice as wide as tall and is shown as wide as the wing beside the notch
# (~38 pt), so the frames are a bit bigger than the Max's 72 px.
swift scripts/render-turntable.swift "$model/source/AirPods Pro.blend" DyNotch/Resources/AirPodsPro.turntable.heic \
    --keep "${(j:,:)buds}" --up z --size 84 \
    --turn "$buds[1] y-35 z-22" --turn "$buds[2] y35 z22" \
    --move "$buds[1] -0.2,0,0" --move "$buds[2] 0.2,0,0" \
    `# White shell` \
    --material "AWTzhuHRqcuHHac base=#FFFFFF roughness=$t/dJbFuXzciYblWxD@channels=G.png occlusion=$t/ELLgMzZSMHREGVY.png" \
    `# Mesh grilles` \
    --material "CmGiKFayWYAPgnF base=$t/XEIMocoZqXjdEUW.png metallic=$t/GeFUKRvnRuparmq-hJTHrWIHWIaXGkr@channels=B.png roughness=$t/GeFUKRvnRuparmq-hJTHrWIHWIaXGkr@channels=G.png emission=$t/FfJzuSAshEyFiOu.png normal=$t/hGhTHRkLXIVrzcd.png" \
    `# Black inner parts` \
    --material "XRQxhVGHKWInIiz base=#000000 roughness=1" \
    `# Steel at the end of the stems` \
    --material "feFCeOVEGRNYmFP base=#FFFFFF metallic=1 roughness=0.2" \
    --material "mhLOlkhyICoNjJz base=#FFFFFF metallic=1 roughness=0.1" \
    `# A small glossy black window (sensor)` \
    --material "lQGMGvxQZTxRjEE base=#1A1A1A metallic=0.3 roughness=0.1"
