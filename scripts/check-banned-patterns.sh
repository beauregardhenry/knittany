#!/bin/zsh
set -euo pipefail

# Four patterns that should never appear in the app or its libraries, all at zero. The floor is
# 0, forever: there's no baseline to manage, and the check fails the moment one appears.
#
# The `knit` command-line tool is left out: printing and exiting with an error message is its
# job. try! is allowed for compiling literal regular expressions once, a safe idiom that can only
# fail on a malformed literal the first time the file runs.

PROJECT_ROOT="${0:A:h:h}"
typeset -a SOURCE_DIRS
SOURCE_DIRS=("$PROJECT_ROOT/App/Sources" "$PROJECT_ROOT/KnitCore/Sources/KnitCore" "$PROJECT_ROOT/KnitCore/Sources/KnitRender" "$PROJECT_ROOT/KnitCore/Sources/KnitImport")

typeset -a findings
findings=()

check_pattern() {
    local label="$1"
    local grep_pattern="$2"
    local matches
    matches="$(grep -rnE "$grep_pattern" "${SOURCE_DIRS[@]}" --include='*.swift' || true)"
    if [[ -n "$matches" ]]; then
        findings+=("$label")
        print -u2 ""
        print -u2 "Found ${label}:"
        print -r -- "$matches" | while IFS= read -r line; do
            print -u2 "  ${line#$PROJECT_ROOT/}"
        done
    fi
}

check_pattern "as! (forced downcast)" '\bas!'
check_pattern "fatalError(" 'fatalError\('
check_pattern "print( (debug output left in)" '\bprint\('
check_pattern "TODO/FIXME comment markers" '//\s*(TODO|FIXME)'

if (( ${#findings} > 0 )); then
    print -u2 ""
    print -u2 "Banned-pattern check failed: ${#findings} pattern(s) found in the app or KnitCore."
    print -u2 "Replace a forced downcast or fatalError with a real error path, remove a leftover"
    print -u2 "debug print(), and either finish or file the TODO/FIXME before merging."
    exit 1
fi

print "Banned-pattern check passed: no as!, fatalError(, print(, or TODO/FIXME in the app or KnitCore."
