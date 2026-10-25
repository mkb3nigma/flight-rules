#!/usr/bin/env bash
# Tests for agent/session-start.sh — the stale-worktree reminder injected into every
# session. Its output is advice the next session acts on, so a wrong name here is a
# worktree removed for nothing. wiring.test.sh only proves the hook RUNS; this proves
# what it says. Run: ./session-start.test.sh (no args, no network; throwaway repos).
set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$H/session-start.sh"
# The hook reads the session id from stdin (#94). A runner's stdin left open is a case
# of its own, below; everywhere else the runs see what Claude Code gives — a closed one.
exec </dev/null
# The hook's own shq, for the commands it prints: built with printf %q, the expected
# lines matched only while TMPDIR held nothing to quote (fourth review, G6).
eval "$(sed -n '/^shq() {/,/^}/p' "$HOOK")"
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
# A headless session (`claude -p`, observed) has no screen, and spending the day's
# flag on it hid that day's ❌ from every attended session after it — silently, so it
# could never show up as an incident. Claude Code 2.1.301 sets CLAUDE_CODE_SESSION_ATTENDED=0
# for `claude -p` (probe, 2026-10-17; undocumented). Exactly 0 only: unset is today's flag.
printf '{ "name": "flight-rules", "version": "1.0.2" }\n' > "$T/.claude-plugin/plugin.json"
HRUN() { { (cd "$D" && CLAUDE_CODE_SESSION_ATTENDED=0 HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>/dev/null); echo "rc=$?"; } | ctx; }
OUT=$(HRUN)
say "$(grep -c 'flight-rules doctor' <<<"$OUT")" "1" "headless: doctor still runs, for the headless assistant's context"
say "$(grep -c '^rc=0$' <<<"$OUT")" "1" "…and exits 0"
say "$(ls -a "$D/fakehome/.claude/hooks" | grep -c -- '-1.0.2$')" "0" "…without spending the day's flag"
say "$(HRUN | grep -c 'flight-rules doctor')" "1" "…so a second headless session runs it too"
say "$( (cd "$D" && env -u CLAUDE_CODE_SESSION_ATTENDED HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>/dev/null) | ctx | grep -c 'flight-rules doctor')" "1" "the first attended session after them still gets doctor"
say "$( (cd "$D" && CLAUDE_CODE_SESSION_ATTENDED=1 HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>/dev/null) | ctx | grep -c 'flight-rules doctor')" "0" "…and spends the flag as before"
say "$(ls -a "$D/fakehome/.claude/hooks" | grep -c -- '-1.0.2$')" "1" "…the flag file now there (so the check above can see one)"
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
printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
OUT=$(ctx <<<"$J")
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "the hook exits 0"
say "$(grep -c 'HOOK_SYNC=auto updated git hooks' <<<"$OUT")" "1" "says it updated hooks"
say "$(usr <<<"$J" | grep -c 'synced commit-msg')" "1" "…on the user's screen too, since the diff is theirs to commit"
say "$(grep -c 'synced commit-msg (flight-rules 9.9.9)' <<<"$OUT")" "1" "…names the hook and the release"
say "$(cmp -s "$D/.ai/hooks/commit-msg" "$T/hooks/git/commit-msg" && echo same)" "same" "the stale commit-msg is now the plugin's"
say "$(grep -c '# own' "$D/.ai/hooks/post-merge")" "1" "the adapted post-merge is untouched"
# Quoted, as doctor accepts it: doctor said ✅ auto and the hook only reported (0.27.0
# release review).
T2=$(mkplugin); D2=$(mkrepo); stale "$D2" commit-msg
printf "HOOK_SYNC='auto'\nPROTECTED_BRANCHES=^main\$\n" >> "$D2/.ai/flight-rules.conf"
J=$( (cd "$D2" && HOME="$D2/fakehome" bash "$T2/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
say "$(ctx <<<"$J" | grep -c 'HOOK_SYNC=auto updated git hooks')" "1" "HOOK_SYNC='auto', quoted, syncs as doctor reads it"
rm -rf "$D2" "$T2"
say "$(grep -c 'git hooks have uncommitted changes' <<<"$OUT")" "0" "…and the sync's own notice is not repeated as uncommitted changes"
say "$(grep -c 'post-merge differs from this' <<<"$OUT")" "1" "…and doctor names it on the same run"
say "$(grep -c 'commit-msg is the flight-rules' <<<"$OUT")" "0" "doctor no longer reports the synced hook stale"
rm -rf "$D"
# A headless session syncs (the clone is protected at once) but its notice reaches no
# screen, and the next attended session found the hooks current and said nothing of the
# uncommitted diff (final release /dg, 2026-10-17). It now says so, on screen.
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: hooks" --no-verify
OUT=$( { (cd "$D" && CLAUDE_CODE_SESSION_ATTENDED=0 HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?"; } | ctx)
say "$(grep -c 'synced commit-msg' <<<"$OUT")" "1" "headless, auto: the stale hook is synced"
say "$(grep -c 'git hooks have uncommitted changes' <<<"$OUT")" "0" "…and headless is not told twice"
J=$( (cd "$D" && env -u CLAUDE_CODE_SESSION_ATTENDED HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
say "$(ctx <<<"$J" | grep -c 'rc=0')" "1" "the attended session after it exits 0"
say "$(ctx <<<"$J" | grep -c 'updated git hooks')" "0" "…finds nothing left to sync"
say "$(usr <<<"$J" | grep -c 'git hooks have uncommitted changes')" "1" "…and says on screen the hooks have uncommitted changes"
say "$(usr <<<"$J" | grep -c 'M .ai/hooks/commit-msg')" "1" "…naming the file"
git -C "$D" add .ai/hooks && git -C "$D" commit -qm "chore: synced" --no-verify
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
say "$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1) | usr | grep -c 'git hooks have uncommitted changes')" "0" "…and once committed, says nothing"
rm -rf "$D"
# Without the key: reported, not written.
D=$(mkrepo); stale "$D" commit-msg
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "unset: the hook exits 0"
say "$(grep -c 'updated git hooks' <<<"$OUT")" "0" "unset: nothing is synced"
say "$(grep -c 'commit-msg is the flight-rules 0.0.1 copy' <<<"$OUT")" "1" "…and doctor reports the stale hook instead"
rm -rf "$D"
# auto with no hooks installed at all: that is the owner's install step, not a sync.
D=$(mkrepo); git -C "$D" config --unset core.hooksPath; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, no core.hooksPath: the hook exits 0"
say "$(grep -c 'updated git hooks\|could not update' <<<"$OUT")" "0" "…syncs nothing and reports no failure"
say "$(grep -c 'core.hooksPath is not set' <<<"$OUT")" "1" "…doctor says the hooks are not installed"
rm -rf "$D"
# A GLOBAL core.hooksPath only: `git config core.hooksPath` said "set", and the sync
# wrote the hooks into ~/.githooks (review, 2026-10-12). Local config is the gate.
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
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
# A session in a linked worktree, with the usual install: an absolute core.hooksPath into
# the main checkout, shared by every worktree. Not synced from here, and said as such
# with the command for the main checkout — it read "outside this repository; sync it by
# hand", and a downstream project's worktree sessions never synced (#87, 2026-10-18).
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: auto" --no-verify
git -C "$D" worktree add -q "$D/.ai/worktrees/wt" -b fix/wt || die "could not add the worktree"
git -C "$D" config core.hooksPath "$D/.ai/hooks"
OUT=$( { (cd "$D/.ai/worktrees/wt" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?"; } | ctx)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, in a worktree, hooks in the main checkout: the hook exits 0"
say "$(grep -c 'could not update the git hooks' <<<"$OUT")" "1" "…says it did not sync"
say "$(grep -cF "is in the main checkout, $D," <<<"$OUT")" "1" "…because the hooks are the main checkout's"
say "$(grep -c 'outside this repository' <<<"$OUT")" "0" "…not because they are outside the repository"
say "$(grep -E '^[[:space:]]+bash ' <<<"$OUT" | grep -cF "bash $(shq "$T/hooks/git/install.sh") --from $(shq "$T/hooks/git") --stale-only --this-checkout")" "1" "…and gives the command for this worktree's copy, its paths shell-quoted"
say "$(cmp -s "$D/.ai/hooks/commit-msg" "$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/commit-msg" && echo stale)" "stale" "…leaving the main checkout's copy as it was"
rm -rf "$D"
# …and with every copy there current, nothing to say: the warning came every day
# regardless (#93, 2026-10-21).
D=$(mkrepo); cp "$H/../git/install.sh" "$D/.ai/hooks/"; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: auto" --no-verify
git -C "$D" worktree add -q "$D/.ai/worktrees/wt" -b fix/wt || die "could not add the worktree"
git -C "$D" config core.hooksPath "$D/.ai/hooks"
WT() { (cd "$D/.ai/worktrees/wt" && rm -f "$D"/fakehome/.claude/hooks/.worktree-check-* && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); }
J=$(WT)
say "$(grep -c 'could not update the git hooks\|main checkout' <<<"$J")" "0" "auto, in a worktree, current hooks in the main checkout: says nothing about the sync"
# The silence is a decision, not a path never reached (session-start always exits 0, so
# its exit status could not tell — #93 batch review, B4): the same fixture with one
# stale copy gets the main-checkout command on screen.
stale "$D" commit-msg; git -C "$D" commit -qam "chore: stale" --no-verify
say "$(WT | usr | grep -c 'is in the main checkout')" "1" "…while one stale copy there, same fixture, gets the main-checkout command on screen"
# A worktree session asked `git status` about a path in the main checkout, which git
# refuses (exit 128); 2>/dev/null made that "no uncommitted changes" (#93 batch review,
# B8). It now asks from the directory that holds the hooks.
cp "$H/../git/commit-msg" "$D/.ai/hooks/commit-msg"; git -C "$D" commit -qam "chore: current" --no-verify
echo '# flight-rules: adapted' >> "$D/.ai/hooks/post-merge"
J=$(WT)
say "$(usr <<<"$J" | grep -c 'git hooks have uncommitted changes')" "1" "…an uncommitted change to a hook in the main checkout: said on screen from the worktree"
say "$(usr <<<"$J" | grep -c 'M .ai/hooks/post-merge')" "1" "…naming the file"
say "$(usr <<<"$J" | grep -cF "in $D")" "1" "…and the checkout it is in"
# A status git cannot answer is said, with git's reason, not read as clean (second
# review, C3): the main checkout's index corrupted, asked from the worktree.
git -C "$D" checkout -q -- .ai/hooks/post-merge; cp "$D/.git/index" "$D/index.bak"; printf 'x' > "$D/.git/index"
J=$(WT)
mv "$D/index.bak" "$D/.git/index"
say "$(usr <<<"$J" | grep -c "could not fully check the git hooks in $D for uncommitted changes")" "1" "…a status that fails: said on screen as not checked, naming the checkout"
say "$(usr <<<"$J" | grep -c 'fatal:')" "1" "…with git's reason"
say "$(usr <<<"$J" | grep -c 'git hooks have uncommitted changes')" "0" "…and not as uncommitted changes"
rm -rf "$D"
# No install.sh in the main checkout at all — nothing needs it, and doctor does not
# name it — was a "could not update" every day from every worktree (second review, C1).
D=$(mkrepo); rm -f "$D/.ai/hooks/install.sh"; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: auto" --no-verify
git -C "$D" worktree add -q "$D/.ai/worktrees/wt" -b fix/wt || die "could not add the worktree"
git -C "$D" config core.hooksPath "$D/.ai/hooks"
say "$(WT | grep -c 'could not update the git hooks\|main checkout\|install.sh: missing')" "0" "auto, in a worktree, no install.sh in the main checkout, hooks current: says nothing about the sync"
stale "$D" commit-msg; git -C "$D" commit -qam "chore: stale" --no-verify
J=$(WT)
say "$(usr <<<"$J" | grep -c 'is in the main checkout')" "1" "…while a stale hook there, same fixture, still gets the main-checkout command"
say "$(usr <<<"$J" | grep -c 'install.sh: missing')" "0" "…without naming install.sh as missing"
rm -rf "$D"
# A status that succeeds but warns — an unreadable directory among the hooks — is a
# check that did not see everything: said as such, with the warning. Read with stdout it
# was shown as "uncommitted changes" (second review, C2); dropped, it was silence the
# suite pinned (third review, E1). Root reads a mode-000 directory, so git never warns.
D=$(mkrepo); cp "$H/../git/install.sh" "$D/.ai/hooks/"; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: auto" --no-verify
mkdir -p "$D/.ai/hooks/sub"; : > "$D/.ai/hooks/sub/x"; chmod 000 "$D/.ai/hooks/sub"
if [ -r "$D/.ai/hooks/sub" ]; then
  chmod 755 "$D/.ai/hooks/sub"
  echo "  ⏭️  a status that warns: skipped — running as root, a mode-000 directory is readable"
else
  J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?" )
  chmod 755 "$D/.ai/hooks/sub"
  say "$(grep -c '^rc=0$' <<<"$J")" "1" "a status that warns but succeeds: session-start exits 0"
  say "$(usr <<<"$J" | grep -c 'could not fully check the git hooks for uncommitted changes')" "1" "…and says the hooks could not be fully checked"
  say "$(usr <<<"$J" | grep -c 'warning:')" "1" "…with git's warning"
  say "$(usr <<<"$J" | grep -c 'git hooks have uncommitted changes')" "0" "…not as uncommitted changes"
fi
rm -rf "$D/.ai/hooks/sub"; echo '# flight-rules: adapted' >> "$D/.ai/hooks/post-merge"
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
say "$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1) | usr | grep -c 'git hooks have uncommitted changes')" "1" "…while a real uncommitted change, same fixture, is still said"
# status.branch=true adds a `## trunk` line to --short: taken for git saying something,
# it was a false "could not fully check" every session (fix review, F2).
git -C "$D" config status.branch true
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?" )
say "$(grep -c '^rc=0$' <<<"$J")" "1" "status.branch=true: session-start exits 0"
say "$(usr <<<"$J" | grep -c 'git hooks have uncommitted changes')" "1" "…still says the uncommitted change"
say "$(usr <<<"$J" | grep -c 'could not fully check')" "0" "…and not that the hooks could not be checked"
# status.showUntrackedFiles=no hid an untracked file there — a hook the sync copied in
# (group A fix review, F12).
git -C "$D" config status.branch false; git -C "$D" checkout -q -- .ai/hooks/post-merge
git -C "$D" config status.showUntrackedFiles no; : > "$D/.ai/hooks/pre-push"
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?" )
say "$(grep -c '^rc=0$' <<<"$J")" "1" "status.showUntrackedFiles=no: session-start exits 0"
say "$(usr <<<"$J" | grep -c 'git hooks have uncommitted changes')" "1" "…still says the hooks directory has changes"
say "$(usr <<<"$J" | grep -c '?? .ai/hooks/pre-push')" "1" "…naming the untracked file"
rm -rf "$D"
# On a protected branch nothing is written: the diff could not be committed there, and
# `git restore` was refused as discarding work, so it blocked the merge that would land
# it (AppliHawk, 2026-10-21, #99). Compared only; behind is said, with the command for a
# branch; current is silent. The fixture's trunk is protected (PROTECTED_BRANCHES=^trunk$).
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: stale" --no-verify
BEFORE=$(cksum < "$D/.ai/hooks/commit-msg")
J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
say "$(grep -c '^rc=0$' <<<"$J")" "1" "auto on a protected branch, a stale hook: exits 0"
say "$(usr <<<"$J" | grep -c 'did not update the git hooks: this checkout is on "trunk", a protected branch')" "1" "…says on screen it did not update them, and why"
say "$(usr <<<"$J" | grep -c 'commit-msg: the flight-rules 0.0.1 copy — stale')" "1" "…naming the stale hook"
say "$(usr <<<"$J" | grep -c -- '--stale-only --this-checkout$')" "1" "…with the command for a worktree's branch"
say "$(cksum < "$D/.ai/hooks/commit-msg")" "$BEFORE" "…writing nothing"
say "$(git -C "$D" status --porcelain -- .ai/hooks | grep -c .)" "0" "…so the hooks have no uncommitted change"
cp "$T/hooks/git/commit-msg" "$D/.ai/hooks/commit-msg"; git -C "$D" commit -qam "chore: current" --no-verify
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
say "$(grep -c '^rc=0$' <<<"$J")" "1" "…every hook current: exits 0"
say "$(grep -c 'HOOK_SYNC' <<<"$J")" "0" "…and says nothing about the sync"
rm -rf "$D"
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=off\n' >> "$D/.ai/flight-rules.conf"
J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
say "$(ctx <<<"$J" | grep -c 'HOOK_SYNC=auto updated git hooks')" "1" "PROTECTED_BRANCHES=off: the branch policy is off, and the sync writes"
rm -rf "$D"
# The default set is pre-commit-check.sh's; a copy that drifts protects a different set.
say "$(sed -n 's/^PROT="\${PROT:-\(.*\)}"$/\1/p' "$H/session-start.sh")" \
    "$(sed -n "s/^DEFAULT_PROTECTED='\(.*\)'$/\1/p" "$H/pre-commit-check.sh")" "the protected-branch default matches pre-commit-check.sh's"
say "$(sed -n '/^read_conf() {/,/^}/p' "$H/session-start.sh")" \
    "$(sed -n '/^read_conf() {/,/^}/p' "$H/pre-commit-check.sh")" "read_conf is pre-commit-check.sh's, verbatim"
# Protected as the guard decides it, crossed through both hooks: a single-quoted value,
# a branch in another case, the environment over the conf. The sync's own parse, grep
# and case wrote on each while the guard refused the commit (fix review, F1/D7).
# <description> % <conf line> % <branch> % <env>
# Counted: a command in the loop that reads stdin eats the cases after it, and the
# suite still says "passed" — the hook's stdin read did, 2026-10-24, three of four.
NCASE=0
while IFS='%' read -r desc line br envv; do
  NCASE=$((NCASE+1))
  D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\n%s\n' "$line" >> "$D/.ai/flight-rules.conf"
  git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: stale" --no-verify
  [ "$br" = trunk ] || git -C "$D" checkout -qb "$br"
  BEFORE=$(cksum < "$D/.ai/hooks/commit-msg")
  J=$( (cd "$D" && env $envv HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
  say "$(grep -c '^rc=0$' <<<"$J")" "1" "$desc: session-start exits 0"
  say "$(usr <<<"$J" | grep -c "this checkout is on \"$br\", a protected branch")" "1" "…the sync says the branch is protected"
  say "$(cksum < "$D/.ai/hooks/commit-msg")" "$BEFORE" "…and writes nothing"
  G=$(cd "$D" && env $envv CLAUDE_PROJECT_DIR="$D" bash "$H/pre-commit-check.sh" <<<'{"tool_input":{"command":"git commit -m x"}}' 2>/dev/null)
  say "$(grep -c '"permissionDecision": *"deny"' <<<"$G")" "1" "…as the guard refuses a commit there"
  rm -rf "$D"
done <<'CASES'
a single-quoted pattern%PROTECTED_BRANCHES='^trunk$'%trunk%
a double-quoted pattern with a comment%PROTECTED_BRANCHES="^trunk$"   # the trunk%trunk%
a branch in another case than the pattern%PROTECTED_BRANCHES=^(main|qa)$%QA%
the environment over the conf%PROTECTED_BRANCHES=^main$%trunk%FLIGHT_RULES_PROTECTED_BRANCHES=^trunk$
CASES
say "$NCASE" "4" "…all four protected-branch cases ran"
# A pattern bash cannot compile protects nothing to =~; the sync takes the branch as
# protected and says the pattern is broken, rather than writing (fix review, F5).
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^(trunk\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: stale" --no-verify
BEFORE=$(cksum < "$D/.ai/hooks/commit-msg")
J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
say "$(grep -c '^rc=0$' <<<"$J")" "1" "a pattern that does not compile: session-start exits 0"
say "$(usr <<<"$J" | grep -c 'PROTECTED_BRANCHES (^(trunk) is not a pattern bash can read, so "trunk" is taken as protected')" "1" "…says the pattern is broken and the branch taken as protected"
say "$(cksum < "$D/.ai/hooks/commit-msg")" "$BEFORE" "…and writes nothing"
# The fix is the owner's, as the guard says: "fix the pattern" told the assistant to edit
# the setting the guard tells it not to (group A fix review, F10).
say "$(usr <<<"$J" | grep -c "It is the project owner's to fix, in .ai/flight-rules.conf (or FLIGHT_RULES_PROTECTED_BRANCHES); an assistant does not edit it")" "1" "…leaves the fix to the project owner, in words that read right to them on screen"
say "$(usr <<<"$J" | grep -c 'Fix the pattern')" "0" "…not to the assistant"
rm -rf "$D"
# Behind is stale or missing; what the command leaves alone is listed apart, not as
# behind beside a command that will not touch it (fix review, F3).
D=$(mkrepo); stale "$D" commit-msg; echo "# own" >> "$D/.ai/hooks/post-merge"; printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: stale" --no-verify
J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
SEC=$(usr <<<"$J" | sed -n '/Behind or missing:$/,/^To update them/p')
say "$(grep -c 'commit-msg: the flight-rules 0.0.1 copy — stale' <<<"$SEC")" "1" "protected, stale and differing: the stale hook is behind"
say "$(grep -c 'post-merge' <<<"$SEC")" "0" "…the differing one is not listed as behind"
say "$(usr <<<"$J" | sed -n '/^Left alone/,$p' | grep -c 'post-merge: differs')" "1" "…but under what the command leaves alone"
rm -rf "$D"
# A hook the sync could not read, nothing else to say: said, not silence that reads as
# "current" (fix review, F4; Codex P2). Root reads a mode-000 file: skipped there.
D=$(mkrepo); echo "# own" >> "$D/.ai/hooks/post-merge"; printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: own" --no-verify
chmod 000 "$D/.ai/hooks/post-merge"
if [ -r "$D/.ai/hooks/post-merge" ]; then
  echo "  ⏭️  an unreadable hook: skipped — running as root, a mode-000 file is readable"
else
  for br in trunk feature/x; do
    [ "$br" = trunk ] || git -C "$D" checkout -qb "$br"
    rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
    J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
    say "$(grep -c '^rc=0$' <<<"$J")" "1" "an unreadable hook, on $br: session-start exits 0"
    say "$(usr <<<"$J" | grep -c 'HOOK_SYNC=auto could not check every git hook')" "1" "…says a hook could not be checked"
    say "$(usr <<<"$J" | grep -c 'post-merge: unreadable — could not check it')" "1" "…naming it"
  done
  # …and the uncommitted-changes check still runs beside it: an elif in the same chain,
  # the notice hid it (group A fix review, F2).
  : > "$D/.ai/hooks/notes.txt"
  rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
  J=$( (cd "$D" && HOME="$D/fakehome" bash "$T/hooks/agent/session-start.sh" 2>&1); echo "rc=$?")
  say "$(grep -c '^rc=0$' <<<"$J")" "1" "an unreadable hook and an uncommitted file: session-start exits 0"
  say "$(usr <<<"$J" | grep -c 'HOOK_SYNC=auto could not check every git hook')" "1" "…says a hook could not be checked"
  say "$(usr <<<"$J" | grep -c 'git hooks have uncommitted changes')" "1" "…and the uncommitted change too"
fi
chmod 644 "$D/.ai/hooks/post-merge"; rm -rf "$D"
# Mid-merge: an unattended write to a tracked file is what makes --continue refuse.
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: hooks" --no-verify
git -C "$D" checkout -qb feature/c; echo c > "$D/f.txt"; git -C "$D" commit -qam "chore: c" --no-verify
git -C "$D" checkout -q trunk; echo t > "$D/f.txt"; git -C "$D" commit -qam "chore: t" --no-verify
git -C "$D" merge --no-verify feature/c >/dev/null 2>&1   # conflicts on f.txt, MERGE_HEAD stays
[ -n "$(git -C "$D" rev-parse -q --verify MERGE_HEAD)" ] || die "the merge did not stop on a conflict"
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, mid-merge: the hook exits 0"
say "$(grep -c 'skipped the git hooks: a merge is in progress' <<<"$OUT")" "1" "…says the sync was skipped and why"
say "$(grep -c 'A leftover never finishes: `git status`' <<<"$OUT")" "1" "…and how to clear one left behind"
# The command is pasted, so its paths are quoted for the shell, not wrapped in "…": a
# path holding `$(…)` or `"` ran or broke when pasted (0.26.0 release review, P2).
say "$(grep -cxF "  bash $(shq "$T/hooks/git/install.sh") --from $(shq "$T/hooks/git") --stale-only" <<<"$OUT")" "1" "…with the command to run once it is finished, its paths shell-quoted"
say "$(grep -c 'updated git hooks' <<<"$OUT")" "0" "…and syncs nothing"
say "$(grep -c 'commit-msg is the flight-rules 0.0.1 copy' <<<"$OUT")" "1" "…while doctor still reports the stale hook"
# A plugin under a path with a multibyte character and a space (a home directory named
# so): printf %q under macOS bash 3.2 split the ß and left a raw byte, so the pasted
# command named a path that does not exist (fix review, 2026-10-24). shq quotes it whole.
U=$(cd "$(mktemp -d)" && pwd -P)/"Stra ße"; mkdir -p "$U" && cp -R "$T/." "$U/" || die "could not lay out the ß plugin"
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*   # the day's run was spent above
# A UTF-8 locale, as the install and doctor cases pin: under C, %q left the ß alone and
# the case passed against the bug (fourth review, G1).
U8=$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -1); U8=${U8:-en_US.UTF-8}
OUT=$( { (cd "$D" && LC_ALL=$U8 HOME="$D/fakehome" bash "$U/hooks/agent/session-start.sh" 2>&1); echo "rc=$?"; } | ctx)
CMD=$(grep -E '^  bash .*--stale-only$' <<<"$OUT" | head -1)
say "$(grep -cE '^  bash .*--stale-only$' <<<"$OUT")" "1" "a plugin path with ß and a space: the sync command is printed"
# jq turns a stray byte into U+FFFD, so the check is for that, not for valid UTF-8, which
# jq's output always is (fourth review, D6b).
say "$(grep -c "$(printf '\357\277\275')" <<<"$CMD")" "0" "…with no byte replaced on the way"
say "$(bash() { printf '%s|' "$@"; }; eval "$CMD")" "$U/hooks/git/install.sh|--from|$U/hooks/git|--stale-only|" "…and, pasted, hands bash the exact paths"
rm -rf "$D" "$(dirname "$U")"
# Mid-cherry-pick too, not only merge and rebase (release review, 2026-10-12).
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: hooks" --no-verify
git -C "$D" checkout -qb feature/p; echo p > "$D/f.txt"; git -C "$D" commit -qam "chore: p" --no-verify
git -C "$D" checkout -q trunk; echo t > "$D/f.txt"; git -C "$D" commit -qam "chore: t" --no-verify
git -C "$D" cherry-pick feature/p >/dev/null 2>&1
[ -n "$(git -C "$D" rev-parse -q --verify CHERRY_PICK_HEAD)" ] || die "the cherry-pick did not stop on a conflict"
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, mid-cherry-pick: the hook exits 0"
say "$(grep -c 'skipped the git hooks: a cherry-pick is in progress' <<<"$OUT")" "1" "…says the sync was skipped and why"
say "$(grep -c 'updated git hooks' <<<"$OUT")" "0" "…and syncs nothing"
say "$(grep -c 'commit-msg is the flight-rules 0.0.1 copy' <<<"$OUT")" "1" "…while doctor still reports the stale hook"
rm -rf "$D"
# The other three in-progress states, each alone (fix review, 2026-10-12): a revert
# stopped on a conflict, and the rebase directories git leaves — rebase-merge is the
# interactive stop REBASE_HEAD misses, rebase-apply the am/apply one.
for state in revert rebase-merge rebase-apply am sequencer bisect; do
  D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
  git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: hooks" --no-verify
  case "$state" in
    revert)
      echo r > "$D/f.txt"; git -C "$D" commit -qam "chore: r" --no-verify
      echo s > "$D/f.txt"; git -C "$D" commit -qam "chore: s" --no-verify
      git -C "$D" revert --no-edit HEAD~1 >/dev/null 2>&1
      [ -n "$(git -C "$D" rev-parse -q --verify REVERT_HEAD)" ] || die "the revert did not stop on a conflict" ;;
    # A stopped `git am` keeps rebase-apply/ with an `applying` marker; git status calls
    # it an am session, and "a rebase" sent the reader to `rebase --continue` (review,
    # 2026-10-17).
    am) mkdir -p "$(git -C "$D" rev-parse --absolute-git-dir)/rebase-apply" \
          && touch "$(git -C "$D" rev-parse --absolute-git-dir)/rebase-apply/applying" || die "could not fake am" ;;
    # A multi-commit cherry-pick stopped on a conflict that was then committed by hand:
    # CHERRY_PICK_HEAD is gone, sequencer/todo remains, git status says in progress, and
    # a later pick touching the synced hooks makes --continue refuse (review, 2026-10-17).
    sequencer)
      git -C "$D" checkout -qb feature/s; echo s1 > "$D/f.txt"; git -C "$D" add f.txt; git -C "$D" commit -qm "chore: s1" --no-verify
      echo s2 > "$D/g.txt"; git -C "$D" add g.txt; git -C "$D" commit -qm "chore: s2" --no-verify
      git -C "$D" checkout -qb feature/w trunk; echo t > "$D/f.txt"; git -C "$D" add f.txt; git -C "$D" commit -qm "chore: t" --no-verify
      git -C "$D" cherry-pick trunk..feature/s >/dev/null 2>&1
      echo resolved > "$D/f.txt"; git -C "$D" add f.txt; git -C "$D" commit -qm "chore: resolved" --no-verify
      [ -z "$(git -C "$D" rev-parse -q --verify CHERRY_PICK_HEAD)" ] \
        && [ -f "$(git -C "$D" rev-parse --absolute-git-dir)/sequencer/todo" ] || die "no sequencer-only state" ;;
    # A bisect: a synced hook on the commit under test made `bisect good` refuse to
    # check out (final release /dg, 2026-10-17).
    bisect) git -C "$D" bisect start >/dev/null 2>&1 \
      && [ -f "$(git -C "$D" rev-parse --absolute-git-dir)/BISECT_LOG" ] || die "no bisect started" ;;
    *) mkdir -p "$(git -C "$D" rev-parse --absolute-git-dir)/$state" || die "could not make $state" ;;
  esac
  OUT=$(PRUN)
  say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, mid-$state: the hook exits 0"
  case "$state" in am) op="git am session" ;; sequencer) op="cherry-pick or revert" ;; *) op="${state%%-*}" ;; esac
  say "$(grep -c "skipped the git hooks: a $op is in progress" <<<"$OUT")" "1" "…says the sync was skipped and why"
  say "$(grep -c 'updated git hooks' <<<"$OUT")" "0" "…and syncs nothing"
  say "$(grep -c 'commit-msg is the flight-rules 0.0.1 copy' <<<"$OUT")" "1" "…while doctor still reports the stale hook"
  rm -rf "$D"
done
# A REBASE_HEAD with no rebase directory is not a rebase: git leaves the file behind,
# and one from March 2026 kept AppliHawk's hooks at 0.22.0 under 0.24.1, unsynced and
# unsaid (2026-10-17). git status calls that state clean, and so does the sync.
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" rev-parse HEAD > "$(git -C "$D" rev-parse --absolute-git-dir)/REBASE_HEAD"
[ -n "$(git -C "$D" rev-parse -q --verify REBASE_HEAD)" ] || die "could not leave a REBASE_HEAD"
OUT=$(PRUN)
say "$(grep -c 'rc=0' <<<"$OUT")" "1" "auto, leftover REBASE_HEAD: the hook exits 0"
say "$(grep -c 'synced commit-msg' <<<"$OUT")" "1" "…and syncs the stale hook"
say "$(grep -c 'skipped the git hooks' <<<"$OUT")" "0" "…without calling it mid-rebase"
rm -rf "$D"
# Nor is a branch or tag named MERGE_HEAD, CHERRY_PICK_HEAD or REVERT_HEAD an operation
# in progress: rev-parse --verify resolved them and the sync skipped (AppliHawk review,
# 2026-10-17). The markers are files.
for ref in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
  git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: hooks" --no-verify
  git -C "$D" branch "$ref" >/dev/null 2>&1; git -C "$D" rev-parse -q --verify "$ref" >/dev/null || die "no branch $ref"
  OUT=$(PRUN)
  say "$(grep -c 'rc=0' <<<"$OUT")" "1" "a branch named $ref: the hook exits 0"
  say "$(grep -c 'synced commit-msg' <<<"$OUT")" "1" "…and syncs, not taking it for an operation in progress"
  rm -rf "$D"
done
# A session-start.sh copied in by hand has no git/ beside it: silent on sync, still runs doctor.
L=$(cd "$(mktemp -d)" && pwd -P); mkdir -p "$L/hooks/agent"; cp "$HOOK" "$L/hooks/agent/"; cp "$H/../flight-rules-doctor.sh" "$L/hooks/"
D=$(mkrepo); stale "$D" commit-msg; printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"; git -C "$D" config --unset merge.ff
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
# flight-rules' hooks at core.hooksPath = ~/…: read raw, the path was joined to the repo
# root, the gate was not found there, and an adopted project got no screen.
F=$(mkrepo); rm "$F/.ai/flight-rules.conf"; git -C "$F" config --unset merge.ff
mkdir -p "$F/fakehome/hk"; cp "$F"/.ai/hooks/pre-* "$F"/.ai/hooks/commit-msg "$F"/.ai/hooks/post-merge "$F"/.ai/hooks/reference-transaction "$F/fakehome/hk/"
git -C "$F" config core.hooksPath '~/hk'
J=$(raw "$F")
say "$(usr <<<"$J" | grep -c 'merge.ff')" "1" "flight-rules' hooks at ~/hk: adopted, the ❌ is on screen"
say "$(ctx <<<"$J" | grep -c 'does not exist')" "0" "…and the assistant is not told the path is missing"
rm -rf "$F"
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

echo "After /reload-plugins, the next prompt says the session's version changed (#94):"
# No hook event fires on a reload, and SessionStart does not fire again, so a project
# kept three stale hooks under 0.26.0 and nothing said a new session was needed
# (AppliHawk, 2026-10-21). SessionStart records the version under the session id on
# stdin; UserPromptSubmit runs the hook with --prompt, which compares and does nothing
# else (batch review, 2026-10-24: a prompt that ran the sync downgraded hooks from an
# older session, and re-ran everything from a subdirectory).
T=$(mkplugin); printf '{ "name": "flight-rules", "version": "1.0.0" }\n' > "$T/.claude-plugin/plugin.json"
D=$(mkrepo); printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: conf" --no-verify
SF="$D/fakehome/.claude/hooks/.session-version-"
# SS <session id> [dir] [plugin] [flag, default --plugin; "" for a hand-wired run]:
# SessionStart; UP: the same as a prompt. rc on the last line.
SS() { (cd "${2:-$D}" && env -u CLAUDE_CODE_SESSION_ATTENDED HOME="$D/fakehome" bash "${3:-$T}/hooks/agent/session-start.sh" ${4---plugin} 2>&1 <<<"{\"session_id\":\"$1\",\"hook_event_name\":\"SessionStart\"}"); echo "rc=$?"; }
UP() { (cd "${2:-$D}" && env -u CLAUDE_CODE_SESSION_ATTENDED HOME="$D/fakehome" bash "${3:-$T}/hooks/agent/session-start.sh" --prompt ${4---plugin} 2>&1 <<<"{\"session_id\":\"$1\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}"); echo "rc=$?"; }
body() { grep -v '^rc=' <<<"$1" | grep -c .; }
rc() { tail -1 <<<"$1"; }
J=$(SS s-a)
say "$(rc "$J")" "rc=0" "SessionStart with a session id exits 0"
say "$(cat "${SF}s-a" 2>/dev/null)" "1.0.0" "…and records the version it started on"
J=$(UP s-a)
say "$(rc "$J")" "rc=0" "a prompt in that session, same version: exits 0"
say "$(body "$J")" "0" "…saying nothing"
say "$(cat "${SF}s-a" 2>/dev/null)" "1.0.0" "…and leaving the record as it was"
# The update and reload: this session's hooks are now 1.0.1's; a git hook is behind.
printf '{ "name": "flight-rules", "version": "1.0.1" }\n' > "$T/.claude-plugin/plugin.json"; stale "$D" commit-msg
cp "$D/.ai/hooks/commit-msg" "$D/before-commit-msg"
J=$(UP s-a)
say "$(rc "$J")" "rc=0" "the first prompt after the reload exits 0"
say "$(grep -v '^rc=' <<<"$J" | jq -r '.hookSpecificOutput.hookEventName')" "UserPromptSubmit" "…answering as UserPromptSubmit"
say "$(usr <<<"$J" | grep -c 'flight-rules is now 1.0.1 in this session (it was 1.0.0)')" "1" "…says on screen the plugin changed under the session"
say "$(usr <<<"$J" | grep -c 'Start a new session to get both')" "1" "…and that a new session loads the rules and runs the checks"
say "$(ctx <<<"$J" | grep -c 'its rules are not')" "1" "…telling the assistant too"
say "$(ctx <<<"$J" | grep -c "Already on the user's screen with this prompt")" "1" "…which is told the user saw it"
say "$(cmp -s "$D/.ai/hooks/commit-msg" "$D/before-commit-msg" && echo same)" "same" "…and syncs nothing: the stale hook waits for the new session"
say "$(usr <<<"$J" | grep -c 'merge.ff\|synced')" "0" "…nor runs doctor or the sync"
say "$(cat "${SF}s-a" 2>/dev/null)" "1.0.1" "…and records the new version"
J=$(UP s-a)
say "$(rc "$J")" "rc=0" "the prompt after that exits 0"
say "$(body "$J")" "0" "…saying nothing: it was said once"
# Another session that already ran the new version must not hide the notice from this
# one (the per-project flag did).
printf '{ "name": "flight-rules", "version": "1.0.0" }\n' > "$T/.claude-plugin/plugin.json"; SS s-b >/dev/null
printf '{ "name": "flight-rules", "version": "1.0.1" }\n' > "$T/.claude-plugin/plugin.json"; SS s-c >/dev/null
J=$(UP s-b)
say "$(usr <<<"$J" | grep -c 'now 1.0.1 in this session (it was 1.0.0)')" "1" "a reloaded session is told even when another ran the new version first"
rm -rf "$D" "$T"
# An older session left open, on the older plugin, after a newer one synced the hooks:
# its prompts, on any day, change nothing and say nothing (it used to sync back down).
T0=$(mkplugin); printf '{ "name": "flight-rules", "version": "1.0.0" }\n' > "$T0/.claude-plugin/plugin.json"
T1=$(mkplugin); printf '{ "name": "flight-rules", "version": "1.0.1" }\n' > "$T1/.claude-plugin/plugin.json"
D=$(mkrepo); printf 'HOOK_SYNC=auto\nPROTECTED_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: conf" --no-verify
SF="$D/fakehome/.claude/hooks/.session-version-"
SS old "$D" "$T0" >/dev/null; SS new "$D" "$T1" >/dev/null
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*   # the next day: no daily flag
before=$(git -C "$D" status --porcelain; find "$D/.ai/hooks" -type f -exec cksum {} + | sort)
J=$(UP old "$D" "$T0")
say "$(rc "$J")" "rc=0" "an older session's prompt the next day exits 0"
say "$(body "$J")" "0" "…saying nothing: its own version has not changed"
say "$( [ "$(git -C "$D" status --porcelain; find "$D/.ai/hooks" -type f -exec cksum {} + | sort)" = "$before" ] && echo same)" "same" "…and writing nothing in the project"
say "$(ls -a "$D"/fakehome/.claude/hooks/ | grep -c '^\.worktree-check-')" "0" "…nor running the day's checks"
# From a subdirectory or a worktree: the session is the same, and so is the answer.
mkdir -p "$D/sub"; git -C "$D" worktree add -q "$D/.ai/worktrees/w" -b feat/w 2>/dev/null
J=$(UP new "$D/sub" "$T1")
say "$(rc "$J")" "rc=0" "a prompt from a subdirectory exits 0"
say "$(body "$J")" "0" "…saying nothing, running nothing"
J=$(UP new "$D/.ai/worktrees/w" "$T1")
say "$(rc "$J")" "rc=0" "a prompt from a worktree exits 0"
say "$(body "$J")" "0" "…saying nothing, running nothing"
say "$(ls -a "$D"/fakehome/.claude/hooks/ | grep -c '^\.worktree-check-')" "0" "…neither one spending a day's flag"
# A session with no record (it started before versions were recorded): never told.
J=$(UP never-started "$D" "$T1")
say "$(rc "$J")" "rc=0" "a session with no record: exits 0"
say "$(body "$J")" "0" "…saying nothing"
say "$(ls -a "$D"/fakehome/.claude/hooks/ | grep -c '^\.session-version-never-started')" "0" "…and recording nothing"
# An id with characters a session id does not have names no file.
J=$(SS 'a*b c' "$D" "$T1")
say "$(rc "$J")" "rc=0" "a session id with * and a space: SessionStart exits 0"
say "$(ls -a "$D/fakehome/.claude/hooks" | grep -c 'session-version-a')" "0" "…and no file is made from it"
say "$(usr <<<"$J" | grep -c 'merge.ff')" "0" "…the day's run having been spent above"
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
# stdin left open with nothing on it: the read gives up, and the run goes on (a test
# runner's socket held it until killed, 2026-10-24; Claude Code's timeout drops the output).
# With --plugin, the only run that reads stdin: without it this passed with the read
# untimed (0.27.0 release review).
t0=$(date +%s)
J=$( { sleep 20 & echo $! > "$D/sleeper"; } | (cd "$D" && env -u CLAUDE_CODE_SESSION_ATTENDED HOME="$D/fakehome" bash "$T1/hooks/agent/session-start.sh" --plugin 2>&1); echo "rc=$?")
kill "$(cat "$D/sleeper")" 2>/dev/null; t1=$(date +%s)
say "$(rc "$J")" "rc=0" "stdin left open: SessionStart exits 0"
say "$([ $((t1 - t0)) -lt 10 ] && echo bounded)" "bounded" "…within seconds, not when stdin closes (took $((t1 - t0))s)"
rm -rf "$D" "$T0"
# Headless: no record at SessionStart, and a prompt is skipped outright.
D=$(mkrepo); git -C "$D" config --unset merge.ff
J=$( (cd "$D" && CLAUDE_CODE_SESSION_ATTENDED=0 HOME="$D/fakehome" bash "$T1/hooks/agent/session-start.sh" --plugin 2>&1 <<<'{"session_id":"h1"}'); echo "rc=$?")
say "$(usr <<<"$J" | grep -c 'merge.ff')" "1" "headless SessionStart still runs"
say "$(ls -a "$D/fakehome/.claude/hooks" 2>/dev/null | grep -c 'session-version')" "0" "…recording no session version"
# Even with a record from another version (a session id seen attended before).
printf '0.0.1\n' > "$D/fakehome/.claude/hooks/.session-version-h1"
J=$( (cd "$D" && CLAUDE_CODE_SESSION_ATTENDED=0 HOME="$D/fakehome" bash "$T1/hooks/agent/session-start.sh" --prompt --plugin 2>&1 <<<'{"session_id":"h1"}'); echo "rc=$?")
say "$(rc "$J")" "rc=0" "headless, a prompt: exits 0"
say "$(body "$J")" "0" "…saying nothing, though the record is another version's"
say "$(cat "$D/fakehome/.claude/hooks/.session-version-h1")" "0.0.1" "…and leaving the record alone"
rm -rf "$D" "$T1"
# Two copies in one session — the plugin and a hand-wired copy that has a plugin.json
# (a vendored tree, or this repo's own wiring in a release worktree): only the plugin's
# records, so prompts through both never flip the notice (fix review: six in three).
T2=$(mkplugin); printf '{ "name": "flight-rules", "version": "1.0.0" }\n' > "$T2/.claude-plugin/plugin.json"
V=$(mkplugin); printf '{ "name": "flight-rules", "version": "1.0.1" }\n' > "$V/.claude-plugin/plugin.json"
D=$(mkrepo); SF="$D/fakehome/.claude/hooks/.session-version-"
SS two "$D" "$T2" >/dev/null; SS two "$D" "$V" "" >/dev/null
say "$(cat "${SF}two" 2>/dev/null)" "1.0.0" "two copies: SessionStart records the plugin's version only"
n=0; for c in "$T2" "$V" "$T2" "$V"; do
  [ "$c" = "$V" ] && J=$(UP two "$D" "$V" "") || J=$(UP two "$D" "$c")
  [ "$(rc "$J")" = rc=0 ] || n=$((n+100)); n=$((n + $(usr <<<"$J" | grep -c 'flight-rules is now')))
done
say "$n" "0" "…and four prompts through both copies: exit 0, no notice"
# The environment does not make a copy the plugin: only the flag hooks.json passes.
(cd "$D" && env -u CLAUDE_CODE_SESSION_ATTENDED CLAUDE_PLUGIN_ROOT="$V" HOME="$D/fakehome" bash "$V/hooks/agent/session-start.sh" <<<'{"session_id":"envonly"}' >/dev/null 2>&1)
say "$?" "0" "CLAUDE_PLUGIN_ROOT set, no --plugin: SessionStart exits 0"
say "$(ls -a "$D/fakehome/.claude/hooks" | grep -c 'session-version-envonly')" "0" "CLAUDE_PLUGIN_ROOT set, no --plugin: nothing recorded"
rm -rf "$D" "$T2" "$V"
# Hand-wired, with no plugin.json beside the hook: no version, so no record and no
# notice — the hook copied where ../../.claude-plugin does not exist.
L=$(cd "$(mktemp -d)" && pwd -P); mkdir -p "$L/x/hooks/agent"; cp "$HOOK" "$L/x/hooks/agent/"; cp "$H/../flight-rules-doctor.sh" "$L/x/hooks/"
[ ! -e "$L/x/.claude-plugin" ] || die "hand-wired copy has a plugin.json"
D=$(mkrepo); git -C "$D" config --unset merge.ff
J=$(SS hw "$D" "$L/x")
say "$(usr <<<"$J" | grep -c 'merge.ff')" "1" "hand-wired, SessionStart runs doctor"
say "$(ls -a "$D/fakehome/.claude/hooks" | grep -c 'session-version')" "0" "…and records no version, having none"
J=$(UP hw "$D" "$L/x")
say "$(rc "$J")" "rc=0" "hand-wired, a prompt: exits 0"
say "$(body "$J")" "0" "…saying nothing"
rm -rf "$D" "$L"

echo
echo "OPEN_BRANCH_LIMIT warns when that many branches are open, and never blocks (#108):"
# More than ten branches sat unmerged in this repo (2026-10-20 to 10-23) and the owner
# saw the backlog only once they depended on each other. Open: a worktree's branch with
# commits not in the integration branch. Waiting: one with a passing note on its tip.
# open <repo> <name>: a worktree on a new branch off trunk, with a commit made there —
# not branch(), whose `add -A` in the main checkout would commit the conf edits below.
open() {
  local w="$1/.ai/worktrees/${2//\//_}"
  git -C "$1" worktree add -q -b "$2" "$w" trunk 2>/dev/null || die "could not add a worktree for $2"
  echo "$2" > "$w/open.txt"; git -C "$w" add open.txt
  git -C "$w" commit -qm "chore: on $2" --no-verify >/dev/null || die "could not commit on $2"
}
OB() { (cd "$D" && HOME="$D/fakehome" bash "$HOOK" 2>/dev/null); echo "rc=$?"; }
D=$(mkrepo); open "$D" fix/a; open "$D" fix/b; printf 'OPEN_BRANCH_LIMIT=2\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" notes --ref=pre-merge-check add -m "passed: 2026-10-24T00:00:00Z branch:fix/a" fix/a || die "could not stamp fix/a"
J=$(OB)
say "$(ctx <<<"$J" | grep -c '^rc=0$')" "1" "at the limit: exits 0"
say "$(usr <<<"$J" | grep -c '2 branches are open and not yet merged into trunk (OPEN_BRANCH_LIMIT is 2, in .ai/flight-rules.conf)')" "1" "…warns on screen, with the count, the limit and where it is set"
say "$(usr <<<"$J" | grep -c '/feature-start asks before it opens another')" "1" "…saying /feature-start asks before opening more"
say "$(usr <<<"$J" | grep -c 'waiting to merge: fix/a$')" "1" "…naming the stamped one as waiting to merge"
say "$(usr <<<"$J" | grep -c 'Not yet passed: fix/b$')" "1" "…and the other as not yet passed"
say "$(ctx <<<"$J" | grep -c 'OPEN_BRANCH_LIMIT is 2')" "1" "…telling the assistant too"
say "$(ctx <<<"$J" | grep -c "Already on the user's screen at session start: the open-branch warning")" "1" "…which is told the user saw it"
# Set from the environment, it says so: raising the conf's value would change nothing.
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$( (cd "$D" && FLIGHT_RULES_OPEN_BRANCH_LIMIT=2 HOME="$D/fakehome" bash "$HOOK" 2>/dev/null); echo "rc=$?")
say "$(usr <<<"$J" | grep -c '(OPEN_BRANCH_LIMIT is 2, from FLIGHT_RULES_OPEN_BRANCH_LIMIT)')" "1" "…set by FLIGHT_RULES_OPEN_BRANCH_LIMIT, the warning names it, not the conf"
rm -rf "$D"
# Below the limit, nothing — paired with the exit status and with the same run's
# reminder, so a hook that died cannot pass it. A merged branch is not open.
D=$(mkrepo); branch "$D" fix/m merge; git -C "$D" worktree add -q "$D/.ai/worktrees/m" fix/m
open "$D" fix/a; printf 'OPEN_BRANCH_LIMIT=2\n' >> "$D/.ai/flight-rules.conf"
J=$(OB)
say "$(ctx <<<"$J" | grep -c '^rc=0$')" "1" "one open and one merged, limit 2: exits 0"
say "$(ctx <<<"$J" | grep -c 'Branch: fix/m')" "1" "…the run reports (the merged worktree's reminder)"
say "$(ctx <<<"$J" | grep -c 'branches are open')" "0" "…and gives no open-branch warning"
# The default is 5; the environment comes first; off stands it down.
open "$D" fix/b; open "$D" fix/c; open "$D" fix/d
sed -i.bak '/OPEN_BRANCH_LIMIT/d' "$D/.ai/flight-rules.conf"; rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$(OB)
say "$(ctx <<<"$J" | grep -c '^rc=0$')" "1" "four open, no setting: exits 0"
say "$(ctx <<<"$J" | grep -c 'Branch: fix/m')" "1" "…the run reports (the merged worktree's reminder)"
say "$(ctx <<<"$J" | grep -c 'branches are open')" "0" "…and gives no warning (default 5)"
open "$D" fix/e; rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
say "$(OB | usr | grep -c '5 branches are open and not yet merged into trunk (OPEN_BRANCH_LIMIT is 5, in .ai/flight-rules.conf)')" "1" "…five: the warning"
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$( (cd "$D" && FLIGHT_RULES_OPEN_BRANCH_LIMIT=9 HOME="$D/fakehome" bash "$HOOK" 2>/dev/null); echo "rc=$?")
say "$(ctx <<<"$J" | grep -c '^rc=0$')" "1" "…FLIGHT_RULES_OPEN_BRANCH_LIMIT=9: exits 0"
say "$(ctx <<<"$J" | grep -c 'Branch: fix/m')" "1" "…the run reports"
say "$(ctx <<<"$J" | grep -c 'branches are open')" "0" "…and the environment overrides the default"
printf 'OPEN_BRANCH_LIMIT=off\n' >> "$D/.ai/flight-rules.conf"; rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$(OB)
say "$(ctx <<<"$J" | grep -c '^rc=0$')" "1" "OPEN_BRANCH_LIMIT=off: exits 0"
say "$(ctx <<<"$J" | grep -c 'branches are open')" "0" "…and gives no warning"
sed -i.bak 's/OPEN_BRANCH_LIMIT=off/OPEN_BRANCH_LIMIT=lots/' "$D/.ai/flight-rules.conf"; rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
say "$(OB | usr | grep -c 'OPEN_BRANCH_LIMIT is 5,')" "1" "…a value that is not a number is taken as 5"
# Quoted, as doctor accepts it: doctor said ✅ 2 and the hook ran at 5 (batch review).
sed -i.bak "s/OPEN_BRANCH_LIMIT=lots/OPEN_BRANCH_LIMIT='3'/" "$D/.ai/flight-rules.conf"; rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
say "$(OB | usr | grep -c '5 branches are open and not yet merged into trunk (OPEN_BRANCH_LIMIT is 3,')" "1" "…a quoted '3' is read as 3, as doctor reads it"
# …and so is a quoted INTEGRATION_BRANCH: kept with its quotes, it named no branch, and
# the count was "not made" while doctor showed ✅ (0.27.0 release review).
printf "INTEGRATION_BRANCH='trunk'\n" >> "$D/.ai/flight-rules.conf"; rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
say "$(OB | usr | grep -c '5 branches are open and not yet merged into trunk (OPEN_BRANCH_LIMIT is 3,')" "1" "…a quoted INTEGRATION_BRANCH is read as doctor reads it"
# A protected branch is not open work: main ahead of trunk after a release is not.
printf 'PROTECTED_BRANCHES=^(trunk|rel)$\nOPEN_BRANCH_LIMIT=5\n' >> "$D/.ai/flight-rules.conf"; open "$D" rel
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$(OB)
say "$(usr <<<"$J" | grep -c '5 branches are open')" "1" "a protected branch is not counted: five open, not six"
say "$(usr <<<"$J" | grep -cE ' rel( |$)')" "0" "…and it is not named"
# A protected pattern that does not compile protects, as the sync takes it; doctor's ❌
# says so on the same run.
sed -i.bak '/^PROTECTED_BRANCHES=/d' "$D/.ai/flight-rules.conf"; printf 'PROTECTED_BRANCHES=^(trunk\n' >> "$D/.ai/flight-rules.conf"
rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$(OB)
say "$(ctx <<<"$J" | grep -c '^rc=0$')" "1" "PROTECTED_BRANCHES that does not compile: exits 0"
say "$(usr <<<"$J" | grep -c 'PROTECTED_BRANCHES')" "1" "…doctor's ❌ names it"
say "$(usr <<<"$J" | grep -c 'branches are open')" "0" "…and no branch is counted as open"
say "$(ctx <<<"$J" | grep -c 'OPEN_BRANCH_LIMIT: the protected pattern does not compile — open branches not counted')" "1" "…and the assistant is told the count was not made"
# Without the conf, the project does not use flight-rules: not told how to run branches.
# A main for the default INTEGRATION_BRANCH to find, so it is the conf that silences it.
git -C "$D" branch main trunk || die "could not make main"
rm "$D/.ai/flight-rules.conf"; rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$(OB)
say "$(ctx <<<"$J" | grep -c '^rc=0$')" "1" "no conf: exits 0"
say "$(ctx <<<"$J" | grep -c 'flight-rules.conf absent')" "1" "…the run reports (doctor's warning)"
say "$(ctx <<<"$J" | grep -c 'branches are open')" "0" "…and gives no open-branch warning"
rm -rf "$D"
# A clone with no local integration branch counts against origin's; with neither, the
# assistant is told the count was not made — never silence that reads as "under".
D=$(mkrepo); open "$D" fix/a; open "$D" fix/b; printf 'OPEN_BRANCH_LIMIT=2\n' >> "$D/.ai/flight-rules.conf"
git -C "$D" update-ref refs/remotes/origin/trunk trunk; git -C "$D" checkout -q -b elsewhere
git -C "$D" branch -D trunk >/dev/null || die "could not drop the local trunk"
J=$(OB)
say "$(ctx <<<"$J" | grep -c '^rc=0$')" "1" "only origin/trunk: exits 0"
say "$(usr <<<"$J" | grep -c '2 branches are open and not yet merged into origin/trunk')" "1" "…counts against origin/trunk"
git -C "$D" update-ref -d refs/remotes/origin/trunk; rm -f "$D"/fakehome/.claude/hooks/.worktree-check-*
J=$(OB)
say "$(ctx <<<"$J" | grep -c '^rc=0$')" "1" "no trunk, local or origin: exits 0"
say "$(ctx <<<"$J" | grep -c 'OPEN_BRANCH_LIMIT: no trunk here, local or origin/ — open branches not counted')" "1" "…the assistant is told the count was not made"
say "$(usr <<<"$J" | grep -c 'not counted')" "0" "…off the screen"
rm -rf "$D"

echo "/feature-start step 5 counts what session-start counts (0.27.0 release review):"
# The skill's snippet, run as written. With the pattern unset it used a bare `main`, or
# grepped an empty pattern that left out every branch; with `off` it grepped for "off".
FS_SKILL="$H/../../skills/feature-start/SKILL.md"
SNIP=$(awk '/^5\. \*\*Count the open branches/{s=1} s && /^   ```bash$/{b=1; next} b && /^   ```$/{exit} b{sub(/^   /, ""); print}' "$FS_SKILL")
[ -n "$SNIP" ] || die "no bash block in step 5 of $FS_SKILL"
fs_count() {   # fs_count <repo> <{PROTECTED_BRANCHES} as substituted>: the branches the snippet lists, sorted, space-separated
  local s="${SNIP//'{INTEGRATION_BRANCH}'/trunk}"; s="${s//'{PROTECTED_BRANCHES}'/$2}"
  (cd "$1" && unset FLIGHT_RULES_PROTECTED_BRANCHES && bash -c "$s" 2>&1) | sort | tr '\n' ' '
}
D=$(mkrepo); open "$D" fix/domain-model; open "$D" staging; open "$D" fix/turn-off-x
sed -i.bak '/^PROTECTED_BRANCHES=/d' "$D/.ai/flight-rules.conf"; printf 'OPEN_BRANCH_LIMIT=2\n' >> "$D/.ai/flight-rules.conf"
say "$(fs_count "$D" '')" "fix/domain-model fix/turn-off-x " "unset: the hooks' anchored default leaves out staging, and only staging"
J=$(OB)
say "$(usr <<<"$J" | grep -c '2 branches are open')" "1" "…the two session-start counts"
say "$(fs_count "$D" off)" "fix/domain-model fix/turn-off-x staging " "off: nothing is left out, a name holding \"off\" included"
rm -rf "$D"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
