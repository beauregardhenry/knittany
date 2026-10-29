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
#        xcrun notarytool store-credentials knittany-notary --apple-id YOU@EXAMPLE.COM --team-id TEAMID
#   3. Export your team ID before running this script:
#        export KNITTANY_TEAM_ID=TEAMID
#
# Then:   scripts/release.sh
# Output: build/release/Knittany.zip, ready to install or share.

set -euo pipefail
cd "$(dirname "$0")/.."

: "${KNITTANY_TEAM_ID:?Set KNITTANY_TEAM_ID to your Apple Developer team ID}"
PROFILE="${KNITTANY_NOTARY_PROFILE:-knittany-notary}"
OUT=build/release
rm -rf -f "$OUT"
mkdir -p "$OUT"

echo "Building…"
(cd App && xcodegen generate -q)
xcodebuild -project App/Knittany.xcodeproj -scheme Knittany -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$KNITTANY_TEAM_ID" OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build | tail -1

APP=build/DerivedData/Build/Products/Release/Knittany.app
ditto "$APP" "$OUT/Knittany.app"
codesign --verify --deep --strict --verbose=1 "$OUT/Knittany.app"
echo "Architectures: $(lipo -archs "$OUT/Knittany.app/Contents/MacOS/Knittany")"

echo "Notarizing (this takes a few minutes)…"
ditto -c -k --keepParent "$OUT/Knittany.app" "$OUT/upload.zip"
xcrun notarytool submit "$OUT/upload.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$OUT/Knittany.app"
spctl --assess --type execute --verbose "$OUT/Knittany.app"

rm -f "$OUT/upload.zip"
ditto -c -k --keepParent "$OUT/Knittany.app" "$OUT/Knittany.zip"
echo "Done: $OUT/Knittany.zip"
