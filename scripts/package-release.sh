#!/bin/zsh
set -euo pipefail

# Builds the universal app and packages a release: a ZIP and a DMG (each with the app, first-open
# instructions and release notes), a software bill of materials, and SHA-256 checksums, in
# dist/releases.

PROJECT_ROOT="${0:A:h:h}"
DIST_ROOT="$PROJECT_ROOT/dist"
RELEASE_ROOT="$DIST_ROOT/releases"
APP_NAME="Knittany"
APP_PATH="$DIST_ROOT/$APP_NAME.app"

"$PROJECT_ROOT/scripts/build-app.sh" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
export KNITTANY_VERSION="$VERSION"
RELEASE_NAME="$APP_NAME-$VERSION-macOS-universal"
ZIP_PATH="$RELEASE_ROOT/$RELEASE_NAME.zip"
DMG_PATH="$RELEASE_ROOT/$RELEASE_NAME.dmg"
CHECKSUM_PATH="$RELEASE_ROOT/SHA256SUMS.txt"
SBOM_NAME="$APP_NAME-$VERSION.spdx.json"
SBOM_PATH="$RELEASE_ROOT/$SBOM_NAME"
RELEASE_NOTES_PATH="$PROJECT_ROOT/DistributionAssets/RELEASE NOTES - $APP_NAME $VERSION.md"

BUILT_ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
if [[ "$BUILT_ARCHS" != *arm64* || "$BUILT_ARCHS" != *x86_64* ]]; then
    print -u2 "$RELEASE_NAME requires a universal build, but only '$BUILT_ARCHS' was produced."
    exit 1
fi
if [[ ! -f "$RELEASE_NOTES_PATH" ]]; then
    print -u2 "Release notes are missing at '$RELEASE_NOTES_PATH'."
    exit 1
fi

mkdir -p "$PROJECT_ROOT/build"
STAGING_ROOT="$(mktemp -d "$PROJECT_ROOT/build/knittany-release.XXXXXX")"
PAYLOAD_ROOT="$STAGING_ROOT/$APP_NAME $VERSION"
cleanup() { rm -rf "$STAGING_ROOT"; }
trap cleanup EXIT

mkdir -p "$RELEASE_ROOT" "$PAYLOAD_ROOT"
ditto "$APP_PATH" "$PAYLOAD_ROOT/$APP_NAME.app"
cp "$PROJECT_ROOT/DistributionAssets/FIRST OPEN - Knittany.txt" "$PAYLOAD_ROOT/"
cp "$RELEASE_NOTES_PATH" "$PAYLOAD_ROOT/"
ln -s /Applications "$PAYLOAD_ROOT/Applications"

rm -f "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH" "$SBOM_PATH"

"$PROJECT_ROOT/scripts/generate-sbom.sh" "$PAYLOAD_ROOT/$SBOM_NAME" >/dev/null
cp "$PAYLOAD_ROOT/$SBOM_NAME" "$SBOM_PATH"

ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PAYLOAD_ROOT" "$ZIP_PATH"
hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$PAYLOAD_ROOT" -ov -format UDZO "$DMG_PATH"

cd "$RELEASE_ROOT"
shasum -a 256 "${ZIP_PATH:t}" "${DMG_PATH:t}" "${SBOM_PATH:t}" > "${CHECKSUM_PATH:t}"

print "$ZIP_PATH"
print "$DMG_PATH"
print "$CHECKSUM_PATH"
print "$SBOM_PATH"
