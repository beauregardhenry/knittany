#!/bin/zsh
# Builds a universal Release of the app, signs it with your Developer ID,
# notarizes it with Apple and staples the ticket, so it opens on any Mac
# without the "can't be checked" warning.
#
# One-time setup, once the Apple Developer account exists:
#   1. In Xcode > Settings > Accounts, add the account and create a
#      "Developer ID Application" certificate.
#   2. Store notarization credentials in the keychain (an app-specific
#      password from appleid.apple.com):
#        xcrun notarytool store-credentials knitting-notary --apple-id YOU@EXAMPLE.COM --team-id TEAMID
#   3. Export your team ID before running this script:
#        export KNITTING_TEAM_ID=TEAMID
#
# Then:   scripts/release.sh
# Output: build/release/Knitting.zip, ready to install or share.

set -euo pipefail
cd "$(dirname "$0")/.."

: "${KNITTING_TEAM_ID:?Set KNITTING_TEAM_ID to your Apple Developer team ID}"
PROFILE="${KNITTING_NOTARY_PROFILE:-knitting-notary}"
OUT=build/release
rm -rf -f "$OUT"
mkdir -p "$OUT"

echo "Building…"
(cd App && xcodegen generate -q)
xcodebuild -project App/Knitting.xcodeproj -scheme Knitting -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$KNITTING_TEAM_ID" OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build | tail -1

APP=build/DerivedData/Build/Products/Release/Knitting.app
ditto "$APP" "$OUT/Knitting.app"
codesign --verify --deep --strict --verbose=1 "$OUT/Knitting.app"
echo "Architectures: $(lipo -archs "$OUT/Knitting.app/Contents/MacOS/Knitting")"

echo "Notarizing (this takes a few minutes)…"
ditto -c -k --keepParent "$OUT/Knitting.app" "$OUT/upload.zip"
xcrun notarytool submit "$OUT/upload.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$OUT/Knitting.app"
spctl --assess --type execute --verbose "$OUT/Knitting.app"

rm -f "$OUT/upload.zip"
ditto -c -k --keepParent "$OUT/Knitting.app" "$OUT/Knitting.zip"
echo "Done: $OUT/Knitting.zip"
