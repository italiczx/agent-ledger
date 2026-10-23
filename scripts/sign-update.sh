#!/bin/bash
# EdDSA-sign the update zip and write dist/appcast.xml.
# Skips quietly when SPARKLE_ED_PRIVATE_KEY is unset so a release can still ship.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  echo "SPARKLE_ED_PRIVATE_KEY is not set. The DMG will publish without an update feed."
  exit 0
fi

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "dist/AgentLedger.app/Contents/Info.plist")
arch=$(uname -m)
zip="dist/AgentLedger-${version}-macOS-${arch}.zip"
if [[ ! -f "$zip" ]]; then
  echo "Missing $zip. Run ./scripts/build-dmg.sh first." >&2
  exit 1
fi

tag="${GITHUB_REF_NAME:-v${version}}"
tools=$(mktemp -d)
trap 'rm -rf "$tools"' EXIT
curl -fsSL -o "$tools/Sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz"
tar -xf "$tools/Sparkle.tar.xz" -C "$tools"
printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" > "$tools/key"

archives=$(mktemp -d)
cp "$zip" "$archives/"
"$tools/bin/generate_appcast" \
  --ed-key-file "$tools/key" \
  --download-url-prefix "https://github.com/italiczx/agent-ledger/releases/download/${tag}/" \
  "$archives"
cp "$archives/appcast.xml" dist/appcast.xml
echo "Wrote dist/appcast.xml for ${tag}"
