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
command -v jq >/dev/null 2>&1 || { echo "  ❌ harness: jq is required to read the hook's JSON" >&2; exit 2; }

# The hook prints one JSON object: systemMessage for the person, additionalContext for
# the assistant. ctx reads the assistant's text out of it, usr the person's; an `rc=N`
# line a caller appends passes through. Output that is not exactly one JSON object —
# trailing text, two objects — is what Claude Code would not parse, and becomes a
# HARNESS line WITHOUT the text, so no presence assertion can match on it (pre-review,
# 2026-10-13: `jq -e .` accepted two concatenated objects).
one_object() { [ "$(jq -s 'length == 1 and (.[0] | type == "object")' <<<"$1" 2>/dev/null)" = true ]; }
decode() {
  local in body; in=$(cat); body=$(grep -v '^rc=' <<<"$in")
  if [ -n "$body" ]; then
    if one_object "$body"; then jq -r "$1 // empty" <<<"$body"
    else echo 'HARNESS: the hook printed something that is not one JSON object'; fi
  fi
  grep '^rc=' <<<"$in"; return 0
}
ctx() { decode '.hookSpecificOutput.additionalContext'; }
usr() { decode '.systemMessage'; }

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
  printf '%s' "$out" | ctx
}
# raw <dir> → the hook's stdout as it is, for the JSON assertions.
raw() { (cd "$1" && HOME="$1/fakehome" bash "$HOOK" 2>/dev/null); }

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
OTHER=$( (cd "$E" && HOME="$D/fakehome" bash "$HOOK" 2>/dev/null) ); OTHER_RC=$?; OTHER=$(ctx <<<"$OTHER")
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
PRUN() { (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>/dev/null) | ctx; }
say "$(PRUN | grep -c 'flight-rules doctor')" "1" "the first session of the day runs doctor"
# Paired with the exit status: "does not" is also what a hook that died prints.
SECOND=$( { (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>/dev/null); echo "rc=$?"; } | ctx)
say "$(grep -c 'flight-rules doctor' <<<"$SECOND")" "0" "…the second, same version, does not"
say "$(grep -c '^rc=0$' <<<"$SECOND")" "1" "…and exits 0 doing so"
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
PRUN() { { (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?"; } | ctx; }
T=$(mkplugin); D=$(mkrepo); stale "$D" commit-msg; echo "# own" >> "$D/.ai/hooks/post-merge"
printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
OUT=$(ctx <<<"$J")
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "the hook exits 0"
say "$(grep -c 'HOOK_SYNC=auto updated git hooks' <<<"$OUT")" "1" "says it updated hooks"
say "$(usr <<<"$J" | grep -c 'synced commit-msg')" "1" "…on the user's screen too, since the diff is theirs to commit"
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
OUT=$( { (cd "$D" && HOME="$D/fakehome" bash "$L/hooks/agent/session-start.sh" 2>&1); echo "rc=$?"; } | ctx)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "hand-wired, auto: the hook exits 0"
say "$(grep -c 'updated git hooks\|could not update' <<<"$OUT")" "0" "…and says nothing about syncing"
say "$(grep -c 'flight-rules doctor' <<<"$OUT")" "1" "…while doctor still runs"
rm -rf "$D" "$L" "$T"

echo "What the person must act on is shown to them, not only to the assistant:"
# Plain stdout reaches the assistant alone, so a fresh plugin user never saw doctor's
# install command (live 2.1.296 session, 2026-10-13). systemMessage is what the screen shows.
D=$(mkrepo); git -C "$D" config --unset merge.ff
J=$(raw "$D")
say "$(one_object "$J" && echo json)" "json" "the output is one JSON object"
say "$(usr <<<"$J" | grep -c 'flight-rules doctor')" "1" "doctor's finding is in the user's message"
say "$(usr <<<"$J" | grep -c 'merge.ff')" "1" "…with the problem line itself"
say "$(ctx <<<"$J" | grep -c 'merge.ff')" "1" "…and in the assistant's context"
say "$(ctx <<<"$J" | grep -c "Already on the user's screen at session start: doctor's ❌ lines")" "1" "…which says the user has already seen it"
rm -rf "$D"
# A ⚠️ alone stays off the screen: no conf is a choice in a main-only project, and a
# warning only the project can silence would repeat every day (review, 2026-10-13).
D=$(mkrepo); rm "$D/.ai/flight-rules.conf"
J=$(raw "$D")
say "$(ctx <<<"$J" | grep -c 'flight-rules.conf absent')" "1" "a ⚠️ warning reaches the assistant"
say "$(jq -r 'has("systemMessage")' <<<"$J")" "false" "…and nothing is put on the user's screen for it"
rm -rf "$D"
# Beside a ❌, the ⚠️ is still kept off the screen.
D=$(mkrepo); rm "$D/.ai/flight-rules.conf"; git -C "$D" config --unset merge.ff
J=$(raw "$D")
say "$(usr <<<"$J" | grep -c 'merge.ff')" "1" "with a ❌ as well: the ❌ is on screen"
say "$(usr <<<"$J" | grep -c 'flight-rules.conf absent')" "0" "…the ⚠️ is not"
say "$(ctx <<<"$J" | grep -c 'flight-rules.conf absent')" "1" "…and the assistant has both"
rm -rf "$D"
D=$(mkrepo); branch "$D" fix/merged merge
git -C "$D" worktree add -q "$D/.ai/worktrees/merged" fix/merged
J=$(raw "$D")
say "$(ctx <<<"$J" | grep -c 'Branch: fix/merged')" "1" "the worktree reminder is in the assistant's context"
say "$(jq -r 'has("systemMessage")' <<<"$J")" "false" "…and nothing is put on the user's screen for it"
rm -rf "$D"

echo "The screen is for projects that use flight-rules:"
# A plugin enabled for the whole account opens every repo; a daily ❌ there, or in a
# directory that is no repo, is the nag that gets it switched off (fix review, 2026-10-13).
N=$(cd "$(mktemp -d)" && pwd -P)
J=$( (cd "$N" && HOME="$N/fakehome" bash "$HOOK" 2>/dev/null) )
say "$(ctx <<<"$J" | grep -c 'not inside a git repository')" "1" "outside a repo: the assistant is told"
say "$(jq -r 'has("systemMessage")' <<<"$J")" "false" "…and nothing is put on screen"
rm -rf "$N"
F=$(cd "$(mktemp -d)" && pwd -P); git -C "$F" init -q || die "git init failed in $F"
J=$( (cd "$F" && HOME="$F/fakehome" bash "$HOOK" 2>/dev/null) )
say "$(usr <<<"$J" | grep -c 'core.hooksPath is not set')" "1" "a repo without flight-rules: the install hint is shown once"
rm -f "$F"/fakehome/.claude/hooks/.worktree-check-*    # the next day
J=$( (cd "$F" && HOME="$F/fakehome" bash "$HOOK" 2>/dev/null) )
say "$(ctx <<<"$J" | grep -c 'core.hooksPath is not set')" "1" "…the next day the assistant is still told"
say "$(jq -r 'has("systemMessage")' <<<"$J")" "false" "…and the screen is not"
rm -rf "$F"
D=$(mkrepo); git -C "$D" config --unset merge.ff
raw "$D" >/dev/null; rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
say "$(raw "$D" | usr | grep -c 'merge.ff')" "1" "a project using flight-rules: a ❌ is on screen again the next day"
# From a subdirectory too: adoption is judged at the repo root, not the cwd.
mkdir -p "$D/sub"; rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
say "$( (cd "$D/sub" && HOME="$D/fakehome" bash "$HOOK" 2>/dev/null) | usr | grep -c 'merge.ff')" "1" "…and from a subdirectory of it"
rm -rf "$D"
# Another tool's hooks (husky): any core.hooksPath counted as adoption, and the repo
# got eight ❌ a day plus a command that wrote the gates into .husky/ (fix review,
# 2026-10-13). The assistant is told; the screen never is.
for scope in local global; do
  F=$(cd "$(mktemp -d)" && pwd -P); git -C "$F" init -q || die "git init failed in $F"
  mkdir -p "$F/.husky" "$F/fakehome"; printf '#!/bin/sh\nnpx lint-staged\n' > "$F/.husky/pre-commit"
  if [ "$scope" = local ]; then git -C "$F" config core.hooksPath .husky
  else printf '[core]\n\thooksPath = %s\n' "$F/.husky" > "$F/fakehome/.gitconfig"; fi
  J=$( (cd "$F" && HOME="$F/fakehome" bash "$HOOK" 2>/dev/null) )
  say "$(ctx <<<"$J" | grep -c 'missing from')" "5" "husky as $scope core.hooksPath: the assistant is told"
  say "$(jq -r 'has("systemMessage")' <<<"$J")" "false" "…and nothing is put on screen"
  rm -f "$F"/fakehome/.claude/hooks/.worktree-check-*
  say "$( (cd "$F" && HOME="$F/fakehome" bash "$HOOK" 2>/dev/null) | jq -r 'has("systemMessage")')" "false" "…the next day either"
  rm -rf "$F"
done
# Committed flight-rules hooks beside another tool's GLOBAL hooksPath: counting
# .ai/hooks/ as adoption put a daily `cp` into that tool's directory on screen.
F=$(mkrepo); git -C "$F" config --unset core.hooksPath; rm "$F/.ai/flight-rules.conf"
mkdir -p "$F/fakehome/githooks"; printf '[core]\n\thooksPath = %s\n' "$F/fakehome/githooks" > "$F/fakehome/.gitconfig"
J=$( (cd "$F" && HOME="$F/fakehome" bash "$HOOK" 2>/dev/null) )
say "$(ctx <<<"$J" | grep -c 'missing from')" "6" "committed hooks + a foreign global hooksPath: the assistant is told"
say "$(jq -r 'has("systemMessage")' <<<"$J")" "false" "…and nothing is put on screen"
rm -rf "$F"
# The hint is once per repository, not per worktree.
F=$(cd "$(mktemp -d)" && pwd -P); git -C "$F" init -q -b trunk && git -C "$F" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m base || die "repo in $F"
git -C "$F" worktree add -q "$F/wt" -b other || die "worktree in $F"
say "$( (cd "$F" && HOME="$F/fakehome" bash "$HOOK" 2>/dev/null) | usr | grep -c 'core.hooksPath is not set')" "1" "the hint is shown in the main checkout"
say "$( (cd "$F/wt" && HOME="$F/fakehome" bash "$HOOK" 2>/dev/null) | jq -r 'has("systemMessage")')" "false" "…and not again in a worktree of it"
rm -rf "$F"

echo "The sync command reaches the screen only beside a ❌ about a hook copy:"
# The ⚠️ that also asks for it is not shown, and a command next to an unrelated ❌ read
# as an instruction with no reason (fix review, 2026-10-13).
D=$(mkrepo); git -C "$D" config --unset merge.ff; echo "# my own tweak" >> "$D/.ai/hooks/post-merge"
J=$(raw "$D")
say "$(usr <<<"$J" | grep -c 'merge.ff')" "1" "unrelated ❌ beside an adapted ⚠️: the ❌ is on screen"
say "$(usr <<<"$J" | grep -c 'to update:')" "0" "…the sync command is not"
say "$(ctx <<<"$J" | grep -c 'to update:')" "1" "…the assistant has it"
rm -rf "$D"
D=$(mkrepo); rm "$D/.ai/hooks/pre-commit"
say "$(raw "$D" | usr | grep -c 'to update: .*--stale-only')" "1" "a missing hook: the --stale-only sync command is on screen"
rm -rf "$D"
# The stale copy is the case this exists for (AppliHawk); the filter matches doctor's
# wording, so a rewording that drops it fails here (fix review, 2026-10-13).
D=$(mkrepo); stale "$D" commit-msg
J=$(raw "$D")
say "$(usr <<<"$J" | grep -c 'commit-msg is the flight-rules 0.0.1 copy')" "1" "a stale hook copy: the ❌ is on screen"
say "$(usr <<<"$J" | grep -c 'to update: .*--stale-only')" "1" "…with the sync command"
rm -rf "$D"

echo "Without jq or python3, plain text for the assistant, and no claim the user saw it:"
NJ=$(cd "$(mktemp -d)" && pwd -P); mkdir -p "$NJ/hooks/agent"; cp "$H/../flight-rules-doctor.sh" "$NJ/hooks/"
sed 's/command -v jq >/command -v no-such-jq >/; s/command -v python3 >/command -v no-such-py >/' "$HOOK" > "$NJ/hooks/agent/session-start.sh" || die "no-tools copy"
D=$(mkrepo); git -C "$D" config --unset merge.ff
OUT=$( { (cd "$D" && HOME="$D/fakehome" bash "$NJ/hooks/agent/session-start.sh" 2>/dev/null); echo "rc=$?"; } )
say "$(grep -c "merge.ff is 'unset'" <<<"$OUT")" "1" "the doctor line is in the plain text"
say "$(grep -cE "Already on the user's screen|user was shown" <<<"$OUT")" "0" "…without saying the user saw it"
say "$(grep -c '^rc=0$' <<<"$OUT")" "1" "…and the hook exits 0"
rm -rf "$D"
# The once-ever hint is not spent by output that never reached the screen.
F=$(cd "$(mktemp -d)" && pwd -P); git -C "$F" init -q || die "git init failed in $F"
FIRST=$( { (cd "$F" && HOME="$F/fakehome" bash "$NJ/hooks/agent/session-start.sh" 2>/dev/null); echo "rc=$?"; } )
say "$(grep -c 'core.hooksPath is not set' <<<"$FIRST")" "1" "the plain-text run carried the hint"
say "$(grep -c '^rc=0$' <<<"$FIRST")" "1" "…and exited 0"
rm -f "$F"/fakehome/.claude/hooks/.worktree-check-*
say "$( (cd "$F" && HOME="$F/fakehome" bash "$HOOK" 2>/dev/null) | usr | grep -c 'core.hooksPath is not set')" "1" "a hint given as plain text is shown on the next JSON run"
rm -rf "$F"
# A python3 that fails — the macOS stub without Command Line Tools — falls back too.
sed 's/command -v jq >/command -v no-such-jq >/; s/python3 -I -c /false /' "$HOOK" > "$NJ/hooks/agent/session-start.sh" || die "stub copy"
D=$(mkrepo); git -C "$D" config --unset merge.ff
OUT=$( { (cd "$D" && HOME="$D/fakehome" bash "$NJ/hooks/agent/session-start.sh" 2>/dev/null); echo "rc=$?"; } )
say "$(grep -c "merge.ff is 'unset'" <<<"$OUT")" "1" "a failing python3: the plain text still comes out"
say "$(grep -c '^rc=0$' <<<"$OUT")" "1" "…and the hook exits 0"
rm -rf "$D" "$NJ"

echo "Without jq, the python3 fallback does not run the project's own json.py:"
# python3 puts the working directory — the project — first on its import path, so a
# json.py there ran at session start (security review, 2026-10-13). Both SessionStart
# hooks, each with the jq branch disabled in a copy so the fallback is what runs.
NJ=$(cd "$(mktemp -d)" && pwd -P); mkdir -p "$NJ/hooks/agent" "$NJ/rules"
sed 's/command -v jq >/command -v no-such-jq >/' "$HOOK" > "$NJ/hooks/agent/session-start.sh" \
  && sed 's/command -v jq >/command -v no-such-jq >/' "$H/../session-start-rules.sh" > "$NJ/hooks/session-start-rules.sh" \
  && cp "$H/../flight-rules-doctor.sh" "$NJ/hooks/" && cp "$H/../../rules/engineering-principles.md" "$NJ/rules/" \
  || die "could not lay out the no-jq copy"
D=$(mkrepo); git -C "$D" config --unset merge.ff
printf 'open("%s/PWNED", "w").write("x")\nfrom json import *\n' "$D" > "$D/json.py"
J=$( (cd "$D" && HOME="$D/fakehome" bash "$NJ/hooks/agent/session-start.sh" 2>/dev/null) )
say "$(usr <<<"$J" | grep -c 'merge.ff')" "1" "session-start.sh: the python3 fallback still prints the JSON"
say "$([ -e "$D/PWNED" ] && echo ran || echo not)" "not" "…and the project's json.py did not run"
J=$( (cd "$D" && bash "$NJ/hooks/session-start-rules.sh" 2>/dev/null) )
say "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$J" 2>/dev/null | grep -c 'Engineering Principles')" "1" "session-start-rules.sh: the fallback still injects the rules"
say "$([ -e "$D/PWNED" ] && echo ran || echo not)" "not" "…and the project's json.py did not run"
rm -rf "$D" "$NJ"

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
