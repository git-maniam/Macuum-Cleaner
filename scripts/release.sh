#!/bin/zsh
# Build, sign, notarize (app, then .dmg), staple both, and package Macuum Cleaner as a .dmg.
# Requires: Xcode, xcodegen, create-dmg (brew install create-dmg), a "Developer ID Application" certificate,
# and a notarytool keychain profile:  xcrun notarytool store-credentials macuum-notary
# Usage: scripts/release.sh 1.0.0 "Developer ID Application: Your Name (TEAMID)" [notary-profile]
set -euo pipefail

VERSION="${1:?version, e.g. 1.0.0}"
IDENTITY="${2:?signing identity}"
PROFILE="${3:-macuum-notary}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/release"
APP="$BUILD/export/Macuum Cleaner.app"
DMG="$ROOT/build/Macuum-Cleaner-v$VERSION.dmg"

rm -rf "$BUILD" "$DMG"; mkdir -p "$BUILD"
cd "$ROOT"
xcodegen generate

xcodebuild -project "Macuum Cleaner.xcodeproj" -scheme "Macuum Cleaner" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$BUILD/MacuumCleaner.xcarchive" \
  MARKETING_VERSION="$VERSION" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" archive

cat > "$BUILD/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$BUILD/MacuumCleaner.xcarchive" -exportPath "$BUILD/export" -exportOptionsPlist "$BUILD/export.plist"

lipo -info "$APP/Contents/MacOS/Macuum Cleaner"
codesign --verify --deep --strict --verbose=2 "$APP"

# Notarize and staple the app itself first, so the copy users drag out of the .dmg also works offline.
ditto -c -k --keepParent "$APP" "$BUILD/MacuumCleaner.zip"
xcrun notarytool submit "$BUILD/MacuumCleaner.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute -v "$APP"

create-dmg --volname "Macuum Cleaner" --app-drop-link 480 170 --icon "Macuum Cleaner.app" 160 170 \
  --window-size 640 360 "$DMG" "$APP"
codesign --sign "$IDENTITY" --timestamp "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "Done: $DMG"
