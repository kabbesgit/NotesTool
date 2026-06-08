#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="NotesTool.app"
BIN_NAME="NotesTool"

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$BIN_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotesTool</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDisplayName</key><string>NotesTool</string>
  <key>CFBundleExecutable</key><string>NotesTool</string>
  <key>CFBundleIdentifier</key><string>com.kasper.notestool</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign with a stable identity so the Accessibility/TCC grant survives rebuilds.
# Ad-hoc signatures change every build, which silently revokes the grant.
SIGN_ID="${NOTESTOOL_SIGN_ID:-61E3166D881BEA67FABE413F907BD6B17ECFC914}"
if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
  codesign --force --sign "$SIGN_ID" "$APP"
  echo "Built $APP (signed with $SIGN_ID)"
else
  echo "WARN: signing identity $SIGN_ID not found — using ad-hoc; Accessibility grant will reset each build."
  codesign --force --sign - "$APP"
  echo "Built $APP (ad-hoc)"
fi
