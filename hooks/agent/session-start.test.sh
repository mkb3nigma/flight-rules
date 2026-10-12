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

# A fixture that cannot be built is not a test failure, it is an aborted run — so it
# stops the suite rather than being counted. The builders below run inside command
# substitutions, where a FAIL increment would be discarded with the subshell; `$$` is
# the parent's pid even there, so the signal reaches the trap. Measured 2026-09-12:
# with every fixture repo broken this suite still scored 6 of 16.
MAINPID=$$
trap 'printf "\n%s\n" "ABORTED: a fixture could not be built — no result above is meaningful" >&2; exit 2' TERM
die() { printf '  ❌ harness: %s\n' "$1" >&2; kill -s TERM "$MAINPID"; exit 2; }

# A project with an integration branch, a worktree dir, and the enforcement installed
# far enough to keep doctor quiet — session-start runs doctor first, and its findings
# are flight-rules-doctor.test.sh's business, not this suite's. They would drown every assertion here.
mkrepo() {
  local d; d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b trunk || die "git init failed in $d"
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  git -C "$d" config merge.ff false
  mkdir -p "$d/.ai/hooks" "$d/.ai/worktrees"
  cp "$H/../git/pre-merge-commit" "$H/../git/commit-msg" "$H/../git/pre-rebase" \
     "$H/../git/post-merge" "$H/../git/reference-transaction" "$H/../git/pre-commit" "$d/.ai/hooks/"
  chmod +x "$d"/.ai/hooks/*
  git -C "$d" config core.hooksPath .ai/hooks
  printf 'INTEGRATION_BRANCH=trunk\nWORKTREE_DIR=.ai/worktrees\nPROTECTED_BRANCHES=^trunk$\n' \
    > "$d/.ai/flight-rules.conf"
  mkdir -p "$d/.claude"
  printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash .ai/hooks/agent/pre-commit-check.sh"}]}]}}' \
    > "$d/.claude/settings.json"
  mkdir -p "$d/.ai/hooks/agent"; cp "$H/pre-commit-check.sh" "$d/.ai/hooks/agent/"
  echo base > "$d/f.txt"; git -C "$d" add -A
  git -C "$d" commit -qm "chore: base" >/dev/null || die "the base commit failed in $d"
  # What every assertion assumes: trunk exists, and there is a worktree dir to scan.
  git -C "$d" rev-parse --verify -q trunk >/dev/null || die "no trunk in the fixture"
  [ -d "$d/.ai/worktrees" ] || die "no worktree directory in the fixture"
  printf '%s' "$d"
}
# branch <dir> <name> [merge]  — create a branch with a commit; merge it if asked.
branch() {
  git -C "$1" checkout -qb "$2" 2>/dev/null || die "could not create branch $2 in $1"
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
  # The real output is DISCARDED on a non-zero exit, not appended to: a hook that
  # printed the expected line and then died would otherwise satisfy every presence
  # assertion. Nothing a crashed run said is evidence of anything.
  if [ $rc -ne 0 ]; then
    printf 'HARNESS: the hook exited %s — nothing below was tested\n' "$rc"
    return
  fi
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
say "$(run "$D" | grep -c .)" "0" "an empty worktree directory → no output"
rm -rf "$D"

D=$(mkrepo); rmdir "$D/.ai/worktrees"
say "$(run "$D" | grep -c .)" "0" "no worktree directory at all → no output"
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

echo "A plugin update is checked the same day, not the next:"
# The once-a-day flag carried no version, so a session started after an update that day
# found it touched and skipped doctor — the one place an upgrade's missing git hook is
# reported (/dg, 2026-10-08). The flag now names the plugin version.
T=$(cd "$(mktemp -d)" && pwd -P); mkdir -p "$T/.claude-plugin" "$T/hooks/agent"
cp "$HOOK" "$T/hooks/agent/" && cp "$H/../flight-rules-doctor.sh" "$T/hooks/" || die "could not lay out the fake plugin"
printf '{ "name": "flight-rules", "version": "1.0.0" }\n' > "$T/.claude-plugin/plugin.json"
D=$(mkrepo); git -C "$D" config --unset merge.ff   # a problem for doctor to report
PRUN() { (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>/dev/null); }
say "$(PRUN | grep -c 'flight-rules doctor')" "1" "the first session of the day runs doctor"
say "$(PRUN | grep -c 'flight-rules doctor')" "0" "…the second, same version, does not"
printf '{ "name": "flight-rules", "version": "1.0.1" }\n' > "$T/.claude-plugin/plugin.json"
say "$(PRUN | grep -c 'flight-rules doctor')" "1" "…the first after an update, same day, does"
rm -rf "$D" "$T"

echo "HOOK_SYNC=auto brings a provably stale git hook up to date; anything else only reports:"
# A plugin update cannot touch the project's committed git hooks: AppliHawk ran four
# 0.22.0 hooks under a 0.23.0 plugin and the only signal was a CHANGELOG paragraph
# (2026-10-12). Opted in through the conf, the first session after an update replaces a
# copy that is byte-identical to an older release in the plugin cache and leaves the
# diff to commit; a copy matching no release may be the project's own and is left to
# doctor to name. The fake plugin is laid out as the cache has it, so session-start can
# find hooks/git/ and the version beside itself.
mkplugin() {
  local t; t=$(cd "$(mktemp -d)" && pwd -P); mkdir -p "$t/.claude-plugin" "$t/hooks/agent" "$t/hooks/git"
  cp "$HOOK" "$t/hooks/agent/" && cp "$H/../flight-rules-doctor.sh" "$t/hooks/" \
    && cp "$H"/../git/pre-merge-commit "$H"/../git/commit-msg "$H"/../git/pre-rebase "$H"/../git/post-merge \
          "$H"/../git/reference-transaction "$H"/../git/pre-commit "$H"/../git/install.sh "$t/hooks/git/" \
    || die "could not lay out the fake plugin"
  printf '{ "name": "flight-rules", "version": "9.9.9" }\n' > "$t/.claude-plugin/plugin.json"
  printf '%s' "$t"
}
# stale <repo> <hook>: the project's copy is an older release's, and that release is in the cache.
stale() {
  mkdir -p "$1/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git"
  { cat "$H/../git/$2"; echo "# flight-rules 0.0.1"; } > "$1/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/$2"
  cp "$1/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/$2" "$1/.ai/hooks/$2"
}
PRUN() { (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?"; }
T=$(mkplugin); D=$(mkrepo); stale "$D" commit-msg; echo "# own" >> "$D/.ai/hooks/post-merge"
printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "the hook exits 0"
say "$(grep -c 'HOOK_SYNC=auto updated git hooks' <<<"$OUT")" "1" "says it updated hooks"
say "$(grep -c 'synced commit-msg (flight-rules 9.9.9)' <<<"$OUT")" "1" "…names the hook and the release"
say "$(cmp -s "$D/.ai/hooks/commit-msg" "$T/hooks/git/commit-msg" && echo same)" "same" "the stale commit-msg is now the plugin's"
say "$(grep -c '# own' "$D/.ai/hooks/post-merge")" "1" "the adapted post-merge is untouched"
say "$(grep -c 'post-merge differs from this' <<<"$OUT")" "1" "…and doctor names it on the same run"
say "$(grep -c 'commit-msg is the flight-rules' <<<"$OUT")" "0" "doctor no longer reports the synced hook stale"
rm -rf "$D"
# Without the key: reported, not written.
D=$(mkrepo); stale "$D" commit-msg
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "unset: the hook exits 0"
say "$(grep -c 'updated git hooks' <<<"$OUT")" "0" "unset: nothing is synced"
say "$(grep -c 'commit-msg is the flight-rules 0.0.1 copy' <<<"$OUT")" "1" "…and doctor reports the stale hook instead"
rm -rf "$D"
# auto with no hooks installed at all: that is the owner's install step, not a sync.
D=$(mkrepo); git -C "$D" config --unset core.hooksPath; printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, no core.hooksPath: the hook exits 0"
say "$(grep -c 'updated git hooks\|could not update' <<<"$OUT")" "0" "…syncs nothing and reports no failure"
say "$(grep -c 'core.hooksPath is not set' <<<"$OUT")" "1" "…doctor says the hooks are not installed"
rm -rf "$D"
# A GLOBAL core.hooksPath only: `git config core.hooksPath` said "set", and the sync
# wrote the hooks into ~/.githooks (review, 2026-10-12). Local config is the gate.
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" config --unset core.hooksPath; mkdir -p "$D/fakehome/githooks"
printf '[core]\n\thooksPath = %s\n' "$D/fakehome/githooks" > "$D/fakehome/.gitconfig"
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, global hooksPath only: the hook exits 0"
say "$(grep -c 'updated git hooks\|could not update' <<<"$OUT")" "0" "…syncs nothing and reports no failure"
say "$(ls "$D/fakehome/githooks" | wc -l | tr -d ' ')" "0" "…and writes nothing into the global directory"
# Doctor reads git's EFFECTIVE config, as git does: the global directory is where git
# runs hooks from, and it lacks the flight-rules ones — the honest diagnosis.
say "$(grep -c 'missing from' <<<"$OUT")" "6" "…while doctor reports the global directory as missing every hook"
rm -rf "$D"
# Mid-merge: an unattended write to a tracked file is what makes --continue refuse.
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: hooks" --no-verify
git -C "$D" checkout -qb feature/c; echo c > "$D/f.txt"; git -C "$D" commit -qam "chore: c" --no-verify
git -C "$D" checkout -q trunk; echo t > "$D/f.txt"; git -C "$D" commit -qam "chore: t" --no-verify
git -C "$D" merge --no-verify feature/c >/dev/null 2>&1   # conflicts on f.txt, MERGE_HEAD stays
[ -n "$(git -C "$D" rev-parse -q --verify MERGE_HEAD)" ] || die "the merge did not stop on a conflict"
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, mid-merge: the hook exits 0"
say "$(grep -c 'updated git hooks' <<<"$OUT")" "0" "…and syncs nothing"
say "$(grep -c 'commit-msg is the flight-rules 0.0.1 copy' <<<"$OUT")" "1" "…while doctor still reports the stale hook"
rm -rf "$D"
# Mid-cherry-pick too, not only merge and rebase (release review, 2026-10-12).
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: hooks" --no-verify
git -C "$D" checkout -qb feature/p; echo p > "$D/f.txt"; git -C "$D" commit -qam "chore: p" --no-verify
git -C "$D" checkout -q trunk; echo t > "$D/f.txt"; git -C "$D" commit -qam "chore: t" --no-verify
git -C "$D" cherry-pick feature/p >/dev/null 2>&1
[ -n "$(git -C "$D" rev-parse -q --verify CHERRY_PICK_HEAD)" ] || die "the cherry-pick did not stop on a conflict"
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, mid-cherry-pick: the hook exits 0"
say "$(grep -c 'updated git hooks' <<<"$OUT")" "0" "…and syncs nothing"
say "$(grep -c 'commit-msg is the flight-rules 0.0.1 copy' <<<"$OUT")" "1" "…while doctor still reports the stale hook"
rm -rf "$D"
# The other three in-progress states, each alone (fix review, 2026-10-12): a revert
# stopped on a conflict, and the rebase directories git leaves — rebase-merge is the
# interactive stop REBASE_HEAD misses, rebase-apply the am/apply one.
for state in revert rebase-merge rebase-apply; do
  D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
  git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: hooks" --no-verify
  case "$state" in
    revert)
      echo r > "$D/f.txt"; git -C "$D" commit -qam "chore: r" --no-verify
      echo s > "$D/f.txt"; git -C "$D" commit -qam "chore: s" --no-verify
      git -C "$D" revert --no-edit HEAD~1 >/dev/null 2>&1
      [ -n "$(git -C "$D" rev-parse -q --verify REVERT_HEAD)" ] || die "the revert did not stop on a conflict" ;;
    *) mkdir -p "$(git -C "$D" rev-parse --absolute-git-dir)/$state" || die "could not make $state" ;;
  esac
  OUT=$(PRUN)
  say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, mid-$state: the hook exits 0"
  say "$(grep -c 'updated git hooks' <<<"$OUT")" "0" "…and syncs nothing"
  say "$(grep -c 'commit-msg is the flight-rules 0.0.1 copy' <<<"$OUT")" "1" "…while doctor still reports the stale hook"
  rm -rf "$D"
done
# A session-start.sh copied in by hand has no git/ beside it: silent on sync, still runs doctor.
L=$(cd "$(mktemp -d)" && pwd -P); mkdir -p "$L/hooks/agent"; cp "$HOOK" "$L/hooks/agent/"; cp "$H/../flight-rules-doctor.sh" "$L/hooks/"
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"; git -C "$D" config --unset merge.ff
OUT=$( (cd "$D" && HOME="$D/fakehome" bash "$L/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "hand-wired, auto: the hook exits 0"
say "$(grep -c 'updated git hooks\|could not update' <<<"$OUT")" "0" "…and says nothing about syncing"
say "$(grep -c 'flight-rules doctor' <<<"$OUT")" "1" "…while doctor still runs"
rm -rf "$D" "$L" "$T"

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
