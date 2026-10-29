#!/bin/zsh
set -euo pipefail

# The test count only ratchets one way: this fails when the number of tests drops below the one
# recorded in test-count-baseline.txt, so a test quietly deleted, commented out or lost in a merge
# shows up even when coverage barely moves.
#
# Counting is static: a grep for Swift Testing's @Test attribute, not a test run, so it's fast and
# needs nothing built.
#
# Don't bump test-count-baseline.txt from a feature branch. .github/workflows/test-count-ratchet.yml
# re-measures on every push to main and commits the raised number itself.
#
#   ./scripts/check-test-count.sh                     measure and enforce the baseline (what a PR runs)
#   ./scripts/check-test-count.sh --update-if-higher  raise the baseline only if the count climbed
#                                                     (what the post-merge workflow runs on main)
#   ./scripts/check-test-count.sh --update            rewrite it unconditionally, e.g. to lower it
#                                                     deliberately, with a reason in the commit

PROJECT_ROOT="${0:A:h:h}"
BASELINE_FILE="$PROJECT_ROOT/test-count-baseline.txt"

count="$(grep -rhoE '^[[:space:]]*@Test\b' "$PROJECT_ROOT/KnitCore/Tests" --include='*.swift' | wc -l | tr -d '[:space:]')"
print "Swift test count: ${count}"

mode=check
case "${1:-}" in
    --update) mode=update ;;
    --update-if-higher) mode=update-if-higher ;;
    "") ;;
    *)
        print -u2 "Usage: ${0:t} [--update|--update-if-higher]"
        exit 2
        ;;
esac

write_baseline() {
    cat > "$BASELINE_FILE" <<BASELINE
# Test count floor for the Swift test suite. Raised automatically by
# .github/workflows/test-count-ratchet.yml on every push to main; don't bump it from a feature
# branch (see the header of scripts/check-test-count.sh). Lower it only deliberately, with a
# reason in the commit.
swift=$1
BASELINE
}

baseline="$(sed -n 's/^swift=//p' "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"

if [[ "$mode" == "update" ]]; then
    write_baseline "$count"
    print "Baseline updated to swift=${count}. Commit test-count-baseline.txt."
    exit 0
fi

if [[ -z "$baseline" ]]; then
    if [[ "$mode" == "update-if-higher" ]]; then
        write_baseline "$count"
        print "No baseline recorded yet; seeded it at swift=${count}."
        exit 0
    fi
    print "No test-count baseline recorded yet, so nothing to enforce."
    exit 0
fi

if (( count < baseline )); then
    print -u2 "Test count check failed: ${count} tests is below the ${baseline} baseline."
    print -u2 "A test was removed or commented out. Add it back, or lower test-count-baseline.txt"
    print -u2 "deliberately and say why in the commit."
    exit 1
elif (( count > baseline )); then
    print "Test count rose to ${count} from the ${baseline} baseline."
    if [[ "$mode" == "update-if-higher" ]]; then
        write_baseline "$count"
        print "Baseline raised to swift=${count}. Committing test-count-baseline.txt."
        exit 0
    fi
    print "No action needed: the post-merge test-count-ratchet workflow will raise the baseline."
else
    print "Test count holds at ${count}."
fi
