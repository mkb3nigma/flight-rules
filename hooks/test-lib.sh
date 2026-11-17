# The harness every suite shares: sourced, never run, and never copied into a project
# (install.sh copies the hooks by name). Not named *.test.sh, so docs-consistency.test.sh
# does not take it for a suite.
PASS=0; FAIL=0

# say <got> <want> <description>
say() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✅ $3"; else FAIL=$((FAIL+1)); echo "  ❌ $3 (got '$1', want '$2')"; fi; }
# For checks that are not a got/want pair.
ok()  { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

# A fixture that cannot be built is not a test failure, it is an aborted run — so it
# stops the suite rather than being counted. The builders run inside command
# substitutions, where a FAIL increment would be discarded with the subshell; `$$` is
# the parent's pid even there, so the signal reaches the trap. Measured 2026-09-12: with
# the fixtures broken, pre-commit-check still scored 267 of 574, merge-gate 18 of 44,
# doctor 11 of 36, wiring 15 of 24 and session-start 6 of 16, and seven ref-gate
# assertions passed against a repo that was never built.
MAINPID=$$
trap 'printf "\n%s\n" "ABORTED: a fixture could not be built — no result above is meaningful" >&2; exit 2' TERM
die() { printf '  ❌ harness: %s\n' "$1" >&2; kill -s TERM "$MAINPID"; exit 2; }

# A new temporary directory, symlinks resolved: on macOS mktemp hands back /var/…, which
# git reports as /private/var/….
tmpd() { local d; d=$(mktemp -d) && (cd "$d" && pwd -P); }

# The last line of every suite: the count, and its exit status.
finish() { echo; echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }
