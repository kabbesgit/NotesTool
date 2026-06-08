#!/usr/bin/env bash
# Rasterize Resources/AppIcon.svg into the macOS sizes and pack them into
# Resources/AppIcon.icns. Re-run after editing the SVG. Requires rsvg-convert
# (brew install librsvg) and iconutil (ships with macOS).
set -euo pipefail
cd "$(dirname "$0")/.."

SVG="Resources/AppIcon.svg"
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"

# name -> pixel size (Retina @2x variants included).
for spec in \
  "icon_16x16:16" "icon_16x16@2x:32" \
  "icon_32x32:32" "icon_32x32@2x:64" \
  "icon_128x128:128" "icon_128x128@2x:256" \
  "icon_256x256:256" "icon_256x256@2x:512" \
  "icon_512x512:512" "icon_512x512@2x:1024"; do
  name="${spec%%:*}"; px="${spec##*:}"
  rsvg-convert -w "$px" -h "$px" "$SVG" -o "$SET/$name.png"
done

iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
