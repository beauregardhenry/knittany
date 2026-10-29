#!/bin/zsh
set -euo pipefail

# Knittany.xcodeproj is generated from App/project.yml but checked in, so a source file added to
# App/Sources without regenerating leaves the app unbuildable. Catch that drift here instead of
# in a build failure minutes into CI.

PROJECT_ROOT="${0:A:h:h}"
PBXPROJ="$PROJECT_ROOT/App/Knittany.xcodeproj/project.pbxproj"

cd "$PROJECT_ROOT/App"

if [[ ! -f "$PBXPROJ" ]]; then
    print -u2 "Xcode project verification failed: $PBXPROJ is missing."
    exit 1
fi

typeset -a missing
for source in Sources/**/*.swift(.N); do
    if ! grep -qF "/* ${source:t} */" "$PBXPROJ"; then
        missing+=("$source")
    fi
done

if (( ${#missing} > 0 )); then
    print -u2 "Xcode project verification failed: Knittany.xcodeproj is out of date with App/Sources."
    for source in $missing; do
        print -u2 "  missing: App/$source"
    done
    print -u2 "Regenerate it with ./scripts/regenerate-xcode-project.sh and commit the result."
    exit 1
fi

print "Knittany.xcodeproj references all $(print -l Sources/**/*.swift(.N) | wc -l | tr -d ' ') app sources."
