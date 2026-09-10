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
  cp "$H/pre-merge-commit" "$H/post-merge" "$H/commit-msg" "$H/pre-rebase" "$d/.ai/hooks/"
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

echo "Self-disabling — the gate must not be configurable by the thing it gates:"
# git updates the working tree BEFORE these hooks run, so reading the conf from the
# working tree would hand the incoming branch control of the rule judging it. Both
# cases below merge a branch whose own commit relaxes that rule.

# A) branch un-gates dev in the conf, then merges itself into dev unstamped
D=$(mkrepo)
git -C "$D" checkout -q -b feature/sneaky dev
printf 'NOTE_GATED_BRANCHES=^nothing$\n' > "$D/.ai/flight-rules.conf"
echo y > "$D/h"; git -C "$D" add -A; git -C "$D" commit -qm "feature: sneaky"
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff feature/sneaky -m m >/dev/null 2>&1
say "$?" "1" "branch cannot un-gate its own merge via the conf"
git -C "$D" merge --abort 2>/dev/null; rm -rf "$D"

# B) branch relaxes PR_ONLY, then merges itself into main
D=$(mkrepo)
git -C "$D" checkout -q -b feature/sneaky2 main
printf 'PR_ONLY_BRANCHES=^nothing$\n' > "$D/.ai/flight-rules.conf"
echo y > "$D/h2"; git -C "$D" add -A; git -C "$D" commit -qm "feature: sneaky2"
git -C "$D" checkout -q main
git -C "$D" merge --no-ff feature/sneaky2 -m m >/dev/null 2>&1
say "$?" "1" "branch cannot relax PR-only for its own merge"
git -C "$D" merge --abort 2>/dev/null; rm -rf "$D"

# C) the legitimate path must still work: a conf committed on the TARGET is honoured
D=$(mkrepo)
git -C "$D" checkout -q dev
printf 'NOTE_GATED_BRANCHES=^nothing$\n' > "$D/.ai/flight-rules.conf"
git -C "$D" add -A; git -C "$D" commit -qm "chore: conf"
git -C "$D" checkout -q -b feature/legit dev
echo y > "$D/h3"; git -C "$D" add -A; git -C "$D" commit -qm "feature: legit"
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff feature/legit -m m >/dev/null 2>&1
say "$?" "0" "conf committed on the target still configures the gate"
rm -rf "$D"

echo "Back-merges — reconciling a PR-only branch into the integration branch needs no note:"
# Regression: a non-ff `git merge main` on dev was blocked because main's tip had no
# note — and nothing could legitimately stamp one. feature-start step 4 tells you to
# do exactly this merge.
D=$(mkrepo)
echo hot > "$D/h"; git -C "$D" add -A; git -C "$D" commit -qm "fix: landed on main via PR"
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff main -m "reconcile main into dev" >/dev/null 2>&1
say "$?" "0" "unstamped back-merge of main into dev is allowed"
rm -rf "$D"

# The exemption is for the PR-only branch's OWN tip, not for a feature branch that
# happens to share history with it: an unstamped feature merge stays blocked.
D=$(mkrepo)
git -C "$D" checkout -q -b feature/q dev
echo change > "$D/q"; git -C "$D" add -A; git -C "$D" commit -qm "feature: q"
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff feature/q -m "merge" >/dev/null 2>&1
say "$?" "1" "unstamped feature merge is still blocked after the back-merge exemption"
git -C "$D" merge --abort 2>/dev/null; rm -rf "$D"

# The incoming branch cannot make itself "PR-only" through the conf it ships.
D=$(mkrepo)
git -C "$D" checkout -q -b feature/sneaky3 dev
printf 'PR_ONLY_BRANCHES=^feature/sneaky3$\n' > "$D/.ai/flight-rules.conf"
echo y > "$D/s3"; git -C "$D" add -A; git -C "$D" commit -qm "feature: sneaky3"
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff feature/sneaky3 -m m >/dev/null 2>&1
say "$?" "1" "branch cannot declare itself PR-only to skip the note gate"
git -C "$D" merge --abort 2>/dev/null; rm -rf "$D"

echo "Back-merge exemption cannot be forged (post-merge review):"
# mkrepo_with_origin: a bare origin holding main, so refs/remotes/origin/main exists.
mkrepo_with_origin() {
  local d o; d=$(mkrepo); o=$(mktemp -d)
  git init -q --bare "$o"; git -C "$d" remote add origin "$o"
  git -C "$d" push -q origin main dev 2>/dev/null
  printf '%s' "$d"
}
# A) local main forced onto the feature tip: origin/main does not contain it → still gated.
D=$(mkrepo_with_origin)
git -C "$D" checkout -q -b feature/forge dev
echo y > "$D/fg"; git -C "$D" add -A; git -C "$D" commit -qm "feature: forge"
git -C "$D" branch -f main feature/forge
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff feature/forge -m m >/dev/null 2>&1
say "$?" "1" "local main pointed at a feature tip does not exempt it"
git -C "$D" merge --abort 2>/dev/null; rm -rf "$D"

# B) a stale third-party remote ref named main is not consulted.
D=$(mkrepo)
git -C "$D" checkout -q -b feature/stale dev
echo y > "$D/st"; git -C "$D" add -A; git -C "$D" commit -qm "feature: stale"
git -C "$D" update-ref refs/remotes/upstream/main HEAD
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff feature/stale -m m >/dev/null 2>&1
say "$?" "1" "upstream/main at the feature tip does not exempt it"
git -C "$D" merge --abort 2>/dev/null; rm -rf "$D"

# C) the legitimate case with an origin still passes: main advanced and pushed.
D=$(mkrepo_with_origin)
echo hot > "$D/h"; git -C "$D" add -A; git -C "$D" commit -qm "fix: on main"
git -C "$D" push -q origin main 2>/dev/null
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff main -m "reconcile" >/dev/null 2>&1
say "$?" "0" "back-merge of a main that origin has is allowed"
rm -rf "$D"

# D) main advanced locally but NOT pushed: not yet reviewed, so not exempt.
D=$(mkrepo_with_origin)
echo hot > "$D/h2"; git -C "$D" add -A; git -C "$D" commit -qm "fix: unpushed on main"
git -C "$D" checkout -q dev
git -C "$D" merge --no-ff main -m "reconcile" >/dev/null 2>&1
say "$?" "1" "back-merge of unpushed main commits is still gated"
git -C "$D" merge --abort 2>/dev/null; rm -rf "$D"

echo "Squash and rebase cannot slip a change onto a PR-only branch:"
D=$(mkrepo)
git -C "$D" checkout -q -b feature/sq main
echo y > "$D/sq"; git -C "$D" add -A; git -C "$D" commit -qm "feature: sq"
git -C "$D" checkout -q main
git -C "$D" merge --squash --ff feature/sq >/dev/null 2>&1
git -C "$D" commit -qm "squashed" >/dev/null 2>&1
say "$?" "1" "commit completing a squash merge into main is blocked"
rm -rf "$D"

D=$(mkrepo)
git -C "$D" checkout -q -b feature/rb main
echo y > "$D/rb"; git -C "$D" add -A; git -C "$D" commit -qm "feature: rb"
git -C "$D" checkout -q main
echo z > "$D/mz"; git -C "$D" add -A; git -C "$D" commit -qm "chore: on main"
git -C "$D" rebase feature/rb >/dev/null 2>&1
say "$?" "1" "rebasing main is blocked"
git -C "$D" rebase --abort 2>/dev/null
git -C "$D" checkout -q feature/rb
git -C "$D" rebase main >/dev/null 2>&1
say "$?" "0" "rebasing a feature onto main is allowed"
rm -rf "$D"

D=$(mkrepo)
git -C "$D" checkout -q dev
echo y > "$D/sqd"; git -C "$D" add -A
git -C "$D" commit -qm "chore: ordinary commit on dev" >/dev/null 2>&1
say "$?" "0" "squash guard does not touch ordinary commits on a non-PR-only branch"
rm -rf "$D"


echo "post-merge must never offer a protected branch for deletion:"
# Regression 2026-09-10: the merged-branch filter was the literal `main|staging` plus
# the integration branch, so a project calling its branches anything else had them
# listed as "safe to delete" in the note the next session is told to act on.
PM=$(mktemp -d)
git init -q -b trunk "$PM"
git -C "$PM" config user.email t@t.t; git -C "$PM" config user.name t
git -C "$PM" config merge.ff false
mkdir -p "$PM/.ai"
cat > "$PM/.ai/flight-rules.conf" <<'CONF'
PROTECTED_BRANCHES=^(trunk|qa|release-2)$
PR_ONLY_BRANCHES=^trunk$
INTEGRATION_BRANCH=trunk
CONF
echo base > "$PM/f.txt"; git -C "$PM" add -A; git -C "$PM" commit -qm "chore: base"
for b in qa release-2 feature/real; do
  git -C "$PM" checkout -qb "$b" 2>/dev/null
  echo "$b" > "$PM/${b//\//_}.txt"; git -C "$PM" add -A
  git -C "$PM" commit -qm "chore: on $b"
done
git -C "$PM" checkout -q trunk
mkdir -p "$PM/.ai/hooks"; cp "$H/pre-merge-commit" "$H/post-merge" "$H/commit-msg" "$H/pre-rebase" "$PM/.ai/hooks/"; chmod +x "$PM"/.ai/hooks/*; git -C "$PM" config core.hooksPath "$PM/.ai/hooks"
for b in qa release-2 feature/real; do
  git -C "$PM" merge --no-verify --no-edit "$b" >/dev/null 2>&1
done
NOTE="$PM/.claude/post-merge-note.md"
for prot in qa release-2 trunk; do
  if grep -q "git branch -d $prot\$" "$NOTE" 2>/dev/null; then
    FAIL=$((FAIL+1)); printf '  ❌ offered protected branch "%s" for deletion\n' "$prot"
  else
    PASS=$((PASS+1)); printf '  ✅ protected branch "%s" is not offered for deletion\n' "$prot"
  fi
done
if grep -q 'git branch -d feature/real' "$NOTE" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ a real feature branch is still offered\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ the note no longer offers merged feature branches\n'
fi
rm -rf "$PM"

echo "The note gate covers protected branches this project actually has:"
# With no NOTE_GATED_BRANCHES the gated set is "protected but not PR-only", so a
# project using its own names gets the gate without configuring one. The old default
# was the literal ^(dev|staging)$ and silently gated nothing here.
NG=$(mktemp -d)
git init -q -b trunk "$NG"
git -C "$NG" config user.email t@t.t; git -C "$NG" config user.name t
git -C "$NG" config merge.ff false
mkdir -p "$NG/.ai"
cat > "$NG/.ai/flight-rules.conf" <<'CONF'
PROTECTED_BRANCHES=^(trunk|qa)$
PR_ONLY_BRANCHES=^trunk$
INTEGRATION_BRANCH=trunk
CONF
echo base > "$NG/f.txt"; git -C "$NG" add -A; git -C "$NG" commit -qm "chore: base"
git -C "$NG" checkout -qb qa 2>/dev/null; git -C "$NG" checkout -q trunk
git -C "$NG" checkout -qb feature/w 2>/dev/null
echo w > "$NG/w.txt"; git -C "$NG" add -A; git -C "$NG" commit -qm "feature: w"
git -C "$NG" checkout -q qa
mkdir -p "$NG/.ai/hooks"; cp "$H/pre-merge-commit" "$H/post-merge" "$H/commit-msg" "$H/pre-rebase" "$NG/.ai/hooks/"; chmod +x "$NG"/.ai/hooks/*; git -C "$NG" config core.hooksPath "$NG/.ai/hooks"
OUT=$(git -C "$NG" merge --no-edit feature/w 2>&1)
if grep -q 'PRE-MERGE CHECK REQUIRED' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ "qa" is note-gated without being named in the conf\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ "qa" took an unstamped merge\n'
fi
git -C "$NG" merge --abort 2>/dev/null
# ...and a branch that is neither protected nor PR-only is still ungated.
git -C "$NG" checkout -qb scratch 2>/dev/null
OUT=$(git -C "$NG" merge --no-edit feature/w 2>&1)
if grep -q 'PRE-MERGE CHECK REQUIRED' <<<"$OUT"; then
  FAIL=$((FAIL+1)); printf '  ❌ an unprotected branch was gated\n'
else
  PASS=$((PASS+1)); printf '  ✅ an unprotected branch is not gated\n'
fi
rm -rf "$NG"
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
