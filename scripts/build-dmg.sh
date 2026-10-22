#!/bin/bash
# Build dist/AgentLedger.app, then pack a drag-to-Applications disk image.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

APP="dist/AgentLedger.app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
arch=$(uname -m)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

cp -R "$APP" "$stage/Agent Ledger.app"
ln -s /Applications "$stage/Applications"
codesign --verify --strict "$stage/Agent Ledger.app"

dmg="dist/AgentLedger-${version}-macOS-${arch}.dmg"
rm -f "$dmg" "${dmg}.sha256"
if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from --format UDZO --volumeName "Agent Ledger" "$stage" "$dmg"
else
  hdiutil create -volname "Agent Ledger" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
fi
shasum -a 256 "$dmg" > "${dmg}.sha256"

echo "Built $dmg"
cat "${dmg}.sha256"
