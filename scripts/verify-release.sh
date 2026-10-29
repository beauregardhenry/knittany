#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_PATH="${1:-$PROJECT_ROOT/dist/Knittany.app}"
VERIFY_RELEASE_ASSETS="${2:-}"
PLIST_PATH="$APP_PATH/Contents/Info.plist"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/Knittany"
RESOURCES_PATH="$APP_PATH/Contents/Resources"

fail() {
    print -u2 "Release verification failed: $1"
    exit 1
}

[[ -d "$APP_PATH" ]] || fail "application bundle not found at $APP_PATH"
[[ -f "$PLIST_PATH" ]] || fail "Info.plist is missing"
[[ -x "$EXECUTABLE_PATH" ]] || fail "application executable is missing or not executable"
plutil -lint "$PLIST_PATH" >/dev/null

read_plist() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST_PATH"
}

[[ "$(read_plist CFBundleDisplayName)" == "Knittany" ]] || fail "display name is not Knittany"
[[ "$(read_plist CFBundleName)" == "Knittany" ]] || fail "bundle name is not Knittany"
[[ "$(read_plist CFBundleIdentifier)" == "com.beauregardhenry.knittany" ]] || fail "bundle identifier is incorrect"
[[ "$(read_plist LSMinimumSystemVersion)" == "15.0" ]] || fail "minimum macOS version is not 15.0"
[[ "$(read_plist CFBundleDocumentTypes:0:LSItemContentTypes:0)" == "com.adobe.pdf" ]] || fail "opening pattern PDFs is not declared"
[[ "$(read_plist CFBundleIconName)" == "AppIcon" ]] || fail "the app icon is not set"
[[ -f "$RESOURCES_PATH/AppIcon.icns" ]] || fail "AppIcon.icns is missing"

ARCHITECTURES="$(lipo -archs "$EXECUTABLE_PATH")"
[[ " $ARCHITECTURES " == *" arm64 "* ]] || fail "Apple silicon executable slice is missing"
[[ " $ARCHITECTURES " == *" x86_64 "* ]] || fail "Intel executable slice is missing"

codesign --verify --deep --strict "$APP_PATH"

if [[ "$VERIFY_RELEASE_ASSETS" == "--release-assets" ]]; then
    VERSION="$(read_plist CFBundleShortVersionString)"
    RELEASE_ROOT="$PROJECT_ROOT/dist/releases"
    RELEASE_NAME="Knittany-$VERSION-macOS-universal"
    SBOM_NAME="Knittany-$VERSION.spdx.json"
    [[ -f "$RELEASE_ROOT/$RELEASE_NAME.zip" ]] || fail "release ZIP is missing"
    [[ -f "$RELEASE_ROOT/$RELEASE_NAME.dmg" ]] || fail "release DMG is missing"
    [[ -f "$RELEASE_ROOT/SHA256SUMS.txt" ]] || fail "release checksums are missing"
    [[ -f "$RELEASE_ROOT/$SBOM_NAME" ]] || fail "release software bill of materials is missing"
    plutil -convert json -o /dev/null "$RELEASE_ROOT/$SBOM_NAME" || fail "release software bill of materials is invalid JSON"
    unzip -tqq "$RELEASE_ROOT/$RELEASE_NAME.zip"
    ZIP_LISTING="$(unzip -Z1 "$RELEASE_ROOT/$RELEASE_NAME.zip")"
    [[ "$ZIP_LISTING" == *"FIRST OPEN - Knittany.txt"* ]] || fail "first-open instructions are missing from the ZIP"
    [[ "$ZIP_LISTING" == *"RELEASE NOTES - Knittany $VERSION.md"* ]] || fail "versioned release notes are missing from the ZIP"
    [[ "$ZIP_LISTING" == *"$SBOM_NAME"* ]] || fail "software bill of materials is missing from the ZIP"
    grep -q " $SBOM_NAME$" "$RELEASE_ROOT/SHA256SUMS.txt" || fail "software bill of materials is missing from checksums"
    hdiutil verify -quiet "$RELEASE_ROOT/$RELEASE_NAME.dmg"
    (cd "$RELEASE_ROOT" && shasum -a 256 -c SHA256SUMS.txt)
fi

print "Knittany release verification passed for $APP_PATH"
