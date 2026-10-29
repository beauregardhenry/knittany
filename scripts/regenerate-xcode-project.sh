#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"

if ! command -v xcodegen >/dev/null 2>&1; then
    print -u2 "XcodeGen is required to regenerate Knittany.xcodeproj. Install it with: brew install xcodegen"
    exit 1
fi

cd "$PROJECT_ROOT/App"
xcodegen generate --spec project.yml
print "Regenerated App/Knittany.xcodeproj from App/project.yml."
