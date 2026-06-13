#!/usr/bin/env bash
#
# Build a signed + notarized PulseVM.dmg that opens cleanly on ANY Mac.
#
# ONE-TIME SETUP (stores your notary credentials in the keychain):
#   xcrun notarytool store-credentials "pulsevm-notary" \
#       --apple-id "you@example.com" \
#       --team-id  "UKU2H2D5Z7" \
#       --password "abcd-efgh-ijkl-mnop"     # App-Specific Password from appleid.apple.com
#
# Then just run:  ./scripts/release-dmg.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."                              # apps/macos

# --no-notarize : skip Apple notarization for a quick internal send. The DMG is
# still Developer ID-signed, but recipients must right-click → Open the first time
# (or run: xattr -dr com.apple.quarantine /Applications/PulseVM.app).
NOTARIZE=1
[ "${1:-}" = "--no-notarize" ] && NOTARIZE=0

APP_NAME="PulseVM"
SCHEME="PulseWallet"
DEV_ID="Developer ID Application: Paul Grey (UKU2H2D5Z7)"
NOTARY_PROFILE="pulsevm-notary"
BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG="$BUILD_DIR/$APP_NAME.dmg"
STAGE="$BUILD_DIR/dmg-stage"

echo "▶︎ Regenerating project…"
xcodegen generate >/dev/null

echo "▶︎ Building the Rust core (universal)…"
if [ -x ../../scripts/build-core-macos.sh ]; then (cd ../.. && scripts/build-core-macos.sh)
else echo "  (skipping; using existing Vendor/libpulse_wallet_core.a)"; fi

# Monotonically increasing build number (git commit count) so every DMG is
# recognized as newer than the last — clean updates for recipients.
BUILD_NO=$(git rev-list --count HEAD 2>/dev/null || echo 1)
echo "▶︎ Archiving Release (build $BUILD_NO)…"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
# Contain DerivedData in build/ so the archive's intermediate PulseVM.app copy
# doesn't linger in ~/Library/.../DerivedData and hijack the pulsevm:// handler.
xcodebuild -project PulseWallet.xcodeproj -scheme "$SCHEME" -configuration Release \
    -archivePath "$ARCHIVE" -derivedDataPath "$BUILD_DIR/dd" archive \
    DEVELOPMENT_TEAM=UKU2H2D5Z7 \
    CURRENT_PROJECT_VERSION="$BUILD_NO" \
    -quiet

echo "▶︎ Exporting with Developer ID…"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>UKU2H2D5Z7</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" -quiet

APP="$EXPORT_DIR/$APP_NAME.app"
echo "▶︎ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▶︎ Building DMG…"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ "$NOTARIZE" = "1" ]; then
    echo "▶︎ Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "▶︎ Stapling the ticket…"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

# Clean up intermediate .app copies — otherwise the staged/exported/archived
# PulseVM.app copies linger on disk and register themselves as competing
# pulsevm:// handlers (LaunchServices may then launch the wrong build).
echo "▶︎ Cleaning up build copies (keeping the .dmg)…"
rm -rf "$STAGE" "$EXPORT_DIR" "$ARCHIVE" "$BUILD_DIR/dd"
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -kill -r -domain local -domain user >/dev/null 2>&1 || true

echo ""
echo "✅ Done →  $(cd "$(dirname "$DMG")" && pwd)/$(basename "$DMG")"
if [ "$NOTARIZE" = "1" ]; then
    echo "   Send that file. Recipients double-click it, drag PulseVM → Applications, done."
else
    echo "   ⚠︎  NOT notarized (--no-notarize). Recipients must right-click → Open the first"
    echo "      time, or run: xattr -dr com.apple.quarantine /Applications/PulseVM.app"
fi
