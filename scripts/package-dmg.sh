#!/usr/bin/env bash
# Build a Release PulseVM.app and wrap it in a .dmg for distribution.
#
# Code signing + notarization need an Apple Developer ID and are intentionally
# left as a final step (they require credentials this script can't assume):
#
#   codesign --deep --force --options runtime \
#     --sign "Developer ID Application: <Your Name> (<TEAMID>)" build/PulseVM.app
#   xcrun notarytool submit build/PulseVM.dmg \
#     --apple-id <id> --team-id <TEAMID> --password <app-specific-pw> --wait
#   xcrun stapler staple build/PulseVM.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/apps/macos"
OUT="$ROOT/build"
ARCHIVE="$OUT/PulseWallet.xcarchive"

echo "▸ building the Rust core…"
"$ROOT/scripts/build-core-macos.sh"

echo "▸ generating project…"
( cd "$APP" && xcodegen generate )

echo "▸ archiving (Release)…"
mkdir -p "$OUT"
xcodebuild -project "$APP/PulseWallet.xcodeproj" -scheme PulseWallet \
  -configuration Release -archivePath "$ARCHIVE" \
  archive CODE_SIGNING_ALLOWED=NO | tail -3

APPPATH="$ARCHIVE/Products/Applications/PulseVM.app"
[ -d "$APPPATH" ] || { echo "build failed: $APPPATH not found"; exit 1; }

echo "▸ staging app + creating dmg…"
STAGE="$OUT/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APPPATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT/PulseVM.dmg"
hdiutil create -volname "PulseVM" -srcfolder "$STAGE" -ov -format UDZO "$OUT/PulseVM.dmg"

echo "▸ done → $OUT/PulseVM.dmg"
echo "  (unsigned — sign + notarize with your Developer ID before public release; see header)"
