#!/usr/bin/env bash
# Do this repo's DOCUMENTS agree with each other, with .ai/flight-rules.conf, and with CI?
#
# Every other suite tests code. Three findings in the 0.22.0 release candidate were not
# code — they were prose in CLAUDE.md, skills/pr-create/SKILL.md and
# rules/git-worktree-workflow.md, each individually written, contradicting each other only
# in combination. 861 test cases, a 810-verdict differential and a cross-family review on
# every PR could not see them, because nothing read two documents at once.
#
# Only what is MECHANICALLY checkable lives here. "Does this sentence still describe the
# behaviour" is judgement and stays with pre-merge-check item 17; pretending otherwise
# would give a green suite and a false sense of coverage. What is checkable is agreement
# between a value stated in one place and the same value stated in another.
#
# Run: ./docs-consistency.test.sh (no args, no network, reads only).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }

CONF=.ai/flight-rules.conf
[ -r "$CONF" ] || { printf '  ❌ harness: %s is not readable — nothing below was tested\n' "$CONF" >&2; exit 2; }
conf() { sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"[:space:]#]+)\"?.*$/\1/p" "$CONF" | tail -1; }

PROTECTED=$(conf PROTECTED_BRANCHES)
PR_ONLY=$(conf PR_ONLY_BRANCHES)
NOTE_GATED=$(conf NOTE_GATED_BRANCHES)
INTEGRATION=$(conf INTEGRATION_BRANCH)
WORKTREE=$(conf WORKTREE_DIR)
[ -n "$INTEGRATION" ] || { printf '  ❌ harness: no INTEGRATION_BRANCH in %s\n' "$CONF" >&2; exit 2; }

echo "CLAUDE.md's parameter table states the values the hooks actually read:"
# The table is the first thing an assistant reads about this repo, and it is a COPY of the
# conf. A copy that drifts sends every session down the wrong workflow while every hook
# enforces the right one.
tablerow() { sed -n -E "s/^\| \`\{$1\}\` \| (.*) \|$/\1/p" CLAUDE.md | head -1; }
# Keys and values in two index-aligned lists, NOT packed into one "key|value" string:
# every value here is a regex that CONTAINS `|`, so `${pair##*|}` strips to the last one
# and `^(main|dev)$` arrives as `dev`. That made this very check pass without ever looking
# at `main` — caught 2026-09-14 by reading its own output, before it was committed.
CKEY=(  PROTECTED_BRANCHES PR_ONLY_BRANCHES NOTE_GATED_BRANCHES INTEGRATION_BRANCH )
CVAL=( "$PROTECTED"       "$PR_ONLY"       "$NOTE_GATED"       "$INTEGRATION"      )
i=0
while [ $i -lt ${#CKEY[@]} ]; do
  key="${CKEY[$i]}"; val="${CVAL[$i]}"; i=$((i+1))
  row=$(tablerow "$key")
  [ -n "$val" ] || continue                     # key absent from the conf: nothing to agree with
  if [ -z "$row" ]; then
    bad "CLAUDE.md's table has no row for {$key}, which the conf sets to $val"
    continue
  fi
  # The row is prose. Every branch name in the regex must appear somewhere in it.
  missing=""
  for b in $(printf '%s' "$val" | tr -d '^$()' | tr '|' ' '); do
    case "$b" in ""|"*") continue ;; esac
    grep -qF -- "$b" <<<"$row" || missing="$missing $b"
  done
  if [ -n "$missing" ]; then
    bad "CLAUDE.md's {$key} row does not mention:$missing (conf says $val)"
  else
    ok "{$key} — table and conf agree on:$(printf '%s' "$val" | tr -d '^$()' | tr '|' ' ' | sed 's/^/ /')"
  fi
done

echo "The worktree directory in the table is the one the hooks use:"
if grep -qF -- "$WORKTREE" <<<"$(tablerow WORKTREE_DIR)"; then
  ok "{WORKTREE_DIR} — $WORKTREE"
else
  bad "CLAUDE.md's {WORKTREE_DIR} row does not mention $WORKTREE"
fi

echo "{TEST_COMMANDS} lists every suite that exists, and only those:"
# session-start.test.sh was written on 2026-09-12 and had to be added here, to CI and to
# hooks/README.md by hand. A suite nobody runs is a suite that rots.
ON_DISK=$(find . -name '*.test.sh' -not -path './.ai/*' | sed 's|^\./||' | sort)
LISTED=$(sed -n -E 's/^\| `\{TEST_COMMANDS\}` \| (.*)$/\1/p' CLAUDE.md \
         | grep -oE '[A-Za-z0-9_./-]+\.test\.sh' | sort -u)
for f in $ON_DISK; do
  grep -qxF "$f" <<<"$LISTED" || bad "$f exists but {TEST_COMMANDS} does not list it — nothing runs it"
done
for f in $LISTED; do
  [ -f "$f" ] || bad "{TEST_COMMANDS} lists $f, which is not there"
done
[ "$ON_DISK" = "$LISTED" ] && ok "$(printf '%s\n' "$ON_DISK" | grep -c .) suites, all listed, none missing"

echo "CI runs every suite in {TEST_COMMANDS}:"
CI=.github/workflows/tests.yml
if [ ! -r "$CI" ]; then
  bad "$CI is not readable"
else
  for f in $LISTED; do
    grep -qF -- "$f" "$CI" || bad "$f is in {TEST_COMMANDS} but CI never runs it"
  done
  ok "all $(printf '%s\n' "$LISTED" | grep -c .) listed suites appear in $CI"

  # A branch that moves by LOCAL merge is never covered by a pull_request event. dev was
  # pushed untested for two days under a CLAUDE.md that claimed CI on both branches.
  if grep -qE '^ *branches: \[.*\b'"$INTEGRATION"'\b.*\]' "$CI"; then
    ok "CI triggers on a push to the integration branch ($INTEGRATION)"
  else
    bad "CI has no push trigger for $INTEGRATION — it moves by local merge, which no pull_request event covers"
  fi
fi

echo "The skill that opens PRs can open the one this project needs:"
# pr-create forbids a PR whose head is protected. On a two-branch project the integration
# branch is usually protected too — so without an explicit exception the skill forbids the
# release PR it defines. Found on 2026-09-14, by trying to do the release.
SK=skills/pr-create/SKILL.md
if [ -n "$PROTECTED" ] && [ "$PROTECTED" != "off" ] && [ "$PROTECTED" != "none" ] \
   && ( [[ "$INTEGRATION" =~ $PROTECTED ]] ) 2>/dev/null; then
  if grep -q 'except the release PR' "$SK"; then
    ok "$INTEGRATION is protected, and pr-create names the release-PR exception"
  else
    bad "$INTEGRATION is protected and is the PR head for a release, but pr-create's protected-head rule has no exception — the skill forbids the release it describes"
  fi
else
  ok "the integration branch is not protected; no exception needed"
fi

echo "A release has somewhere to put the version bump:"
# The bump cannot land on a protected integration branch directly, and the promotion PR's
# head IS that branch — so unless a release branch is documented, there is no legal place
# for it. The first promotion attempt is what found this.
if [ -n "$PROTECTED" ] && [ "$PROTECTED" != "off" ] && [ "$PROTECTED" != "none" ] \
   && ( [[ "$INTEGRATION" =~ $PROTECTED ]] ) 2>/dev/null; then
  if grep -qiE 'chore/release|release branch' CLAUDE.md; then
    ok "CLAUDE.md documents where the version bump is committed"
  else
    bad "$INTEGRATION is protected, so the bump cannot be committed on it — and CLAUDE.md names no release branch"
  fi
else
  ok "the bump can be committed on the integration branch directly"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
