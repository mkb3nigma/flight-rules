#!/usr/bin/env bash
# Tests for agent/session-start.sh — the stale-worktree reminder injected into every
# session. Its output is advice the next session acts on, so a wrong name here is a
# worktree removed for nothing. wiring.test.sh only proves the hook RUNS; this proves
# what it says. Run: ./session-start.test.sh (no args, no network; throwaway repos).
set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$H/session-start.sh"
PASS=0; FAIL=0
say() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✅ $3"; else FAIL=$((FAIL+1)); echo "  ❌ $3 (got '$1', want '$2')"; fi; }

# A project with an integration branch, a worktree dir, and the hooks NOT installed
# (doctor's findings are its own suite's business; here they would drown the output,
# so core.hooksPath and merge.ff are set to keep doctor quiet).
mkrepo() {
  local d; d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b trunk
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  git -C "$d" config merge.ff false
  mkdir -p "$d/.ai/hooks" "$d/.ai/worktrees"
  cp "$H/../git/pre-merge-commit" "$H/../git/commit-msg" "$H/../git/pre-rebase" \
     "$H/../git/post-merge" "$H/../git/reference-transaction" "$d/.ai/hooks/"
  chmod +x "$d"/.ai/hooks/*
  git -C "$d" config core.hooksPath .ai/hooks
  printf 'INTEGRATION_BRANCH=trunk\nWORKTREE_DIR=.ai/worktrees\nPROTECTED_BRANCHES=^trunk$\n' \
    > "$d/.ai/flight-rules.conf"
  mkdir -p "$d/.claude"
  printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash .ai/hooks/agent/pre-commit-check.sh"}]}]}}' \
    > "$d/.claude/settings.json"
  mkdir -p "$d/.ai/hooks/agent"; cp "$H/pre-commit-check.sh" "$d/.ai/hooks/agent/"
  echo base > "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -qm "chore: base"
  printf '%s' "$d"
}
# branch <dir> <name> [merge]  — create a branch with a commit; merge it if asked.
branch() {
  git -C "$1" checkout -qb "$2" 2>/dev/null
  echo "$2" > "$1/${2//\//_}.txt"; git -C "$1" add -A
  git -C "$1" commit -qm "chore: on $2"
  git -C "$1" checkout -q trunk
  [ "${3:-}" = merge ] && git -C "$1" merge --no-verify --no-edit "$2" >/dev/null 2>&1
  return 0
}
# run <dir> → the hook's stdout. HOME is redirected so the once-a-day flag is fresh.
# Half the assertions below are satisfied by NO output, which is also what a hook that
# died produces — so a non-zero exit is turned into a line, and those assertions fail.
run() {
  local out rc
  out=$( (cd "$1" && HOME="$1/fakehome" bash "$HOOK" 2>/dev/null) ); rc=$?
  [ $rc -ne 0 ] && printf 'HARNESS: the hook exited %s — nothing was tested\n' "$rc"
  printf '%s' "$out"
}

echo "Stale-worktree reminder names the worktrees that are actually merged:"
D=$(mkrepo)
branch "$D" fix/merged merge
branch "$D" fix/open
git -C "$D" worktree add -q "$D/.ai/worktrees/merged" fix/merged
git -C "$D" worktree add -q "$D/.ai/worktrees/open" fix/open
OUT=$(run "$D")
say "$(grep -c 'Branch: fix/merged' <<<"$OUT")" "1" "a merged branch's worktree is reported"
say "$(grep -c 'Branch: fix/open' <<<"$OUT")"   "0" "an unmerged branch's worktree is not"
rm -rf "$D"

echo "A longer branch name is not the merged one (regression 2026-09-12):"
# The hook looks for the WORKTREE's branch inside the merged list, and the match was
# `grep -w`, which counts `-` as a word boundary. So with fix/auth-tokens merged, the
# line `fix/auth-tokens` contains a word-match for `fix/auth`, and a worktree on the
# unmerged fix/auth was reported safe to remove. That pair is an ordinary one.
D=$(mkrepo)
branch "$D" fix/auth-tokens merge
branch "$D" fix/auth
git -C "$D" worktree add -q "$D/.ai/worktrees/tokens" fix/auth-tokens
git -C "$D" worktree add -q "$D/.ai/worktrees/auth" fix/auth
OUT=$(run "$D")
# Paired: an "X is absent" assertion is also satisfied by a hook that printed nothing,
# so each one runs beside a "Y is present" assertion over the same output.
say "$(grep -cE 'Branch: fix/auth-tokens[[:space:]]' <<<"$OUT")" "1" "the merged fix/auth-tokens is reported"
say "$(grep -cE 'Branch: fix/auth[[:space:]]' <<<"$OUT")" "0" "an unmerged fix/auth is not reported because fix/auth-tokens is merged"
rm -rf "$D"

echo "A branch name is a name, not a pattern:"
# grep without -F reads the name as a BRE: `.` matched any character.
D=$(mkrepo)
branch "$D" fix/axb merge
branch "$D" fix/a.b
git -C "$D" worktree add -q "$D/.ai/worktrees/axb" fix/axb
git -C "$D" worktree add -q "$D/.ai/worktrees/dotted" fix/a.b
OUT=$(run "$D")
say "$(grep -c 'fix/axb' <<<"$OUT")" "1" "the merged fix/axb is reported"
say "$(grep -c 'fix/a\.b' <<<"$OUT")" "0" "fix/a.b is not matched by the merged fix/axb"
rm -rf "$D"

echo "A tag sharing a branch name does not hide the branch:"
# Regression 2026-09-12 (adversarial review): `%(refname:short)` abbreviates against ALL
# refs. With a tag named `trunk`, every branch merged into it comes back as
# `heads/<name>`, the whole-line match never fires, and the reminder silently stops
# reporting — the failure mode with no symptom. A bare `--merged trunk` resolves to the
# tag as well, so the merged set is computed against the wrong commit.
D=$(mkrepo)
branch "$D" fix/merged merge
# the tag has to shadow the branch being MATCHED for `short` to mangle it, and one on
# the integration branch for the `--merged` argument to resolve to the wrong object.
git -C "$D" tag fix/merged
git -C "$D" tag trunk
git -C "$D" worktree add -q "$D/.ai/worktrees/merged" fix/merged
OUT=$(run "$D")
say "$(grep -c 'Branch: fix/merged' <<<"$OUT")" "1" "a merged worktree is still reported when tags shadow the branch names"
say "$(grep -c 'heads/' <<<"$OUT")" "0" "no \`heads/\` prefix appears in the reminder"
rm -rf "$D"

echo "Nothing to say, nothing said:"
D=$(mkrepo)
branch "$D" fix/open
git -C "$D" worktree add -q "$D/.ai/worktrees/open" fix/open
say "$(run "$D" | grep -c .)" "0" "no merged worktrees → no output at all"
rm -rf "$D"

D=$(mkrepo)
say "$(run "$D" | grep -c .)" "0" "no worktree directory → no output"
rm -rf "$D"

echo "Once a day, per project:"
D=$(mkrepo)
branch "$D" fix/merged merge
git -C "$D" worktree add -q "$D/.ai/worktrees/merged" fix/merged
FIRST=$(run "$D")
SECOND=$(run "$D")
say "$(grep -c 'Branch: fix/merged' <<<"$FIRST")" "1" "the first run of the day reports"
say "$(grep -c . <<<"$SECOND" | tr -d ' ')" "0" "the second run of the day is silent"
# The flag used to carry only the date, so the first project opened each day took the
# reminder for every other project too.
E=$(mkrepo)
branch "$E" fix/merged merge
git -C "$E" worktree add -q "$E/.ai/worktrees/merged" fix/merged
# deliberately the FIRST project's HOME, so the flag is the one already touched
OTHER=$( (cd "$E" && HOME="$D/fakehome" bash "$HOOK" 2>/dev/null) ); OTHER_RC=$?
[ $OTHER_RC -ne 0 ] && OTHER="HARNESS: the hook exited $OTHER_RC"
say "$(grep -c 'Branch: fix/merged' <<<"$OTHER")" "1" "a different project the same day still reports"
rm -rf "$D" "$E"

echo "A detached-HEAD worktree has no branch and is skipped:"
D=$(mkrepo)
branch "$D" fix/merged merge
git -C "$D" worktree add -q "$D/.ai/worktrees/merged" fix/merged
git -C "$D" worktree add -q --detach "$D/.ai/worktrees/detached"
OUT=$(run "$D")
say "$(grep -c 'Branch: fix/merged' <<<"$OUT")" "1" "the merged worktree beside it is reported"
say "$(grep -c 'detached' <<<"$OUT")" "0" "a detached worktree is not reported stale"
rm -rf "$D"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
