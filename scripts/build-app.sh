#!/bin/zsh
set -euo pipefail

# Builds the universal (Apple silicon and Intel) Release app from the checked-in Xcode project
# into dist/Knittany.app, ad-hoc signed. Developer ID signing and notarization are
# scripts/release.sh, once the Apple Developer account exists.

PROJECT_ROOT="${0:A:h:h}"
DIST_ROOT="$PROJECT_ROOT/dist"
APP_ROOT="$DIST_ROOT/Knittany.app"
DERIVED="$PROJECT_ROOT/build/DerivedData"

cd "$PROJECT_ROOT"
xcodebuild -project App/Knittany.xcodeproj -scheme Knittany -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
    build -quiet

rm -rf "$APP_ROOT"
mkdir -p "$DIST_ROOT"
ditto "$DERIVED/Build/Products/Release/Knittany.app" "$APP_ROOT"
print "$APP_ROOT"
