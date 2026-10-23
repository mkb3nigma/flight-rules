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

# A fixture that cannot be built is not a test failure, it is an aborted run — so it
# stops the suite rather than being counted. mkrepo and friends run inside command
# substitutions, where a FAIL increment would be discarded with the subshell; `$$` is
# the parent's pid even there, so the signal reaches the trap. Measured 2026-09-12:
# with every fixture repo broken this suite still scored 18 of 44.
MAINPID=$$
trap 'printf "\n%s\n" "ABORTED: a fixture could not be built — no result above is meaningful" >&2; exit 2' TERM
die() { printf '  ❌ harness: %s\n' "$1" >&2; kill -s TERM "$MAINPID"; exit 2; }

mkrepo() {
  local d; d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main || die "git init failed in $d"
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  mkdir -p "$d/.ai/hooks"
  cp "$H/pre-merge-commit" "$H/post-merge" "$H/commit-msg" "$H/pre-rebase" "$d/.ai/hooks/" \
    || die "could not copy the hooks under test from $H"
  chmod +x "$d"/.ai/hooks/*
  git -C "$d" config core.hooksPath "$d/.ai/hooks"
  git -C "$d" config merge.ff false
  echo base > "$d/f"; git -C "$d" add -A
  git -C "$d" commit -qm "base" >/dev/null || die "the base commit failed in $d"
  git -C "$d" branch dev || die "could not create dev in $d"
  # What every assertion assumes: both branches, and hooks that are actually wired.
  git -C "$d" rev-parse --verify -q main >/dev/null || die "no main in the fixture"
  git -C "$d" rev-parse --verify -q dev  >/dev/null || die "no dev in the fixture"
  [ -x "$d/.ai/hooks/pre-merge-commit" ] || die "pre-merge-commit not executable in the fixture"
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

# 2. Stamped AND authorised merge into dev must be ALLOWED.
# The authorisation half arrived 2026-09-10. Before it, this case read "stamped merge
# into dev is allowed" and passed with no authorisation at all — which was the hole:
# the agent stamps its own note, so that was a green tick on a merge nobody asked for.
D=$(mkrepo)
git -C "$D" checkout -q -b feature/x dev
echo change > "$D/f2"; git -C "$D" add -A; git -C "$D" commit -qm "feature: x"
git -C "$D" notes --ref=pre-merge-check add -f -m "passed: 2026-08-01T00:00:00Z branch:feature/x" HEAD
git -C "$D" checkout -q dev
FLIGHT_RULES_MERGE_AUTHORISED=1 git -C "$D" merge --no-ff feature/x -m "merge" >/dev/null 2>&1
say "$?" "0" "stamped AND authorised merge into dev is allowed"
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
  git init -q --bare "$o" || die "git init failed (git init -q --bare "$o")"; git -C "$d" remote add origin "$o"
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
git init -q -b trunk "$PM" || die "git init failed (git init -q -b trunk "$PM")"
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
  if grep -q "git branch -d '$prot'" "$NOTE" 2>/dev/null; then
    FAIL=$((FAIL+1)); printf '  ❌ offered protected branch "%s" for deletion\n' "$prot"
  else
    PASS=$((PASS+1)); printf '  ✅ protected branch "%s" is not offered for deletion\n' "$prot"
  fi
done
if grep -q "git branch -d 'feature/real'" "$NOTE" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ a real feature branch is still offered\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ the note no longer offers merged feature branches\n'
fi
rm -rf "$PM"

echo "post-merge: the cleanup note is a command you can paste:"
# Regression 2026-09-12: `git branch --merged` decorates its output — `*` for the
# current branch, `+` for one checked out in ANOTHER worktree — and the hook stripped
# only `*`. Following this repo's own worktree-per-change workflow therefore produced
# `git branch -d + fix/x` — error: branch '+' not found. The protected-branch test
# above could not see it: it anchors on `git branch -d trunk$`, and the decorated line
# does not end there. (A `+`-decorated INTEGRATION branch cannot arise: the hook exits
# unless the current branch is the integration branch, and git allows one checkout.)
# Its own base dir: the extra worktrees go beside the repo, not into the shared
# temp root where a leftover from an earlier run makes `worktree add` fail — silenced
# by 2>&1, that turned this whole case green against the unfixed hook.
WTB=$(mktemp -d); WT="$WTB/repo"
git init -q -b trunk "$WT" || die "git init failed (git init -q -b trunk "$WT")"
git -C "$WT" config user.email t@t.t; git -C "$WT" config user.name t
git -C "$WT" config merge.ff false
mkdir -p "$WT/.ai"
printf 'PROTECTED_BRANCHES=^trunk$\nPR_ONLY_BRANCHES=^trunk$\nINTEGRATION_BRANCH=trunk\n' > "$WT/.ai/flight-rules.conf"
echo base > "$WT/f.txt"; git -C "$WT" add -A; git -C "$WT" commit -qm "chore: base"
# Three merged branches. fix/ab exists because the substring filter dropped the longer
# name from the "previously merged" list whenever the shorter one was just merged;
# fix/c is the one that carries a worktree, so it is `+`-decorated AND not the branch
# just merged — the combination the old note actually printed as `git branch -d + fix/c`.
for b in fix/ab fix/c fix/a; do
  git -C "$WT" checkout -qb "$b" 2>/dev/null
  echo "$b" > "$WT/${b//\//_}.txt"; git -C "$WT" add -A; git -C "$WT" commit -qm "chore: on $b"
  git -C "$WT" checkout -q trunk
done
mkdir -p "$WT/.ai/hooks"
cp "$H/pre-merge-commit" "$H/post-merge" "$H/commit-msg" "$H/pre-rebase" "$WT/.ai/hooks/"
chmod +x "$WT"/.ai/hooks/*; git -C "$WT" config core.hooksPath "$WT/.ai/hooks"
for b in fix/ab fix/c; do git -C "$WT" merge --no-verify --no-edit "$b" >/dev/null 2>&1; done
# a worktree on a merged branch → git marks that branch `+`; and a detached one, which
# has no branch at all. A failure here is reported, not silenced: hidden by `2>&1` it
# made every assertion below vacuous.
git -C "$WT" worktree add -q "$WTB/wt-c" fix/c || { FAIL=$((FAIL+1)); echo "  ❌ fixture: worktree add failed"; }
git -C "$WT" worktree add -q --detach "$WTB/wt-det" || { FAIL=$((FAIL+1)); echo "  ❌ fixture: detached worktree add failed"; }
git -C "$WT" merge --no-verify --no-edit fix/a >/dev/null 2>&1
WNOTE="$WT/.claude/post-merge-note.md"

if grep -qE "^  git branch -d '?[*+]" "$WNOTE" 2>/dev/null; then
  FAIL=$((FAIL+1)); printf '  ❌ the note emits a decorated branch name: %s\n' "$(grep -m1 -E "^  git branch -d '?[*+]" "$WNOTE")"
else
  PASS=$((PASS+1)); printf '  ✅ no `*`/`+` marker reaches a git branch -d line\n'
fi
if grep -q "git branch -d 'fix/c'" "$WNOTE" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ a worktree-held merged branch is offered by its bare name\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ fix/c is not offered under its bare name\n'
fi
if grep -q 'wt-det' "$WNOTE" 2>/dev/null; then
  FAIL=$((FAIL+1)); printf '  ❌ a detached-HEAD worktree is reported stale (grep -qF "" matches everything)\n'
else
  PASS=$((PASS+1)); printf '  ✅ a detached-HEAD worktree is not reported stale\n'
fi
if grep -q "git branch -d 'fix/ab'" "$WNOTE" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ fix/ab survives the just-merged filter alongside fix/a\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ fix/ab was dropped as a substring of the just-merged fix/a\n'
fi

rm -rf "$WTB"

echo "post-merge: a tag sharing a branch name does not rename the branch:"
# Regression 2026-09-12 (adversarial review): `%(refname:short)` abbreviates against ALL
# refs, not refs/heads. With a tag named `trunk`, the integration branch comes back as
# `heads/trunk` — which matches neither `grep -vxF trunk` nor PROTECTED_BRANCHES=^trunk$,
# so the note offered `git branch -d heads/trunk`. A bare `--merged trunk` resolves to
# the tag as well, so the merged set is computed against the wrong commit.
AM=$(mktemp -d); AMR="$AM/repo"
git init -q -b trunk "$AMR" || die "git init failed (git init -q -b trunk "$AMR")"
git -C "$AMR" config user.email t@t.t; git -C "$AMR" config user.name t
git -C "$AMR" config merge.ff false
mkdir -p "$AMR/.ai"
printf 'PROTECTED_BRANCHES=^trunk$\nPR_ONLY_BRANCHES=^trunk$\nINTEGRATION_BRANCH=trunk\n' > "$AMR/.ai/flight-rules.conf"
echo base > "$AMR/f.txt"; git -C "$AMR" add -A; git -C "$AMR" commit -qm "chore: base"
for b in fix/old fix/new; do
  git -C "$AMR" checkout -qb "$b" 2>/dev/null
  echo "$b" > "$AMR/${b//\//_}.txt"; git -C "$AMR" add -A; git -C "$AMR" commit -qm "chore: on $b"
  git -C "$AMR" checkout -q trunk
done
mkdir -p "$AMR/.ai/hooks"
cp "$H/pre-merge-commit" "$H/post-merge" "$H/commit-msg" "$H/pre-rebase" "$AMR/.ai/hooks/"
chmod +x "$AMR"/.ai/hooks/*; git -C "$AMR" config core.hooksPath "$AMR/.ai/hooks"
git -C "$AMR" merge --no-verify --no-edit fix/old >/dev/null 2>&1
git -C "$AMR" tag trunk        # the ambiguity
git -C "$AMR" merge --no-verify --no-edit fix/new >/dev/null 2>&1
ANOTE="$AMR/.claude/post-merge-note.md"
if grep -q 'heads/' "$ANOTE" 2>/dev/null; then
  FAIL=$((FAIL+1)); printf '  ❌ a ref was named `heads/...` in the note: %s\n' "$(grep -m1 'heads/' "$ANOTE")"
else
  PASS=$((PASS+1)); printf '  ✅ no `heads/` prefix reaches the note\n'
fi
if grep -qE "git branch -d '?(heads/)?trunk" "$ANOTE" 2>/dev/null; then
  FAIL=$((FAIL+1)); printf '  ❌ the integration branch was offered for deletion: %s\n' "$(grep -m1 -E "git branch -d '?(heads/)?trunk" "$ANOTE")"
else
  PASS=$((PASS+1)); printf '  ✅ the integration branch is not offered even when a tag shadows it\n'
fi
if grep -q "git branch -d 'fix/old'" "$ANOTE" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ the real merged branch is still offered\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ fix/old was not offered — the merged set was computed against the tag\n'
fi
rm -rf "$AM"

echo "post-merge: the emitted commands quote what they interpolate:"
# `&`, `$`, `|` and parentheses are legal in a refname, and the note is advertised as a
# command you can paste. `git branch -d fix/a&b` backgrounds a DIFFERENT branch's deletion.
QB=$(mktemp -d); QR="$QB/repo"
git init -q -b trunk "$QR" || die "git init failed (git init -q -b trunk "$QR")"
git -C "$QR" config user.email t@t.t; git -C "$QR" config user.name t
git -C "$QR" config merge.ff false
mkdir -p "$QR/.ai"
printf 'PROTECTED_BRANCHES=^trunk$\nPR_ONLY_BRANCHES=^trunk$\nINTEGRATION_BRANCH=trunk\n' > "$QR/.ai/flight-rules.conf"
echo base > "$QR/f.txt"; git -C "$QR" add -A; git -C "$QR" commit -qm "chore: base"
git -C "$QR" checkout -qb 'fix/a&b' 2>/dev/null
echo x > "$QR/x.txt"; git -C "$QR" add -A; git -C "$QR" commit -qm "chore: x"
git -C "$QR" checkout -q trunk
mkdir -p "$QR/.ai/hooks"
cp "$H/pre-merge-commit" "$H/post-merge" "$H/commit-msg" "$H/pre-rebase" "$QR/.ai/hooks/"
chmod +x "$QR"/.ai/hooks/*; git -C "$QR" config core.hooksPath "$QR/.ai/hooks"
git -C "$QR" merge --no-verify --no-edit 'fix/a&b' >/dev/null 2>&1
QNOTE="$QR/.claude/post-merge-note.md"
if grep -q "git branch -d 'fix/a&b'" "$QNOTE" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ a name with shell metacharacters is quoted\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ fix/a&b is emitted unquoted: %s\n' "$(grep -m1 'branch -d' "$QNOTE")"
fi
rm -rf "$QB"

echo "The note gate covers protected branches this project actually has:"
# With no NOTE_GATED_BRANCHES the gated set is "protected but not PR-only", so a
# project using its own names gets the gate without configuring one. The old default
# was the literal ^(dev|staging)$ and silently gated nothing here.
NG=$(mktemp -d)
git init -q -b trunk "$NG" || die "git init failed (git init -q -b trunk "$NG")"
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

echo "A stamped merge still has to say who asked for it:"
# Measured 2026-09-10: with only the note gate, an agent stamped its own note, merged
# into a protected branch nobody had asked about, and the hook printed "✅ Pre-merge
# check verified". The advisory produced no warning of any kind — a green tick where
# the norm was violated. The note proves a check ran, not that a merge was wanted.
mkauth() {  # $1 = extra conf line; echoes the repo dir, on dev, feature/x stamped
  local d; d=$(mkrepo)
  { printf 'PROTECTED_BRANCHES=^(main|dev)$\nPR_ONLY_BRANCHES=^main$\nINTEGRATION_BRANCH=dev\n'
    [ -n "${1:-}" ] && printf '%s\n' "$1"; } > "$d/.ai/flight-rules.conf"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "chore: conf" >/dev/null 2>&1
  # dev is branched before the conf commit in mkrepo, and the hook reads the conf
  # from HEAD of the MERGE TARGET — so dev must actually carry it.
  git -C "$d" branch -f dev main >/dev/null 2>&1
  git -C "$d" checkout -q dev 2>/dev/null
  git -C "$d" checkout -qb feature/x 2>/dev/null
  echo x > "$d/x.txt"; git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm "feature: x" >/dev/null 2>&1
  git -C "$d" notes --ref=pre-merge-check add -f -m "passed: 2026-09-10T00:00:00Z branch:feature/x" HEAD >/dev/null 2>&1
  git -C "$d" checkout -q dev 2>/dev/null
  printf '%s' "$d"
}

D=$(mkauth)
BEFORE=$(git -C "$D" rev-parse dev)
OUT=$(git -C "$D" merge --no-edit feature/x 2>&1)
grep -q 'WHO ASKED FOR THIS MERGE' <<<"$OUT"
say "$?" "0" "a stamped but unauthorised merge is blocked"
grep -q 'FLIGHT_RULES_MERGE_AUTHORISED=1' <<<"$OUT"
say "$?" "0" "…and the block names the way to proceed"
[ "$(git -C "$D" rev-parse dev)" = "$BEFORE" ]
say "$?" "0" "…and dev did not move"
# The command the box prints is run as printed, in the state the refusal left: it
# printed `git merge <branch>`, which fails while the refused merge is still in
# progress — every time the box fired (#100).
# With the secret scan installed as a project has it: git commit runs pre-commit on a
# merge being concluded, which a hook-less fixture never exercised (fix review, F10).
cp "$H/pre-commit" "$D/.ai/hooks/" && chmod +x "$D/.ai/hooks/pre-commit" || die "could not copy pre-commit into $D"
CMD=$(grep -o 'FLIGHT_RULES_MERGE_AUTHORISED=1 git [^║]*' <<<"$OUT" | sed 's/[[:space:]]*$//')
say "$CMD" "FLIGHT_RULES_MERGE_AUTHORISED=1 git commit --no-edit" "…and prints the command that concludes it"
CONC=$(cd "$D" && eval "$CMD" 2>&1); RC=$?
say "$RC" "0" "…which, run as printed, exits 0"
# Its output is read: thrown away, the case also passed with no pre-commit run at all
# (group A fix review, F8).
say "$(grep -c '^pre-commit: concluding a merge of' <<<"$CONC")" "1" "…with the secret scan run on the merge it concludes"
say "$(git -C "$D" rev-parse dev^2 2>/dev/null)" "$(git -C "$D" rev-parse feature/x)" "…landing the merge"
git -C "$D" log -1 --pretty=%B | grep -q '^Merge-authorisation: explicit'
say "$?" "0" "…with the authorisation recorded"
git -C "$D" merge --abort 2>/dev/null; rm -rf "$D"

D=$(mkauth)
FLIGHT_RULES_MERGE_AUTHORISED=1 git -C "$D" merge --no-edit feature/x >/dev/null 2>&1
git -C "$D" log -1 --pretty=%B | grep -q '^Merge-authorisation: explicit'
say "$?" "0" "an authorised merge lands and records it in the commit"
# #62: grep found the line, git's trailer parser did not. The hook appended
# '\n<trailer>\n', meaning the leading newline to be the blank line a trailer block
# needs — but the message file git hands commit-msg for a non-interactive merge ends
# WITHOUT a trailing newline (probed 2026-10-04, git 2.55), so that newline only
# terminated the subject. Every owner merge on dev at c3a708e had the line glued to
# the subject and %(trailers) returned empty for all of them.
[ -n "$(git -C "$D" log -1 --format='%(trailers:key=Merge-authorisation,valueonly)')" ]
say "$?" "0" "…as a trailer git itself can parse, not just a greppable line"
rm -rf "$D"

D=$(mkauth)
FLIGHT_RULES_MERGE_AUTHORISED=0 git -C "$D" merge --no-edit feature/x >/dev/null 2>&1
[ "$(git -C "$D" log -1 --pretty=%s)" != "Merge branch 'feature/x' into dev" ]
say "$?" "0" "…=0 does not count as authorisation"
git -C "$D" merge --abort 2>/dev/null; rm -rf "$D"

D=$(mkauth "MERGE_NEEDS_INSTRUCTION=off")
git -C "$D" merge --no-edit feature/x >/dev/null 2>&1
git -C "$D" log -1 --pretty=%B | grep -q '^Merge-authorisation: not required'
say "$?" "0" "the project opt-out works, and history records that it was used"
[ -n "$(git -C "$D" log -1 --format='%(trailers:key=Merge-authorisation,valueonly)')" ]
say "$?" "0" "…and that record is a parseable trailer too"
rm -rf "$D"

# The trailer must not stack if the message is rewritten.
D=$(mkauth)
FLIGHT_RULES_MERGE_AUTHORISED=1 git -C "$D" merge --no-edit feature/x >/dev/null 2>&1
FLIGHT_RULES_MERGE_AUTHORISED=1 git -C "$D" commit -q --amend --no-edit >/dev/null 2>&1
N=$(git -C "$D" log -1 --pretty=%B | grep -c '^Merge-authorisation:')
say "$N" "1" "the trailer is not duplicated by an amend"
rm -rf "$D"

# What must NOT change.
D=$(mkauth)
git -C "$D" checkout -q main 2>/dev/null
echo m > "$D/m.txt"; git -C "$D" add -A >/dev/null 2>&1; git -C "$D" commit -qm "chore: on main" >/dev/null 2>&1
git -C "$D" checkout -q dev 2>/dev/null
OUT=$(git -C "$D" merge --no-edit main 2>&1)
grep -q 'Back-merge' <<<"$OUT"
say "$?" "0" "a back-merge of a PR-only branch still needs no authorisation"
rm -rf "$D"

D=$(mkauth)
echo z > "$D/z.txt"; git -C "$D" add -A >/dev/null 2>&1
git -C "$D" commit -qm "chore: ordinary" >/dev/null 2>&1
git -C "$D" log -1 --pretty=%B | grep -q 'Merge-authorisation'
say "$?" "1" "an ordinary commit on a protected branch gets no trailer"
rm -rf "$D"

D=$(mkauth)
git -C "$D" checkout -qb scratch 2>/dev/null
git -C "$D" merge --no-edit feature/x >/dev/null 2>&1
git -C "$D" log -1 --pretty=%B | grep -q 'Merge-authorisation'
say "$?" "1" "merging into an unprotected branch is not gated at all"
rm -rf "$D"
echo "post-merge names the branch for the subject the owner flow actually writes:"
# #63: since 2026-09-15 the owner merges into dev locally from origin/<branch>, so the
# subject is "Merge remote-tracking branch 'origin/x' into dev" — and the parser knew
# "Merge branch 'x'", "Merge pull request #N from o/x" and "Merge x into y", none of
# which match it. Every owner merge on dev since 0.22.0 was recorded as `unknown` and
# lost its "← just merged" line. The local branch is what `git branch -d` wants, so
# the `origin/` prefix is stripped.
D=$(mkauth); O=$(mktemp -d)
git -C "$O" init -q --bare || die "git init --bare failed in $O"
git -C "$D" remote add origin "$O"
git -C "$D" push -q origin main dev feature/x 2>/dev/null || die "could not push the fixture to its origin"
FLIGHT_RULES_MERGE_AUTHORISED=1 git -C "$D" merge --no-edit origin/feature/x >/dev/null 2>&1
say "$?" "0" "merging origin/feature/x into dev lands"
[ "$(git -C "$D" log -1 --pretty=%s)" = "Merge remote-tracking branch 'origin/feature/x' into dev" ]
say "$?" "0" "…with the remote-tracking subject (the fixture is the real shape)"
grep -q '^## Post-merge to dev: `feature/x`' "$D/.claude/post-merge-note.md" 2>/dev/null
say "$?" "0" "…and the note names feature/x, not unknown"
grep -q "git branch -d 'feature/x'  ← just merged" "$D/.claude/post-merge-note.md" 2>/dev/null
say "$?" "0" "…and offers the local branch for deletion as just merged"
grep -q "refused until" "$D/.claude/post-merge-note.md" 2>/dev/null
say "$?" "1" "…with no push warning: feature/x has no upstream, so -d works now"
rm -rf "$D" "$O"
# …and when there is no local branch of that name — merged straight from origin — there
# is nothing to delete, so `git branch -d` would only fail (/dg, 2026-10-08).
D=$(mkauth); O=$(mktemp -d)
git -C "$O" init -q --bare || die "git init --bare failed in $O"
git -C "$D" remote add origin "$O"
git -C "$D" push -q origin main dev feature/x 2>/dev/null || die "could not push the fixture to its origin"
git -C "$D" branch -qD feature/x || die "could not delete the local feature/x"
git -C "$D" branch -q fix/old dev || die "could not make fix/old"   # so the list is not empty
FLIGHT_RULES_MERGE_AUTHORISED=1 git -C "$D" merge --no-edit origin/feature/x >/dev/null 2>&1
grep -q '^## Post-merge to dev: `feature/x`' "$D/.claude/post-merge-note.md" 2>/dev/null
say "$?" "0" "with no local feature/x, the note still names it"
grep -q "git branch -d 'feature/x'" "$D/.claude/post-merge-note.md" 2>/dev/null
say "$?" "1" "…but does not offer a branch that is not there for deletion"
grep -q "git branch -d 'fix/old'" "$D/.claude/post-merge-note.md" 2>/dev/null
say "$?" "0" "…while a merged one that is there is still offered"
rm -rf "$D" "$O"

echo "post-merge says when git branch -d will refuse, and only then:"
# A branch cut with `-b fix/x origin/dev` tracks origin/dev, and `git branch -d` judges
# it against that, so it is refused until dev is pushed — and the note is written
# before the push (2026-10-04).
D=$(mkauth); O=$(mktemp -d)
git -C "$O" init -q --bare || die "git init --bare failed in $O"
git -C "$D" remote add origin "$O"
git -C "$D" push -q origin main dev 2>/dev/null || die "could not push the fixture to its origin"
git -C "$D" branch -q --set-upstream-to=origin/dev feature/x || die "could not make feature/x track origin/dev"
git -C "$D" branch -q plain dev && git -C "$D" branch -q --set-upstream-to=origin/dev plain \
  || die "could not make the already-pushed branch"
FLIGHT_RULES_MERGE_AUTHORISED=1 git -C "$D" merge --no-edit feature/x >/dev/null 2>&1
say "$?" "0" "merging feature/x (tracking origin/dev) into dev lands"
git -C "$D" branch -d feature/x >/dev/null 2>&1
say "$?" "1" "…and git branch -d refuses it before dev is pushed (the case is real)"
grep -qF "git branch -d 'feature/x'  ← just merged  (refused until origin/dev has it — push that first)" "$D/.claude/post-merge-note.md" 2>/dev/null
say "$?" "0" "…and the note says origin/dev must have it first"
grep -q "git branch -d 'plain'$" "$D/.claude/post-merge-note.md" 2>/dev/null
say "$?" "0" "…but not for a branch its upstream already has"
git -C "$D" push -q origin dev 2>/dev/null || die "could not push dev in the fixture"
git -C "$D" branch -d feature/x >/dev/null 2>&1
say "$?" "0" "…and after the push, -d deletes it"
rm -rf "$D" "$O"

echo "…and says nothing where -d would in fact delete:"
# Each of these was annotated by the first version while `git branch -d` deleted the
# branch: git judges against HEAD when the upstream ref does not resolve, and the short
# upstream name is not a refs/remotes/ path for a local upstream or next to a tag.
D=$(mkauth); O=$(mktemp -d)
git -C "$O" init -q --bare || die "git init --bare failed in $O"
git -C "$D" remote add origin "$O"
git -C "$D" push -q origin main dev 2>/dev/null || die "could not push the fixture to its origin"
git -C "$D" push -q -u origin feature/x 2>/dev/null || die "could not push feature/x"
git -C "$D" push -q origin --delete feature/x 2>/dev/null && git -C "$D" fetch -q --prune origin \
  || die "could not make feature/x's upstream gone"
git -C "$D" branch -q local-up feature/x && git -C "$D" branch -q --set-upstream-to=main local-up \
  || die "could not make the branch with a local upstream"
git -C "$D" branch -q tagged feature/x && git -C "$D" branch -q --set-upstream-to=origin/dev tagged \
  && git -C "$D" tag origin/dev main || die "could not make the tag that shadows origin/dev"
FLIGHT_RULES_MERGE_AUTHORISED=1 git -C "$D" merge --no-edit feature/x >/dev/null 2>&1
git -C "$D" push -q origin dev 2>/dev/null || die "could not push dev"
(cd "$D" && .ai/hooks/post-merge 0) >/dev/null 2>&1 || die "post-merge failed when run directly"
NOTE="$D/.claude/post-merge-note.md"
grep -qE "^  git branch -d 'feature/x'  ← just merged$" "$NOTE" 2>/dev/null
say "$?" "0" "an upstream gone from the remote: no annotation"
grep -qE "^  git branch -d 'tagged'$" "$NOTE" 2>/dev/null
say "$?" "0" "a tag named origin/dev beside the branch: no annotation"
grep -qE "^  git branch -d 'local-up'  \(refused until main contains it\)$" "$NOTE" 2>/dev/null
say "$?" "0" "a local upstream that lacks it: 'contains', not 'push'"
for b in feature/x tagged; do git -C "$D" branch -d "$b" >/dev/null 2>&1 || echo "$b"; done > "$D/undeleted"
say "$(cat "$D/undeleted")" "" "…and -d really deletes the unannotated ones"
rm -rf "$D" "$O"

echo "…under a remote that is not called origin:"
D=$(mkauth); O=$(mktemp -d)
git -C "$O" init -q --bare || die "git init --bare failed in $O"
git -C "$D" remote add upstream "$O"
git -C "$D" push -q upstream main dev 2>/dev/null || die "could not push the fixture to upstream"
git -C "$D" branch -q --set-upstream-to=upstream/dev feature/x || die "could not make feature/x track upstream/dev"
FLIGHT_RULES_MERGE_AUTHORISED=1 git -C "$D" merge --no-edit feature/x >/dev/null 2>&1
grep -qF "(refused until upstream/dev has it" "$D/.claude/post-merge-note.md" 2>/dev/null
say "$?" "0" "the note names upstream/dev"
rm -rf "$D" "$O"


echo
echo "install.sh lists hooks, not directories or dotted files:"
# A consuming project may keep its own agent/ scripts under .ai/hooks/; git only runs
# bare file names at the top level, so a directory is not an active hook and must not
# be listed as one. The positive assertion on the same run keeps the negatives honest.
D=$(mkrepo)
cp "$H/reference-transaction" "$H/install.sh" "$D/.ai/hooks/" || die "could not copy install.sh"
# Without pre-commit nothing scans `git add f && git commit` for a key (#71), so a
# copy that left it out must be refused, not installed half built.
OUT=$(cd "$D" && bash .ai/hooks/install.sh 2>&1); RC=$?
say "$RC" "1" "install.sh refuses when pre-commit is missing"
grep -q 'pre-commit is missing' <<<"$OUT"
say "$?" "0" "…and names it"
cp "$H/pre-commit" "$D/.ai/hooks/" || die "could not copy pre-commit"
mkdir -p "$D/.ai/hooks/agent"; touch "$D/.ai/hooks/README.md"
OUT=$(cd "$D" && bash .ai/hooks/install.sh 2>&1); RC=$?
say "$RC" "0" "install.sh exits 0 with an agent/ subdirectory and a README beside the hooks"
grep -qE '^ +pre-merge-commit$' <<<"$OUT"
say "$?" "0" "install.sh lists pre-merge-commit as an active hook"
grep -qE '^ +agent$' <<<"$OUT"
say "$?" "1" "install.sh does not list the agent/ directory as an active hook"
grep -q 'README' <<<"$OUT"
say "$?" "1" "install.sh still skips dotted files"
rm -rf "$D"

echo "A pattern that does not compile matches every branch, not none (#103):"
# conf_on <repo> <branch> <conf line>: commit the conf on <branch>, where the hooks
# read it from (HEAD of the branch merged into).
conf_on() {
  git -C "$1" checkout -q "$2" || die "no $2 in $1"
  mkdir -p "$1/.ai"; printf '%s\n' "$3" > "$1/.ai/flight-rules.conf"
  git -C "$1" add -A >/dev/null; git -C "$1" commit -qm "chore: conf" --no-verify >/dev/null || die "could not commit the conf"
}
# route <output> <key>: the two-line route a refusal prints, its frame stripped.
route() { grep -A1 -F "FLIGHT_RULES_$2='<pattern>' \\" <<<"$1" | head -2 | sed -e 's/^║ *//' -e 's/ *║$//'; }
feature() {   # <repo> <name> <base>: a one-commit branch off <base>, stamped
  git -C "$1" checkout -q -b "$2" "$3" || die "could not branch $2"
  echo "$2" > "$1/$(echo "$2" | tr / _)"; git -C "$1" add -A; git -C "$1" commit -qm "feature: $2" >/dev/null || die "could not commit on $2"
  git -C "$1" notes --ref=pre-merge-check add -f -m "passed: 2026-10-22T00:00:00Z branch:$2" HEAD
}

# pre-merge-commit: a broken PR_ONLY_BRANCHES let every local merge through.
D=$(mkrepo); conf_on "$D" dev 'PR_ONLY_BRANCHES=^(main'; feature "$D" feature/x dev
git -C "$D" checkout -q dev; BEFORE=$(git -C "$D" rev-parse dev)
OUT=$(cd "$D" && FLIGHT_RULES_MERGE_AUTHORISED=1 git merge --no-ff feature/x -m merge 2>&1); RC=$?
say "$RC" "1" "PR_ONLY_BRANCHES that does not compile: a stamped, authorised merge into dev is refused"
say "$(grep -c 'PR_ONLY_BRANCHES DOES NOT COMPILE — LOCAL MERGE BLOCKED' <<<"$OUT")" "1" "…by the broken-pattern box"
say "$(grep -cF '  ^(main' <<<"$OUT")" "1" "…naming the pattern"
say "$(git -C "$D" rev-parse dev)" "$BEFORE" "…and dev does not move"
say "$(route "$OUT" PR_ONLY_BRANCHES | tail -1)" "git commit --no-edit" "…printing the command that finishes the merge it left"
# The route is for a branch the pattern does not mean: following it on main lands a
# local merge there (#103 review).
say "$(grep -cF 'if dev is not a branch it means' <<<"$OUT")" "1" "…for a branch the pattern does not mean"
# Run from where the refusal leaves you, the merge still in progress: `git merge` again
# fails there ("You have not concluded your merge"), as #100's did, and an abort before
# it is what hid that (#103 review).
(cd "$D" && FLIGHT_RULES_PR_ONLY_BRANCHES='^main$' FLIGHT_RULES_MERGE_AUTHORISED=1 git commit --no-edit) >/dev/null 2>&1
say "$?" "0" "…and that command, with the pattern meant, lands the merge"
say "$(git -C "$D" rev-parse -q --verify dev^2)" "$(git -C "$D" rev-parse feature/x)" "…as a merge of feature/x"
rm -rf "$D"

# pre-rebase: a rebase of any branch is refused.
D=$(mkrepo); conf_on "$D" dev 'PR_ONLY_BRANCHES=^(main'; feature "$D" feature/r dev
# main moves on, so the rebase has something to do: an up-to-date one never runs the hook.
git -C "$D" checkout -q main; echo m > "$D/m"; git -C "$D" add -A; git -C "$D" commit -qm "chore: m" >/dev/null
git -C "$D" checkout -q feature/r
OUT=$(cd "$D" && git rebase main 2>&1); RC=$?
say "$RC" "1" "PR_ONLY_BRANCHES that does not compile: a rebase is refused"
say "$(grep -c 'PR_ONLY_BRANCHES DOES NOT COMPILE — REBASE BLOCKED' <<<"$OUT")" "1" "…by the broken-pattern box"
git -C "$D" rebase --abort 2>/dev/null
rm -rf "$D"

# commit-msg's squash guard: a squash merge finished by a commit, on any branch.
D=$(mkrepo); conf_on "$D" dev 'PR_ONLY_BRANCHES=^(main'; feature "$D" feature/s dev
git -C "$D" checkout -q dev
# --ff: with merge.ff=false git refuses --squash outright, and nothing is staged.
git -C "$D" merge --squash --ff feature/s >/dev/null 2>&1
OUT=$(cd "$D" && git commit -m "squash" 2>&1); RC=$?
say "$RC" "1" "PR_ONLY_BRANCHES that does not compile: a squash merge's commit is refused"
say "$(grep -c 'PR_ONLY_BRANCHES DOES NOT COMPILE — SQUASH MERGE BLOCKED' <<<"$OUT")" "1" "…by the broken-pattern box"
rm -rf "$D"

# commit-msg's note gate: a broken NOTE_GATED_BRANCHES, or PROTECTED_BRANCHES with none
# set, gated nothing. Unstamped feature branches, so the gate has something to refuse.
for KEY in NOTE_GATED_BRANCHES PROTECTED_BRANCHES; do
  D=$(mkrepo); conf_on "$D" dev "$KEY=^(dev"
  git -C "$D" checkout -q -b feature/n dev; echo n > "$D/n"; git -C "$D" add -A; git -C "$D" commit -qm "feature: n" >/dev/null
  git -C "$D" checkout -q dev
  OUT=$(cd "$D" && git merge --no-ff feature/n -m merge 2>&1); RC=$?
  say "$RC" "1" "$KEY that does not compile: an unstamped merge into dev is refused"
  say "$(grep -cF "Gated because $KEY (^(dev)" <<<"$OUT")" "1" "…saying the pattern is why"
  git -C "$D" merge --abort 2>/dev/null
  git -C "$D" notes --ref=pre-merge-check add -f -m "passed: 2026-10-22T00:00:00Z branch:feature/n" feature/n
  (cd "$D" && FLIGHT_RULES_MERGE_AUTHORISED=1 git merge --no-ff feature/n -m merge) >/dev/null 2>&1
  say "$?" "0" "…while a stamped, authorised one lands as usual"
  # Every branch is gated, so a sync merge of dev into a feature branch is refused too,
  # and the refusal printed no route that worked (#103 review). Run as printed, from
  # the merge it leaves in progress.
  git -C "$D" checkout -q -b feature/sync dev
  git -C "$D" checkout -q dev; echo more > "$D/more"; git -C "$D" add -A
  git -C "$D" commit -qm "chore: more" --no-verify >/dev/null || die "could not commit on dev"
  git -C "$D" checkout -q feature/sync
  OUT=$(cd "$D" && git merge --no-ff dev -m sync 2>&1); RC=$?
  say "$RC" "1" "…and a sync merge of dev into a feature branch is refused"
  P='^dev$'
  CMD=$(route "$OUT" "$KEY")
  CMD=${CMD//"<pattern>"/$P}
  (cd "$D" && eval "$CMD") >/dev/null 2>&1
  say "$?" "0" "…and the route it prints, run as printed, lands it"
  say "$(git -C "$D" rev-parse -q --verify feature/sync^2)" "$(git -C "$D" rev-parse dev)" "…as a merge of dev"
  rm -rf "$D"
done

# The exemptions take a real match only. A conflicted merge skips pre-merge-commit, so
# commit-msg alone judges it: with a broken PR_ONLY_BRANCHES in the environment, the
# incoming branch is not taken for a reviewed back-merge, nor dev for PR-only.
D=$(mkrepo); git -C "$D" checkout -q -b feature/c dev
echo theirs > "$D/f"; git -C "$D" add -A; git -C "$D" commit -qm "feature: c" >/dev/null
git -C "$D" checkout -q dev; echo ours > "$D/f"; git -C "$D" add -A; git -C "$D" commit -qm "chore: ours" >/dev/null
git -C "$D" merge feature/c >/dev/null 2>&1; echo resolved > "$D/f"; git -C "$D" add f
OUT=$(cd "$D" && FLIGHT_RULES_PR_ONLY_BRANCHES='^(main' git commit --no-edit 2>&1); RC=$?
say "$RC" "1" "a broken PR_ONLY_BRANCHES grants no back-merge exemption: the unstamped merge is refused"
say "$(grep -c 'PRE-MERGE CHECK REQUIRED' <<<"$OUT")" "1" "…by the note gate"
rm -rf "$D"

# `off` names no branch. Read as a pattern it matched any branch with "off" in its
# name, which pre-merge-commit and pre-rebase then took for PR-only (#103 review).
D=$(mkrepo); conf_on "$D" main 'PR_ONLY_BRANCHES=off'
git -C "$D" checkout -q -b feature/offline main; feature "$D" feature/o feature/offline
git -C "$D" checkout -q feature/offline
(cd "$D" && git merge --no-ff feature/o -m merge) >/dev/null 2>&1
say "$?" "0" "PR_ONLY_BRANCHES=off: a merge into feature/offline is not gated"
(cd "$D" && git rebase main) >/dev/null 2>&1
say "$?" "0" "…nor a rebase of it"
rm -rf "$D"
# …and no merge is a back-merge: `off` read as a pattern matched feature/offline, so an
# unstamped merge of it into dev passed as a reviewed back-merge (#103 review).
D=$(mkrepo); conf_on "$D" dev "$(printf 'PR_ONLY_BRANCHES=off\nNOTE_GATED_BRANCHES=^dev$')"
git -C "$D" checkout -q -b feature/offline dev; echo o > "$D/o"; git -C "$D" add -A
git -C "$D" commit -qm "feature: offline" >/dev/null || die "could not commit on feature/offline"
git -C "$D" checkout -q dev
OUT=$(cd "$D" && git merge --no-ff feature/offline -m merge 2>&1); RC=$?
say "$RC" "1" "PR_ONLY_BRANCHES=off: an unstamped merge of feature/offline into dev is refused"
say "$(grep -c 'PRE-MERGE CHECK REQUIRED' <<<"$OUT")" "1" "…by the note gate, not taken for a back-merge"
rm -rf "$D"

echo "End to end, with an origin and every hook: landing the fix to a broken pattern (#103 review):"
# Each gate was tested alone, so nothing ran the printed way out from the state a
# refusal leaves, or met the ref gate on a branch ahead of its upstream.
E=$(cd "$(mktemp -d)" && pwd -P); D="$E/w"
git init -q --bare -b main "$E/up.git" || die "git init --bare failed in $E"
git clone -q "$E/up.git" "$D" 2>/dev/null || die "git clone failed in $E"
git -C "$D" config user.email t@t.t; git -C "$D" config user.name t; git -C "$D" config merge.ff false
mkdir -p "$D/.ai"; printf 'PR_ONLY_BRANCHES=^(main\n' > "$D/.ai/flight-rules.conf"
echo base > "$D/f"; git -C "$D" add -A; git -C "$D" commit -qm base >/dev/null || die "the base commit failed in $D"
git -C "$D" branch dev || die "could not create dev in $D"
git -C "$D" push -q origin main dev 2>/dev/null || die "could not push main and dev to $E/up.git"
mkdir -p "$E/hooks"
cp "$H/pre-merge-commit" "$H/post-merge" "$H/commit-msg" "$H/pre-rebase" "$H/reference-transaction" "$E/hooks/" \
  || die "could not copy the hooks under test from $H"
chmod +x "$E"/hooks/*; git -C "$D" config core.hooksPath "$E/hooks"
git -C "$D" fetch -q origin
git -C "$D" checkout -q -b fix/conf dev
printf 'PR_ONLY_BRANCHES=^main$\n' > "$D/.ai/flight-rules.conf"
git -C "$D" commit -qam "fix: conf" >/dev/null || die "could not commit the conf fix"
git -C "$D" notes --ref=pre-merge-check add -f -m "passed: 2026-10-23T00:00:00Z branch:fix/conf" HEAD
git -C "$D" checkout -q dev
OUT=$(cd "$D" && FLIGHT_RULES_MERGE_AUTHORISED=1 git merge --no-ff fix/conf -m "Merge fix/conf" 2>&1); RC=$?
say "$RC" "1" "e2e: the owner's merge of the fix into dev is refused by the broken pattern"
# The printed command, run as printed: only <pattern> filled in, plus the variable the
# refused command carried, as the box says to keep.
CMD=$(route "$OUT" PR_ONLY_BRANCHES)
P='^main$'; CMD=${CMD//"<pattern>"/$P}
say "$(tail -1 <<<"$CMD")" "git commit --no-edit" "…printing the command that finishes it"
(cd "$D" && eval "FLIGHT_RULES_MERGE_AUTHORISED=1 $CMD") >/dev/null 2>&1
say "$?" "0" "…which lands it"
say "$(git -C "$D" rev-parse -q --verify dev^2)" "$(git -C "$D" rev-parse fix/conf)" "…as a merge of fix/conf"
# dev is now ahead of origin/dev, whose conf the ref gate still reads, and is broken.
# A refused merge's undo writes dev to the value it has: no move, so not refused.
git -C "$D" checkout -q -b feature/late dev; echo late > "$D/late"; git -C "$D" add -A
git -C "$D" commit -qm "feature: late" >/dev/null || die "could not commit on feature/late"
git -C "$D" checkout -q dev; BEFORE=$(git -C "$D" rev-parse dev)
(cd "$D" && git merge --no-ff feature/late -m merge) >/dev/null 2>&1
say "$?" "1" "…an unstamped merge into dev, ahead of origin/dev, is refused by the note gate"
(cd "$D" && git merge --abort) >/dev/null 2>&1
say "$?" "0" "…and git merge --abort, its undo, is not refused as a move"
say "$(git -C "$D" rev-parse dev)" "$BEFORE" "…and leaves dev where it was"
(cd "$D" && git commit -q --allow-empty -m "chore: direct") >/dev/null 2>&1; RC=$?
say "$([ "$RC" -ne 0 ] && git -C "$D" rev-parse dev)" "$BEFORE" "…while a commit that does move dev off origin/dev still is, until dev is pushed"
git -C "$D" push -q origin dev 2>/dev/null || die "could not push dev to $E/up.git"
git -C "$D" fetch -q origin
(cd "$D" && git commit -q --allow-empty -m "chore: direct") >/dev/null 2>&1
say "$?" "0" "…and once it is, the fixed conf is what the ref gate reads"
rm -rf "$E"

echo "Branch patterns match case-insensitively, as the agent guard matches them (#103 review):"
# The git hooks matched case-sensitively, so ^MAIN$ named no branch to them while the
# agent guard and the README took it for main.
D=$(mkrepo); conf_on "$D" main 'PR_ONLY_BRANCHES=^MAIN$'; feature "$D" feature/u main
git -C "$D" checkout -q main
OUT=$(cd "$D" && git merge --no-ff feature/u -m merge 2>&1); RC=$?
say "$RC" "1" "PR_ONLY_BRANCHES=^MAIN\$: a local merge into main is refused"
say "$(grep -c 'main IS PR-ONLY — LOCAL MERGE BLOCKED' <<<"$OUT")" "1" "…by the PR-only box"
git -C "$D" merge --abort 2>/dev/null
echo m > "$D/m"; git -C "$D" add -A; git -C "$D" commit -qm "chore: on main" --no-verify >/dev/null || die "could not commit on main"
OUT=$(cd "$D" && git rebase feature/u 2>&1); RC=$?
say "$RC" "1" "…and a rebase of main"
say "$(grep -c 'main IS PR-ONLY — REBASE BLOCKED' <<<"$OUT")" "1" "…by the PR-only box"
git -C "$D" rebase --abort 2>/dev/null
git -C "$D" merge --squash --ff feature/u >/dev/null 2>&1
OUT=$(cd "$D" && git commit -m "squash" 2>&1); RC=$?
say "$RC" "1" "…and a squash merge's commit"
say "$(grep -c 'main IS PR-ONLY — SQUASH MERGE BLOCKED' <<<"$OUT")" "1" "…by the PR-only box"
rm -rf "$D"
D=$(mkrepo); conf_on "$D" dev 'PROTECTED_BRANCHES=^(MAIN|DEV)$'
git -C "$D" checkout -q -b feature/n dev; echo n > "$D/n"; git -C "$D" add -A; git -C "$D" commit -qm "feature: n" >/dev/null
git -C "$D" checkout -q dev
OUT=$(cd "$D" && git merge --no-ff feature/n -m merge 2>&1); RC=$?
say "$RC" "1" "PROTECTED_BRANCHES=^(MAIN|DEV)\$: an unstamped merge into dev is refused"
say "$(grep -c 'PRE-MERGE CHECK REQUIRED' <<<"$OUT")" "1" "…by the note gate"
rm -rf "$D"

echo "…but an exemption takes the pattern's exact case (#103 review):"
# Read case-insensitively, ^main$ took a branch anyone can make for main, and an
# unstamped merge of it into dev passed as a reviewed back-merge. A pattern in the
# wrong case now gates the merge it meant to exempt, and the refusal says why.
D=$(mkrepo); conf_on "$D" dev 'PR_ONLY_BRANCHES=^MAIN$'
git -C "$D" checkout -q main; echo m > "$D/m"; git -C "$D" add -A; git -C "$D" commit -qm "chore: on main" >/dev/null
git -C "$D" checkout -q dev
OUT=$(cd "$D" && git merge --no-ff main -m merge 2>&1); RC=$?
say "$RC" "1" "PR_ONLY_BRANCHES=^MAIN\$: merging main into dev is not taken for a back-merge"
say "$(grep -c 'Not taken for a back-merge: main matches' <<<"$OUT")" "1" "…and the refusal says the case is why"
CMD=$(route "$OUT" PR_ONLY_BRANCHES); P='^main$'; CMD=${CMD//"<pattern>"/$P}
OUT=$(cd "$D" && eval "$CMD" 2>&1)
say "$?" "0" "…and the route it prints, with the pattern in main's case, lands it"
say "$(grep -c 'Back-merge of PR-only branch main' <<<"$OUT")" "1" "…as a back-merge"
rm -rf "$D"
# The case is named only where it is the whole reason: a local main forced onto an
# unstamped commit fails origin's check as well, and the case route would not land it.
D=$(mkrepo_with_origin); conf_on "$D" dev 'PR_ONLY_BRANCHES=^MAIN$'; git -C "$D" fetch -q origin
git -C "$D" checkout -q -b feature/z dev; echo z > "$D/z"; git -C "$D" add -A; git -C "$D" commit -qm "feature: z" >/dev/null
git -C "$D" branch -f main feature/z || die "could not point main at feature/z in $D"
git -C "$D" checkout -q dev
OUT=$(cd "$D" && git merge --no-ff main -m merge 2>&1); RC=$?
say "$RC" "1" "PR_ONLY_BRANCHES=^MAIN\$: a local main forced off origin/main is refused"
say "$(grep -c 'Not taken for a back-merge' <<<"$OUT")" "0" "…without blaming the case"
say "$(grep -c 'PRE-MERGE CHECK REQUIRED' <<<"$OUT")" "1" "…by the note gate"
rm -rf "$D"
# The two ways in, with prod PR-only so that no branch of the same name is there for a
# case-variant one to collide with on a case-insensitive filesystem. A local PROD at an
# unstamped commit:
D=$(mkrepo); conf_on "$D" dev 'PR_ONLY_BRANCHES=^prod$'
git -C "$D" checkout -q -b feature/p dev; echo p > "$D/p"; git -C "$D" add -A; git -C "$D" commit -qm "feature: p" >/dev/null
git -C "$D" branch PROD || die "could not create PROD in $D"
git -C "$D" checkout -q dev
OUT=$(cd "$D" && git merge --no-ff PROD -m merge 2>&1); RC=$?
say "$RC" "1" "PR_ONLY_BRANCHES=^prod\$: a local PROD at an unstamped commit is not a back-merge"
say "$(grep -c 'PRE-MERGE CHECK REQUIRED' <<<"$OUT")" "1" "…the note gate refuses it"
rm -rf "$D"
# …and Prod pushed to an origin that has no prod, read from its remote-tracking ref.
D=$(mkrepo); conf_on "$D" dev 'PR_ONLY_BRANCHES=^prod$'
O=$(mktemp -d); git init -q --bare "$O" || die "git init --bare failed in $O"
git -C "$D" remote add origin "$O"
git -C "$D" checkout -q -b feature/p dev; echo p > "$D/p"; git -C "$D" add -A; git -C "$D" commit -qm "feature: p" >/dev/null
git -C "$D" push -q origin feature/p:Prod 2>/dev/null || die "could not push Prod to $O"
git -C "$D" fetch -q origin; git -C "$D" rev-parse -q --verify origin/Prod >/dev/null || die "no origin/Prod in $D"
git -C "$D" checkout -q dev
OUT=$(cd "$D" && git merge --no-ff origin/Prod -m merge 2>&1); RC=$?
say "$RC" "1" "…nor is origin/Prod"
say "$(grep -c 'PRE-MERGE CHECK REQUIRED' <<<"$OUT")" "1" "…the note gate refuses it"
rm -rf "$D" "$O"
# The other exemption: a PR-only branch is not note-gated by the derived set. A
# conflicted merge skips pre-merge-commit, so commit-msg alone judges it; with
# ^DEV$, dev is not exempt from the note gate.
D=$(mkrepo); conf_on "$D" dev 'PR_ONLY_BRANCHES=^DEV$'
git -C "$D" checkout -q -b feature/c dev
echo theirs > "$D/f"; git -C "$D" add -A; git -C "$D" commit -qm "feature: c" >/dev/null
git -C "$D" checkout -q dev; echo ours > "$D/f"; git -C "$D" add -A; git -C "$D" commit -qm "chore: ours" --no-verify >/dev/null
git -C "$D" merge feature/c >/dev/null 2>&1; echo resolved > "$D/f"; git -C "$D" add f
OUT=$(cd "$D" && git commit --no-edit 2>&1); RC=$?
say "$RC" "1" "PR_ONLY_BRANCHES=^DEV\$: a conflicted, unstamped merge into dev is not exempt from the note gate"
say "$(grep -c 'PRE-MERGE CHECK REQUIRED' <<<"$OUT")" "1" "…the note gate refuses it"
rm -rf "$D"
PM=$(mktemp -d)
git init -q -b trunk "$PM" || die "git init failed in $PM"
git -C "$PM" config user.email t@t.t; git -C "$PM" config user.name t; git -C "$PM" config merge.ff false
mkdir -p "$PM/.ai"; printf 'PROTECTED_BRANCHES=^(TRUNK|QA)$\nPR_ONLY_BRANCHES=^TRUNK$\nINTEGRATION_BRANCH=trunk\n' > "$PM/.ai/flight-rules.conf"
echo base > "$PM/f.txt"; git -C "$PM" add -A; git -C "$PM" commit -qm "chore: base"
for b in qa feature/real; do
  git -C "$PM" checkout -qb "$b" trunk; echo "$b" > "$PM/${b//\//_}.txt"; git -C "$PM" add -A
  git -C "$PM" commit -qm "chore: on $b"
done
git -C "$PM" checkout -q trunk
mkdir -p "$PM/.ai/hooks"; cp "$H/pre-merge-commit" "$H/post-merge" "$H/commit-msg" "$H/pre-rebase" "$PM/.ai/hooks/"; chmod +x "$PM"/.ai/hooks/*; git -C "$PM" config core.hooksPath "$PM/.ai/hooks"
for b in qa feature/real; do git -C "$PM" merge --no-verify --no-edit "$b" >/dev/null 2>&1; done
say "$(grep -c "git branch -d 'qa'" "$PM/.claude/post-merge-note.md" 2>/dev/null)" "0" "post-merge with PROTECTED_BRANCHES=^(TRUNK|QA)\$: qa is not offered for deletion"
say "$(grep -c "git branch -d 'feature/real'" "$PM/.claude/post-merge-note.md" 2>/dev/null)" "1" "…while a merged feature branch is"
rm -rf "$PM"

echo "A trailing comment in the conf does not turn a gate off (#103 review):"
# pre-merge-commit and pre-rebase kept it as part of the pattern, which then matched no
# branch, so a local merge into main landed in a repo with no origin.
D=$(mkrepo); conf_on "$D" main 'PR_ONLY_BRANCHES=^main$   # only main'; feature "$D" feature/k main
git -C "$D" checkout -q main
OUT=$(cd "$D" && git merge --no-ff feature/k -m merge 2>&1); RC=$?
say "$RC" "1" "PR_ONLY_BRANCHES=^main\$ with a comment: a local merge into main is refused"
say "$(grep -c 'main IS PR-ONLY — LOCAL MERGE BLOCKED' <<<"$OUT")" "1" "…by the PR-only box"
git -C "$D" merge --abort 2>/dev/null
echo m > "$D/m"; git -C "$D" add -A; git -C "$D" commit -qm "chore: on main" --no-verify >/dev/null || die "could not commit on main"
OUT=$(cd "$D" && git rebase feature/k 2>&1); RC=$?
say "$RC" "1" "…and a rebase of main"
say "$(grep -c 'main IS PR-ONLY — REBASE BLOCKED' <<<"$OUT")" "1" "…by the PR-only box"
git -C "$D" rebase --abort 2>/dev/null
rm -rf "$D"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
