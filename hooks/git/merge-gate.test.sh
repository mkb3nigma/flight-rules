#!/usr/bin/env bash
# Tests for the merge gate — pre-merge-commit (PR-only) + commit-msg (note gate).
#
# Run: ./merge-gate.test.sh   (no args, no network; builds throwaway repos)
# The whole point of this change is that the old placement silently did nothing,
# so this must be proven end-to-end against real git, not asserted.
set -uo pipefail
H="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"   # hooks/git dir under test
PASS=0; FAIL=0
say() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✅ $3"; else FAIL=$((FAIL+1)); echo "  ❌ $3 (got '$1', want '$2')"; fi; }

mkrepo() {
  local d; d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  mkdir -p "$d/.ai/hooks"
  cp "$H/pre-merge-commit" "$H/post-merge" "$H/commit-msg" "$d/.ai/hooks/"
  chmod +x "$d"/.ai/hooks/*
  git -C "$d" config core.hooksPath "$d/.ai/hooks"
  git -C "$d" config merge.ff false
  echo base > "$d/f"; git -C "$d" add -A; git -C "$d" commit -qm "base"
  git -C "$d" branch dev
  printf '%s' "$d"
}

echo "Note gate (merging a feature branch into dev):"

# 1. Unstamped merge into dev must be BLOCKED.
D=$(mkrepo)
git -C "$D" checkout -q -b feature/x dev
echo change > "$D/f2"; git -C "$D" add -A; git -C "$D" commit -qm "feature: x"
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff feature/x -m "merge" >/dev/null 2>&1
say "$?" "1" "unstamped merge into dev is blocked"
git -C "$D" merge --abort 2>/dev/null
rm -rf "$D"

# 2. Stamped merge into dev must be ALLOWED.
D=$(mkrepo)
git -C "$D" checkout -q -b feature/x dev
echo change > "$D/f2"; git -C "$D" add -A; git -C "$D" commit -qm "feature: x"
git -C "$D" notes --ref=pre-merge-check add -f -m "passed: 2026-08-01T00:00:00Z branch:feature/x" HEAD
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff feature/x -m "merge" >/dev/null 2>&1
say "$?" "0" "stamped merge into dev is allowed"
rm -rf "$D"

# 3. An ordinary (non-merge) commit on dev must not be gated.
D=$(mkrepo)
git -C "$D" checkout -q dev
echo x > "$D/f3"; git -C "$D" add -A
git -C "$D" commit -qm "chore: ordinary commit" >/dev/null 2>&1
say "$?" "0" "ordinary commit on dev is not gated"
rm -rf "$D"

# 4. A merge into an un-gated branch must pass without a note.
D=$(mkrepo)
git -C "$D" checkout -q -b scratch dev
git -C "$D" checkout -q -b feature/y scratch
echo change > "$D/f4"; git -C "$D" add -A; git -C "$D" commit -qm "feature: y"
git -C "$D" checkout -q scratch
git -C "$D" merge --no-ff feature/y -m "merge" >/dev/null 2>&1
say "$?" "0" "merge into a non-gated branch needs no note"
rm -rf "$D"

# 5. PR-only branch (main) still blocked by pre-merge-commit.
D=$(mkrepo)
git -C "$D" checkout -q -b feature/z main
echo change > "$D/f5"; git -C "$D" add -A; git -C "$D" commit -qm "feature: z"
git -C "$D" checkout -q main
git -C "$D" merge --no-ff feature/z -m "merge" >/dev/null 2>&1
say "$?" "1" "local merge into PR-only main is blocked"
git -C "$D" merge --abort 2>/dev/null
rm -rf "$D"

# 6. Config: .ai/flight-rules.conf can retarget the gated branch set.
D=$(mkrepo)
# The hook reads the conf from the working tree of the branch being merged INTO,
# so it must be committed on dev — not on main.
git -C "$D" checkout -q dev
printf 'NOTE_GATED_BRANCHES=^integration$\n' > "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null 2>&1; git -C "$D" commit -qm "chore: conf" >/dev/null 2>&1
git -C "$D" checkout -q -b feature/w dev
echo change > "$D/f6"; git -C "$D" add -A; git -C "$D" commit -qm "feature: w"
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff feature/w -m "merge" >/dev/null 2>&1
say "$?" "0" "conf retargets the gate: dev no longer gated"
rm -rf "$D"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
