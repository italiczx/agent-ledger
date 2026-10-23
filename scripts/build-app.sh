#!/bin/bash
# Build a menu-bar .app with no Dock icon. Ad-hoc signed so macOS will launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/AgentLedger.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp ".build/release/AgentLedger" "$APP/Contents/MacOS/AgentLedger"
cp "scripts/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/AgentLedger"

framework=$(find .build -type d -name 'Sparkle.framework' -print -quit)
if [[ -z "$framework" ]]; then
  echo "Sparkle.framework was not produced by swift build." >&2
  exit 1
fi
ditto "$framework" "$APP/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP/Contents/MacOS/AgentLedger" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/AgentLedger"
fi

ICON_SRC="Resources/AppIcon-1024.png"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

if [[ -n "${VERSION:-}" ]]; then
  version="${VERSION#v}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${version}" "$APP/Contents/Info.plist"
fi

# Sign Sparkle's helpers before the framework, then the app that embeds it.
sparkle="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
while IFS= read -r item; do
  codesign --force --sign - "$item"
done < <(find "$sparkle" -depth \( -name '*.xpc' -o -name '*.app' -o -name 'Autoupdate' \) -print)
codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
codesign --verify --strict --deep "$APP"

echo "Built $APP"
echo "Open it with: open $APP"
