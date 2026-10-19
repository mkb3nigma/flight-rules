#!/usr/bin/env bash
# Tests for flight-rules-doctor.sh — each case is an install state that has silently failed
# for real. Run: ./flight-rules-doctor.test.sh (no args, no network; builds throwaway repos).
set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="$H/flight-rules-doctor.sh"
PASS=0; FAIL=0
say() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✅ $3"; else FAIL=$((FAIL+1)); echo "  ❌ $3 (got '$1', want '$2')"; fi; }

# A fixture that cannot be built is not a test failure, it is an aborted run — so it
# stops the suite rather than being counted. The builders below run inside command
# substitutions, where a FAIL increment would be discarded with the subshell; `$$` is
# the parent's pid even there, so the signal reaches the trap. Measured 2026-09-12:
# with every fixture repo broken this suite still scored 11 of 36.
MAINPID=$$
trap 'printf "\n%s\n" "ABORTED: a fixture could not be built — no result above is meaningful" >&2; exit 2' TERM
die() { printf '  ❌ harness: %s\n' "$1" >&2; kill -s TERM "$MAINPID"; exit 2; }

# A repo with the hooks copied in and installed the documented way.
mkrepo() {
  local d; d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main || die "git init failed in $d"
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  mkdir -p "$d/.ai/hooks"
  # A cp that fails leaves doctor reporting a missing hook, which several cases here
  # expect for other reasons — the 2026-09-11 shape where a suite silently tested the
  # wrong copy. So it is checked, not assumed.
  cp "$H/git/pre-merge-commit" "$H/git/commit-msg" "$H/git/pre-rebase" "$H/git/post-merge" \
     "$H/git/reference-transaction" "$H/git/pre-commit" "$d/.ai/hooks/" || die "could not copy the git hooks from $H/git"
  chmod +x "$d"/.ai/hooks/*
  git -C "$d" config core.hooksPath .ai/hooks
  git -C "$d" config merge.ff false
  printf 'PROTECTED_BRANCHES=^main$\n' > "$d/.ai/flight-rules.conf"
  # What every assertion assumes: a repo, and six hooks that are there to be broken.
  [ -d "$d/.git" ] || die "no .git in the fixture at $d"
  for _h in pre-merge-commit commit-msg pre-rebase post-merge reference-transaction pre-commit; do
    [ -x "$d/.ai/hooks/$_h" ] || die "$_h missing or not executable in the fixture"
  done
  printf '%s' "$d"
}
# run <dir> → prints "<exit> <output>"; HOME is redirected so the plugin check is deterministic.
run() { local d="$1" out rc; out=$(cd "$d" && HOME="$d/fakehome" bash "$DOCTOR" 2>&1); rc=$?; printf '%s\n%s' "$rc" "$out"; }
rc()  { run "$1" | head -1; }
has() { run "$1" | tail -n +2 | grep -qF -- "$2"; echo $?; }

echo "Healthy install:"
D=$(mkrepo)
say "$(rc "$D")" "0" "installed repo passes"
say "$(has "$D" "merge.ff=false")" "0" "reports merge.ff"
rm -rf "$D"

echo "Hooks missing or not executable — the silent failures:"
D=$(mkrepo); git -C "$D" config --unset core.hooksPath
say "$(rc "$D")" "1" "no core.hooksPath → problem"
say "$(has "$D" "core.hooksPath is not set")" "0" "…and says so"
rm -rf "$D"

echo "A fresh repo is given a command that installs, not a path inside the plugin:"
# The bare "hooks/git/install.sh" named nothing a fresh plugin user could run (2026-10-13).
# The printed command is run as printed, and doctor afterwards is the proof it works.
D=$(cd "$(mktemp -d)" && pwd -P); git -C "$D" init -q -b main || die "git init failed in $D"
OUT=$(run "$D")
# A clone of a project that committed its hooks: wired by the PLUGIN's install.sh
# without --from, which would replace hooks the project adapted (pre-review), and never
# by the repo's own install.sh, which a cloned repo can make anything (security review,
# 2026-10-13). The repo's copy here would print PLANTED if it were the one recommended.
C=$(mkrepo); git -C "$C" config --unset core.hooksPath; git -C "$C" config --unset merge.ff
printf '#!/bin/bash\necho PLANTED > "%s/PLANTED"\n' "$C" > "$C/.ai/hooks/install.sh"
echo "# my own tweak" >> "$C/.ai/hooks/post-merge"
CMD=$(run "$C" | sed -n 's/.*To wire them up: \(bash .*\)   (git config is per clone.*/\1/p')
say "$(printf '%s' "$CMD" | grep -c "$H/git/install.sh")" "1" "a clone with committed hooks is given the plugin's install.sh"
say "$(printf '%s' "$CMD" | grep -c -- '--from\|\.ai/hooks/install.sh')" "0" "…not --from, and not the repo's own copy"
[ -n "$CMD" ] && (cd "$C" && eval "$CMD" >/dev/null 2>&1); say "$?" "0" "…which runs as printed"
say "$([ -e "$C/PLANTED" ] && echo ran || echo not)" "not" "…without running the repo's install.sh"
say "$(run "$C" | grep -cE 'core.hooksPath is not set|merge.ff is')" "0" "…and afterwards doctor reports neither"
say "$(grep -c 'my own tweak' "$C/.ai/hooks/post-merge")" "1" "…with the project's adapted hook kept"
rm -rf "$C"
# A 0.22.0-shaped set has no pre-commit, and install.sh refuses it: the printed
# command copies the missing hook first, and then works (fix review, 2026-10-13).
C=$(mkrepo); git -C "$C" config --unset core.hooksPath; rm "$C/.ai/hooks/pre-commit"
CMD=$(run "$C" | sed -n 's/.*To wire them up: \(.*bash .*\)   (git config is per clone.*/\1/p')
say "$(printf '%s' "$CMD" | grep -c 'cp .*pre-commit .*\.ai/hooks/ && bash')" "1" "a committed set missing pre-commit: the copy comes first"
# From a subdirectory: the person runs it from wherever the session is (fix review).
mkdir -p "$C/sub"; [ -n "$CMD" ] && (cd "$C/sub" && eval "$CMD" >/dev/null 2>&1); say "$?" "0" "…and the command runs as printed, from a subdirectory"
say "$(git -C "$C" config --local core.hooksPath)" ".ai/hooks" "…and wires the hooks"
rm -rf "$C"

# From a plugin directory with a space in its path — what %q quoting is for.
P="$(cd "$(mktemp -d)" && pwd -P)/my plugin"; mkdir -p "$P/hooks" && cp "$DOCTOR" "$P/hooks/" && cp -R "$H/git" "$P/hooks/git" || die "could not lay out the spaced plugin"
OUT=$(cd "$D" && HOME="$D/fakehome" bash "$P/hooks/flight-rules-doctor.sh" 2>&1)
CMD=$(printf '%s\n' "$OUT" | sed -n 's/.*To install them into \.ai\/hooks\/: \(bash .*\)   (it also sets.*/\1/p')
say "$([ -n "$CMD" ] && echo printed)" "printed" "no core.hooksPath → the full install command is printed"
[ -n "$CMD" ] && (cd "$D" && eval "$CMD" >/dev/null 2>&1); say "$?" "0" "…it runs as printed, from a path with a space"
say "$(run "$D" | grep -cE 'core.hooksPath is not set|missing from|merge.ff is')" "0" "…and afterwards doctor reports no hook or merge.ff problem"
say "$(has "$D" "core.hooksPath=.ai/hooks")" "0" "…with the relative path installed"
rm -rf "$D" "$(dirname "$P")"

D=$(mkrepo); git -C "$D" config core.hooksPath .ai/gone
say "$(rc "$D")" "1" "hooksPath at a missing directory → problem"
say "$(has "$D" "git runs NO hooks")" "0" "…and says git runs nothing"
rm -rf "$D"

D=$(mkrepo); chmod -x "$D/.ai/hooks/commit-msg"
say "$(rc "$D")" "1" "commit-msg without +x → problem"
say "$(has "$D" "commit-msg is not executable")" "0" "…names the hook"
rm -rf "$D"

D=$(mkrepo); rm "$D/.ai/hooks/pre-rebase"
say "$(rc "$D")" "1" "pre-rebase missing → problem"
rm -rf "$D"

# Without this one, cherry-pick / revert / branch -f / update-ref and a CONFLICTED
# merge all reach a PR-only branch unguarded — and every other hook still reports
# healthy, which is the exact "looks installed" failure flight-rules-doctor.sh exists to catch.
D=$(mkrepo); rm "$D/.ai/hooks/reference-transaction"
say "$(rc "$D")" "1" "reference-transaction missing → problem"
say "$(has "$D" "reference-transaction missing")" "0" "…names the hook"
rm -rf "$D"

D=$(mkrepo); chmod -x "$D/.ai/hooks/reference-transaction"
say "$(rc "$D")" "1" "reference-transaction without +x → problem"
rm -rf "$D"

# The secret scan for commits (#71): without it, `git add f && git commit` is scanned by
# nothing, and every other hook still reports healthy.
D=$(mkrepo); rm "$D/.ai/hooks/pre-commit"
say "$(rc "$D")" "1" "pre-commit missing → problem"
say "$(has "$D" "pre-commit missing")" "0" "…names the hook"
# A plugin upgrade cannot copy it in, so this line is how an upgraded project learns of
# it — and it must say how. Following it must actually clear the problem.
FIX=$(run "$D" | grep -o "cp '[^']*/git/pre-commit' '[^']*/' && chmod +x '[^']*'" | head -1)
say "$([ -n "$FIX" ] && echo yes)" "yes" "…and gives the command that copies it in"
(cd "$D" && eval "$FIX") >/dev/null 2>&1
say "$(rc "$D")" "0" "…which, run, clears it"
rm -rf "$D"
# A flight-rules-doctor.sh copied in by hand, with no git/ beside it, printed a cp from a directory
# that does not exist (/dg, 2026-10-08). It names flight-rules' hooks/git/ instead.
D=$(mkrepo); rm "$D/.ai/hooks/pre-commit"; mkdir -p "$D/lone"; cp "$DOCTOR" "$D/lone/flight-rules-doctor.sh"
LONE=$(cd "$D" && HOME="$D/fakehome" bash "$D/lone/flight-rules-doctor.sh" 2>&1)
say "$(grep -c "$D/lone/git" <<<"$LONE")" "0" "doctor with no git/ beside it prints no cp from there"
say "$(grep -c "from flight-rules' hooks/git/" <<<"$LONE")" "1" "…and names where the hook comes from"
rm -rf "$D"

D=$(mkrepo); printf 'MERGE_NEEDS_INSTRUCTION=off\n' >> "$D/.ai/flight-rules.conf"
say "$(has "$D" "no longer needs the user")" "0" "MERGE_NEEDS_INSTRUCTION=off is surfaced, not silent"
rm -rf "$D"

# doctor strips inline comments; the hooks did not. It validated a value that was never
# the one in force, and reported ✅ on a repo whose enforcement was off.
D=$(mkrepo); printf 'PROTECTED_BRANCHES=^main$   # trunk-based\n' > "$D/.ai/flight-rules.conf"
say "$(has "$D" "PROTECTED_BRANCHES=^main\$")" "0" "a commented value is reported as the hooks see it"
rm -rf "$D"

# PR_ONLY_BRANCHES=off and NOTE_GATED_BRANCHES=off are both honoured — by
# reference-transaction and commit-msg respectively. Calling them errors was false, and
# it made doctor nag daily about a correctly configured repo.
D=$(mkrepo); printf 'PROTECTED_BRANCHES=^main$\nPR_ONLY_BRANCHES=off\n' > "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "0" "PR_ONLY_BRANCHES=off is not an error"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=^main$\nNOTE_GATED_BRANCHES=off\n' > "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "0" "NOTE_GATED_BRANCHES=off is not an error"
rm -rf "$D"

# Three "looks installed but isn't" states doctor could not see (D4, 2026-09-11). Each
# one leaves every existing check green while the enforcement does nothing.

# 1. The hooks are present, executable, and empty. doctor already content-checks the
#    AGENT guard for a pre-conf copy; the five git hooks had no equivalent, and
#    CLAUDE.md calls a drifted hook copy the failure this repo cannot afford.
D=$(mkrepo)
for f in "$D"/.ai/hooks/*; do printf '#!/bin/sh\nexit 0\n' > "$f"; done
chmod +x "$D"/.ai/hooks/*
say "$(rc "$D")" "1" "hooks replaced by no-op stubs → problem"
say "$(has "$D" "does not look like")" "0" "…and says which"
rm -rf "$D"

# 1b. A project upgrading to 0.23.0 already had its own pre-commit (a linter). doctor
#     called it a possible stub and never said where it goes (/dg, 2026-10-08).
D=$(mkrepo)
printf '#!/bin/sh\nnpx lint-staged\n' > "$D/.ai/hooks/pre-commit"
say "$(has "$D" "rename it pre-commit.local")" "0" "a foreign pre-commit → told about pre-commit.local"
rm -rf "$D"

# 1c. A pre-commit.local without its executable bit is skipped by the scan without a
#     word, so the project's own linter stops running unnoticed (/dg, 2026-10-08).
D=$(mkrepo)
printf '#!/bin/sh\nexit 0\n' > "$D/.ai/hooks/pre-commit.local"
say "$(rc "$D")" "1" "a non-executable pre-commit.local → problem"
say "$(has "$D" "pre-commit.local is not executable")" "0" "…and says so"
chmod +x "$D/.ai/hooks/pre-commit.local"
say "$(rc "$D")" "0" "…and an executable one is fine"
rm -rf "$D"

# 2. settings.json wires a script that is not there. doctor grepped the file for the
#    string `pre-commit-check.sh`, which a dangling path satisfies just as well.
D=$(mkrepo); mkdir -p "$D/.claude"
cat > "$D/.claude/settings.json" <<'JSON'
{ "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command",
  "command": "bash \"$(git rev-parse --show-toplevel)/hooks/agent/pre-commit-check.sh\"" } ] } ] } }
JSON
say "$(rc "$D")" "1" "settings.json points at a missing script → problem"
say "$(has "$D" "does not exist")" "0" "…and names the path"
rm -rf "$D"
# 1b. core.hooksPath = ~/… is a path git expands; read raw, doctor joined it to the
#     repo root and reported a working gate as "does not exist — git runs NO hooks".
D=$(mkrepo); mkdir -p "$D/fakehome"; mv "$D/.ai/hooks" "$D/fakehome/hk"
git -C "$D" config core.hooksPath '~/hk'
say "$(has "$D" "does not exist")" "1" "core.hooksPath=~/hk that exists: no dangling-path line"
OUT=$(run "$D" | tail -n +2)
say "$(grep -c 'missing from' <<<"$OUT")-$(grep -c '✅ core.hooksPath=' <<<"$OUT")" "0-1" "…every hook found there, in the same run that names the path as fine"
say "$(has "$D" "core.hooksPath=$D/fakehome/hk")" "0" "…and the expanded path is named as fine"
rm -rf "$D"

# 2b. …but a ${CLAUDE_PLUGIN_ROOT} path points into the installed plugin, not into this
#     repo, so it must not be reported as missing.
D=$(mkrepo); mkdir -p "$D/.claude"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash \\"${CLAUDE_PLUGIN_ROOT}/hooks/agent/pre-commit-check.sh\\""}]}]}}' > "$D/.claude/settings.json"
say "$(rc "$D")" "0" "a plugin-rooted path is not reported as missing"
rm -rf "$D"

# 2c. A script wired from a prefix the regex did not list (#66). The optional prefix group
#     knew `.ai/` and `${CLAUDE_PLUGIN_ROOT}/`, so `.claude/hooks/x.sh` was captured as
#     `hooks/x.sh` and tested at the wrong place — three ❌ lines about files that
#     existed and ran, in the layout hooks/README.md itself recommends. Seen 2026-10-04.
D=$(mkrepo); mkdir -p "$D/.claude/hooks"
cat > "$D/.claude/settings.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command",
  "command": "bash -c 'exec \"$(git rev-parse --show-toplevel)/.claude/hooks/x.sh\"'" } ] } ] } }
JSON
printf '#!/bin/sh\nexit 0\n' > "$D/.claude/hooks/x.sh"; chmod +x "$D/.claude/hooks/x.sh"
say "$(rc "$D")" "0" "an existing .claude/hooks/ script is not reported as missing"
say "$(has "$D" "does not exist")" "1" "…no dangling-path line at all"
rm "$D/.claude/hooks/x.sh"
say "$(rc "$D")" "1" "…and the same wiring with the script gone → problem"
say "$(has "$D" "wires .claude/hooks/x.sh, which does not exist")" "0" "…naming the path as written, prefix included"
rm -rf "$D"

# 2e. A variable-prefixed path — the `R=$(git rev-parse --show-toplevel); … "$R/hooks/x.sh"`
#     idiom this repo's own .claude/settings.json uses. 2c's fix captured the whole prefix,
#     so `$R/hooks/x.sh` was read as `R/hooks/x.sh` and reported missing on the first
#     doctor run after it merged (dev f86a990, 2026-10-04). A `$VAR/` prefix other than
#     CLAUDE_PLUGIN_ROOT is taken to be the repo root, which is what the idiom means.
D=$(mkrepo); mkdir -p "$D/.claude" "$D/hooks"
cat > "$D/.claude/settings.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "bash -c 'R=$(git rev-parse --show-toplevel); exec bash \"$R/hooks/x.sh\"'" },
  { "type": "command", "command": "bash -c 'R=$(git rev-parse --show-toplevel); exec bash \"${R}/hooks/y.sh\"'" } ] } ] } }
JSON
printf '#!/bin/sh\nexit 0\n' > "$D/hooks/x.sh"; cp "$D/hooks/x.sh" "$D/hooks/y.sh"; chmod +x "$D/hooks/x.sh" "$D/hooks/y.sh"
say "$(has "$D" "does not exist")" "1" "\$R/ and \${R}/ prefixed scripts that exist are not reported"
rm "$D/hooks/y.sh"
say "$(has "$D" "wires hooks/y.sh, which does not exist")" "0" "…and a missing one is named by its repo-relative path"
say "$(has "$D" "wires hooks/x.sh")" "1" "…while the one that exists stays silent"
rm -rf "$D"

# 2f. A `$VAR` prefix followed by more path, or by a closing quote: `$CLAUDE_PROJECT_DIR`
#     is Claude Code's documented form, and both `"$CLAUDE_PROJECT_DIR"/.claude/hooks/x.sh`
#     and `$CLAUDE_PROJECT_DIR/.claude/hooks/x.sh` were captured as the absolute
#     `/.claude/hooks/x.sh` and reported missing, every day (/dg, 2026-10-08).
D=$(mkrepo); mkdir -p "$D/.claude/hooks" "$D/hooks"
cat > "$D/.claude/settings.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/a.sh" },
  { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/b.sh" },
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR/.claude/hooks/c.sh\"" },
  { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/d.sh" },
  { "type": "command", "command": "bash \"$(git rev-parse --show-toplevel)\"/hooks/e.sh" } ] } ] } }
JSON
for f in .claude/hooks/a.sh .claude/hooks/b.sh .claude/hooks/c.sh .claude/hooks/d.sh hooks/e.sh; do
  printf '#!/bin/sh\nexit 0\n' > "$D/$f"; chmod +x "$D/$f"
done
say "$(has "$D" "does not exist")" "1" "\$CLAUDE_PROJECT_DIR forms, quoted or not, that exist are not reported"
rm "$D/.claude/hooks/a.sh" "$D/.claude/hooks/b.sh" "$D/.claude/hooks/c.sh" "$D/.claude/hooks/d.sh" "$D/hooks/e.sh"
say "$(has "$D" "wires .claude/hooks/a.sh, which does not exist")" "0" "…a missing \"\$VAR\"/ one is named by its repo-relative path"
say "$(has "$D" "wires .claude/hooks/b.sh, which does not exist")" "0" "…as is a missing \$VAR/.claude/ one"
say "$(has "$D" "wires .claude/hooks/c.sh, which does not exist")" "0" "…and a missing \"\$VAR/…\" one"
say "$(has "$D" "wires .claude/hooks/d.sh, which does not exist")" "0" "…and a missing \${VAR}/ one"
say "$(has "$D" "wires hooks/e.sh, which does not exist")" "0" "…and a quoted \$(git rev-parse) one"
rm -rf "$D"

# 2g. `$HOME`, `${HOME}` and an unquoted `~` are the home directory, not the repo root:
#     they were tested under the repo, so a hook missing from home passed when the repo
#     happened to hold that path, and one present there was reported missing. A quoted
#     path with a space was cut at the space and reported missing (/dg G2-5, 2026-10-08).
#     A quoted wrapper and its hook read as one spaced path (/dg, 2026-10-12): either
#     existing is enough.
D=$(mkrepo); mkdir -p "$D/.claude" "$D/fakehome/h/hooks" "$D/my dir/hooks" "$D/h/hooks" "$D/hooks"
cat > "$D/.claude/settings.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "$HOME/h/hooks/a.sh" },
  { "type": "command", "command": "bash \"${HOME}/h/hooks/b.sh\"" },
  { "type": "command", "command": "~/h/hooks/c.sh" },
  { "type": "command", "command": "bash ~/h/hooks/d.sh" },
  { "type": "command", "command": "X=~/h/hooks/k.sh; bash \"$X\"" },
  { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR/my dir/hooks/e.sh\"" },
  { "type": "command", "command": "bash -c 'exec bash \"$CLAUDE_PROJECT_DIR/my dir/hooks/f.sh\"'" },
  { "type": "command", "command": "bash './my dir/hooks/g.sh'" },
  { "type": "command", "command": "bash \"my dir/hooks/m.sh\"" },
  { "type": "command", "command": "bash -c '/usr/bin/env bash ./hooks/w1.sh'" },
  { "type": "command", "command": "sh -c \"/usr/bin/env bash hooks/w2.sh\"" },
  { "type": "command", "command": "bash -c '/usr/bin/timeout 5 $CLAUDE_PROJECT_DIR/hooks/w3.sh'" } ] } ] } }
JSON
for f in fakehome/h/hooks/a.sh fakehome/h/hooks/b.sh fakehome/h/hooks/c.sh fakehome/h/hooks/d.sh fakehome/h/hooks/k.sh \
         "my dir/hooks/e.sh" "my dir/hooks/f.sh" "my dir/hooks/g.sh" "my dir/hooks/m.sh" hooks/w1.sh hooks/w2.sh hooks/w3.sh; do
  printf '#!/bin/sh\nexit 0\n' > "$D/$f"; chmod +x "$D/$f"
done
say "$(rc "$D")" "0" "\$HOME, ~, spaced and wrapped paths that exist: doctor passes"
say "$(has "$D" "does not exist")" "1" "…and reports none of them"
rm "$D"/fakehome/h/hooks/*.sh "$D"/my\ dir/hooks/*.sh "$D"/hooks/w*.sh
for f in a b c d k; do printf '#!/bin/sh\nexit 0\n' > "$D/h/hooks/$f.sh"; done   # the same paths under the repo
say "$(has "$D" "wires ~/h/hooks/a.sh, which does not exist")" "0" "…a missing \$HOME/ one is named, though the repo has that path"
say "$(has "$D" "wires ~/h/hooks/b.sh, which does not exist")" "0" "…as is a missing \"\${HOME}/…\" one"
say "$(has "$D" "wires ~/h/hooks/c.sh, which does not exist")" "0" "…and a missing ~/ one"
say "$(has "$D" "wires ~/h/hooks/d.sh, which does not exist")" "0" "…and a missing ~/ one after a word"
say "$(has "$D" "wires ~/h/hooks/k.sh, which does not exist")" "0" "…and a missing ~/ one after ="
say "$(has "$D" "wires my dir/hooks/e.sh, which does not exist")" "0" "…and a missing quoted path with a space, named whole"
say "$(has "$D" "wires my dir/hooks/f.sh, which does not exist")" "0" "…and one inside bash -c '…'"
say "$(has "$D" "wires ./my dir/hooks/g.sh, which does not exist")" "0" "…and a missing single-quoted one"
say "$(has "$D" "wires my dir/hooks/m.sh, which does not exist")" "0" "…and one not starting at a root, / or ."
say "$(has "$D" "wires dir/hooks/")" "1" "…never cut at the space"
say "$(has "$D" "wires ./hooks/w1.sh, which does not exist")" "0" "…a missing hook behind a quoted wrapper is named by itself"
say "$(has "$D" "wires hooks/w2.sh, which does not exist")" "1" "…but a last word not starting like a path is not split off"
say "$(has "$D" "wires hooks/w3.sh, which does not exist")" "0" "…and a \$VAR one behind a wrapper is named from the root"
rm -rf "$D"

# 2h. A `$VAR` or `~` the shell never expands — inside single quotes, or `~` inside double
#     quotes — means the hook never runs, so it is reported even where a file exists. As
#     the home directory, `'$HOME/…'` was passed when the file was there (/dg, 2026-10-12);
#     a `bash -c '$VAR/…'` script does expand, and is checked like any other.
D=$(mkrepo); mkdir -p "$D/.claude/hooks" "$D/fakehome/h/hooks"
cat > "$D/.claude/settings.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "'$CLAUDE_PROJECT_DIR'/.claude/hooks/q.sh" },
  { "type": "command", "command": "'$CLAUDE_PROJECT_DIR/.claude/hooks/r.sh'" },
  { "type": "command", "command": "bash '$HOME/h/hooks/s.sh'" },
  { "type": "command", "command": "bash \"~/h/hooks/t.sh\"" },
  { "type": "command", "command": "bash -c '$HOME/h/hooks/u.sh'" } ] } ] } }
JSON
for f in .claude/hooks/q.sh .claude/hooks/r.sh fakehome/h/hooks/s.sh fakehome/h/hooks/t.sh fakehome/h/hooks/u.sh; do
  printf '#!/bin/sh\nexit 0\n' > "$D/$f"; chmod +x "$D/$f"
done
say "$(has "$D" "…/.claude/hooks/q.sh under a quoted \$VAR or ~, which the shell never expands")" "0" "'\$VAR'/… is reported, though the file exists"
say "$(has "$D" "…/.claude/hooks/r.sh under a quoted \$VAR or ~, which the shell never expands")" "0" "…as is '\$VAR/…'"
say "$(has "$D" "…/h/hooks/s.sh under a quoted \$VAR or ~, which the shell never expands")" "0" "…and '\$HOME/…'"
say "$(has "$D" "…/h/hooks/t.sh under a quoted \$VAR or ~, which the shell never expands")" "0" "…and a double-quoted ~/…"
say "$(has "$D" "u.sh")" "1" "…while bash -c '\$HOME/…', which its shell expands, passes"
rm -rf "$D"

# 2d. An absolute path is tested where it points, not under the repo root.
D=$(mkrepo); mkdir -p "$D/.claude" "$D/elsewhere/hooks"
printf '#!/bin/sh\nexit 0\n' > "$D/elsewhere/hooks/y.sh"; chmod +x "$D/elsewhere/hooks/y.sh"
printf '{"hooks":{"SessionStart":[{"hooks":[{"command":"bash %s/elsewhere/hooks/y.sh"}]}]}}' "$D" > "$D/.claude/settings.json"
say "$(has "$D" "does not exist")" "1" "an absolute path to an existing script is not reported as missing"
rm -rf "$D"

# 3. The plugin is listed and switched OFF. The check was a grep for the name.
D=$(mkrepo); mkdir -p "$D/fakehome/.claude"
printf '{"enabledPlugins":{"flight-rules@mkb3nigma": false}}\n' > "$D/fakehome/.claude/settings.json"
say "$(has "$D" "no agent guard wired")" "0" "a disabled plugin does not count as wired"
rm -rf "$D"

D=$(mkrepo); git -C "$D" config --unset merge.ff
say "$(rc "$D")" "1" "merge.ff unset → problem"
say "$(has "$D" "fast-forward merge creates no commit")" "0" "…explains why"
rm -rf "$D"

echo "A hook that is present, executable, the right hook — and an older release's:"
# A plugin update cannot touch the project's git hooks, so four of AppliHawk's sat at
# 0.22.0 under a 0.23.0 plugin with every line green (2026-10-12). Byte-identical to an
# older release in the plugin cache is stale beyond doubt; matching no release may be the
# project's own adaptation. The fake HOME's cache holds one older release, 0.0.1.
mkcache() {  # <repo> <hook>: a 0.0.1 release of <hook> in the fake plugin cache
  mkdir -p "$1/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git"
  { cat "$H/git/$2"; echo "# flight-rules 0.0.1"; } > "$1/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/$2"
}
D=$(mkrepo); mkcache "$D" commit-msg
cp "$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/commit-msg" "$D/.ai/hooks/commit-msg"
say "$(rc "$D")" "1" "a copy identical to a cached older release → problem"
say "$(has "$D" "commit-msg is the flight-rules 0.0.1 copy")" "0" "…naming the release it came from"
say "$(has "$D" "to update: bash")" "0" "…and printing the sync command"
SYNC=$(run "$D" | grep -o 'to update: bash .*--from [^ ]* --stale-only' | sed 's/^to update: //' | head -1)
say "$([ -n "$SYNC" ] && echo yes)" "yes" "…which can be lifted from the output, in its --stale-only form"
(cd "$D" && HOME="$D/fakehome" eval "$SYNC") >/dev/null 2>&1
say "$(rc "$D")" "0" "…and, run as printed, clears it"
say "$(has "$D" "to update:")" "1" "…after which no sync command is printed"
rm -rf "$D"

D=$(mkrepo); echo "# this project's own change" >> "$D/.ai/hooks/post-merge"
say "$(rc "$D")" "0" "a copy matching no release is a warning, not a problem"
say "$(has "$D" "post-merge differs from this flight-rules' copy")" "0" "…that names the hook"
say "$(has "$D" "to update: bash")" "0" "…and still prints the sync command"
rm -rf "$D"

# Marked adapted, the project's own hook is accepted: a ⚠️ every session with no way to
# accept it was the complaint (review, 2026-10-12).
D=$(mkrepo); printf '# flight-rules: adapted\n# own change\n' >> "$D/.ai/hooks/post-merge"
say "$(rc "$D")" "0" "a hook marked 'flight-rules: adapted' is not a problem"
say "$(has "$D" "post-merge adapted here (marked")" "0" "…and is reported as adapted"
say "$(has "$D" "post-merge differs from")" "1" "…not as differing"
say "$(has "$D" "to update:")" "1" "…and no sync command is printed for it"
rm -rf "$D"

# Indented, the comment line is still the mark.
D=$(mkrepo); printf '  # flight-rules: adapted\n' >> "$D/.ai/hooks/post-merge"
say "$(has "$D" "post-merge adapted here")" "0" "an indented '# flight-rules: adapted' is the mark too"
rm -rf "$D"
# The phrase inside a line of code is not the mark: only a comment line of its own is.
D=$(mkrepo); printf 'echo "flight-rules: adapted"\n' >> "$D/.ai/hooks/post-merge"
say "$(has "$D" "post-merge adapted here")" "1" "the phrase inside code is not the adapted mark"
say "$(has "$D" "post-merge differs from")" "0" "…the hook is reported as differing"
rm -rf "$D"

# The printed command, run as printed, keeps an unmarked adapted hook beside a stale one:
# the bare form overwrote it, and on screen the ⚠️ that would have warned is not shown
# (fix review, 2026-10-13 — reproduced).
D=$(mkrepo); mkcache "$D" commit-msg
cp "$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/commit-msg" "$D/.ai/hooks/commit-msg"
echo "# my own tweak" >> "$D/.ai/hooks/post-merge"
SYNC=$(run "$D" | grep -o 'to update: bash .*--from [^ ]* --stale-only' | sed 's/^to update: //' | head -1)
[ -n "$SYNC" ] && (cd "$D" && HOME="$D/fakehome" eval "$SYNC") >/dev/null 2>&1; say "$?" "0" "stale + adapted: the printed command runs"
say "$(cmp -s "$D/.ai/hooks/commit-msg" "$H/git/commit-msg" && echo synced)" "synced" "…replaces the stale hook"
say "$(grep -c 'my own tweak' "$D/.ai/hooks/post-merge")" "1" "…and keeps the adapted one"
rm -rf "$D"

# The missing-hook line already gives a cp; the sync command covers it too.
D=$(mkrepo); rm "$D/.ai/hooks/pre-commit"
say "$(has "$D" "to update: bash")" "0" "a missing hook also prints the sync command"
rm -rf "$D"

echo "The conf — typos and bad values must not pass silently:"
D=$(mkrepo); printf 'HOOK_SYNC=auto\n' >> "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "0" "HOOK_SYNC=auto is a known key"
say "$(has "$D" "HOOK_SYNC=auto")" "0" "…and is reported"
say "$(has "$D" "unknown key")" "1" "…not as unknown"
printf 'HOOK_SYNC=yes\n' >> "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "0" "HOOK_SYNC=yes is a warning, not a failure"
say "$(has "$D" "neither auto nor report")" "0" "…saying what the values are"
rm -rf "$D"

# /dg's comic settings (owner, 2026-10-17): read by a skill, so a typo would only show as
# a comic that appears, or lands in a PR, against the project's wish.
D=$(mkrepo); printf 'DG_COMIC=never\nDG_COMIC_PR=always\n' >> "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "0" "DG_COMIC and DG_COMIC_PR are known keys"
say "$(has "$D" "unknown key")" "1" "…not reported as unknown"
say "$(has "$D" "DG_COMIC=never")" "0" "…and each is reported"
say "$(has "$D" "DG_COMIC_PR=always")" "0" "…both of them"
printf 'DG_COMIC=sometimes\nDG_COMIC_PR=yes\n' >> "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "0" "a bad comic value is a warning, not a failure"
say "$(has "$D" "DG_COMIC='sometimes' is neither always nor never")" "0" "…naming DG_COMIC's values"
say "$(has "$D" "DG_COMIC_PR='yes' is not never, ask or always")" "0" "…and DG_COMIC_PR's"
say "$(has "$D" "treats it as never and keeps the comic out of PRs")" "0" "…falling back to never, the opt-in default"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCH=^main$\n' > "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "0" "unknown key is a warning, not a failure"
say "$(has "$D" "unknown key 'PROTECTED_BRANCH'")" "0" "…and is named"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=^(main$\n' > "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "1" "invalid regex → problem"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=main\n' > "$D/.ai/flight-rules.conf"
say "$(has "$D" "unanchored")" "0" "unanchored pattern → warning"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\n' > "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "0" "PROTECTED_BRANCHES=off is allowed"
say "$(has "$D" "no protected branches in the agent guard")" "0" "…with a warning naming the layers it stands down"
# It used to say "the branch policy is off", which is not what happens: pre-merge-commit,
# pre-rebase and the squash guard read PR_ONLY_BRANCHES directly and keep refusing local
# merges and rebases into a PR-only branch. A reader turning `off` on to work locally
# would have been told more was disabled than is.
say "$(has "$D" "PR_ONLY_BRANCHES still refuses")" "0" "…and says what it does NOT disable"
rm -rf "$D"

# This case asserted that `off` on a git-hook key is an error, on the belief that only
# PROTECTED_BRANCHES understands it. That was wrong: reference-transaction honours
# PR_ONLY_BRANCHES=off and commit-msg honours NOTE_GATED_BRANCHES=off. The old assertion
# made doctor report a problem every day about a correctly configured project.
D=$(mkrepo); printf 'PR_ONLY_BRANCHES=off\n' > "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "0" "off on a git-hook key is honoured, not an error"
rm -rf "$D"

D=$(mkrepo); rm "$D/.ai/flight-rules.conf"
say "$(rc "$D")" "0" "no conf at all is a warning only"
rm -rf "$D"

echo "PROTECTED_BRANCHES=off empties the note gate, and doctor says so:"
# The note gate's default set is DERIVED from PROTECTED_BRANCHES — "protected but not
# PR-only" — so turning protection off empties it. Measured 2026-09-13: a merge landed
# on an integration branch with no pre-merge-check note and no layer said a word. Only
# worth saying when the project integrates somewhere other than main; a trunk-only
# project has no note-gated branch either way.
D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\nINTEGRATION_BRANCH=dev\n' > "$D/.ai/flight-rules.conf"
say "$(has "$D" "empties the note gate")" "0" "off + a dev integration branch → warned"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\nINTEGRATION_BRANCH=main\n' > "$D/.ai/flight-rules.conf"
say "$(has "$D" "empties the note gate")" "1" "off on a trunk-only project → not warned"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\nNOTE_GATED_BRANCHES=^dev$\nINTEGRATION_BRANCH=dev\n' > "$D/.ai/flight-rules.conf"
say "$(has "$D" "empties the note gate")" "1" "NOTE_GATED_BRANCHES named → not warned"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=^(main|dev)$\nINTEGRATION_BRANCH=dev\n' > "$D/.ai/flight-rules.conf"
say "$(has "$D" "empties the note gate")" "1" "policy on → not warned"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\nPR_ONLY_BRANCHES=^(main|dev)$\nINTEGRATION_BRANCH=dev\n' > "$D/.ai/flight-rules.conf"
say "$(has "$D" "empties the note gate")" "1" "integration branch is PR-only → not warned, there is no gate to lose"
rm -rf "$D"

echo "Guard wiring — once, not twice, not a stale copy:"
D=$(mkrepo); mkdir -p "$D/.claude" "$D/fakehome/.claude"
printf '{"enabledPlugins":{"flight-rules@flight-rules":true}}' > "$D/fakehome/.claude/settings.json"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash x/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
say "$(has "$D" "runs twice")" "0" "plugin + local wiring → double-fire warning"
rm -rf "$D"

# The plugin can be enabled at PROJECT scope (#67): Claude Code then writes the
# enabledPlugins key to <repo>/.claude/settings.local.json and nothing to ~/.claude.
# doctor read only the user-level file and declared the guard absent in a repo where it
# demonstrably ran — the one thing it must never say wrongly, because the "fix" a reader
# reaches for is hand-wiring pre-commit-check.sh, which is the double-fire. Seen 2026-10-04.
D=$(mkrepo); mkdir -p "$D/.claude" "$D/fakehome/.claude"
printf '{}' > "$D/fakehome/.claude/settings.json"
printf '{"enabledPlugins":{"flight-rules@flight-rules":true}}' > "$D/.claude/settings.local.json"
say "$(has "$D" "agent guard via the plugin")" "0" "plugin enabled only in .claude/settings.local.json → wired"
say "$(has "$D" "no agent guard wired")" "1" "…and not declared absent"
rm -rf "$D"

D=$(mkrepo); mkdir -p "$D/.claude"
printf '{"enabledPlugins":{"flight-rules@flight-rules":true},"hooks":{"PreToolUse":[{"hooks":[{"command":"bash x/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
say "$(has "$D" "runs twice")" "0" "plugin enabled in .claude/settings.json + local wiring in the same file → double-fire warning"
rm -rf "$D"

D=$(mkrepo); mkdir -p "$D/.claude"
printf '{"enabledPlugins":{"flight-rules@flight-rules":false}}' > "$D/.claude/settings.local.json"
say "$(has "$D" "no agent guard wired")" "0" "a plugin disabled at project scope does not count as wired"
rm -rf "$D"

D=$(mkrepo); mkdir -p "$D/.claude/" "$D/.ai/hooks/agent"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash .ai/hooks/agent/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
printf '#!/bin/bash\n[[ "$COMMAND" == *"git commit"* ]]\n' > "$D/.ai/hooks/agent/pre-commit-check.sh"
say "$(rc "$D")" "1" "pre-conf copy of the guard → problem"
say "$(has "$D" "pre-conf copy")" "0" "…identified as such"
rm -rf "$D"

echo "--problems-only is silent on a healthy repo:"
D=$(mkrepo); rm "$D/.ai/flight-rules.conf"; printf 'PROTECTED_BRANCHES=^main$\n' > "$D/.ai/flight-rules.conf"
mkdir -p "$D/.claude" "$D/hooks/agent"; printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash hooks/agent/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
# The wired script has to be THERE: a healthy repo is one where the path resolves.
cp "$H/agent/pre-commit-check.sh" "$D/hooks/agent/pre-commit-check.sh"
OUT=$(cd "$D" && HOME="$D/fakehome" bash "$DOCTOR" --problems-only 2>&1)
say "$(printf '%s' "$OUT" | grep -c .)" "0" "no output when nothing is wrong"
rm -rf "$D"

echo "A command or skill of the user's or project's own that shadows a plugin skill is named:"
# AppliHawk's ~/.claude/commands/dg.md, a copy from 2026-06-11, ran for /dg in place of
# the plugin's skill through every release after it, and nothing said so (2026-10-13).
D=$(mkrepo); mkdir -p "$D/fakehome/.claude/commands" "$D/fakehome/.claude/skills/diagnose" "$D/.claude/skills/dg"
printf '{"enabledPlugins":{"flight-rules@flight-rules":true}}' > "$D/fakehome/.claude/settings.json"
printf -- '---\nname: dg\n---\n# an old full copy\n' > "$D/fakehome/.claude/commands/dg.md"
printf -- '---\nname: diagnose\n---\n# a copy\n' > "$D/fakehome/.claude/skills/diagnose/SKILL.md"
printf '# mine\n' > "$D/fakehome/.claude/commands/standup.md"
# A pointer at the project's copy-in is the documented pattern, not a shadow.
printf -- '---\nname: dg\n---\nRead and follow `.ai/skills/dg/SKILL.md`.\n' > "$D/.claude/skills/dg/SKILL.md"
# A command that hands over to the plugin's skill by name is a wrapper, not a shadow:
# AppliHawk's .claude/commands/*.md each say "Use the `flight-rules:<name>` skill" and
# were all flagged on the first real run (2026-10-17).
mkdir -p "$D/.claude/commands"
printf -- '---\ndescription: x\n---\nUse the `flight-rules:commit` skill.\n' > "$D/.claude/commands/commit.md"
say "$(rc "$D")" "0" "plugin on, shadowing commands: doctor exits 0 (a warning, not a failure)"
say "$(has "$D" "commit.md shadows")" "1" "…a command that delegates to flight-rules:<name> is not a shadow"
say "$(has "$D" "~/.claude/commands/dg.md shadows flight-rules' /dg")" "0" "…a user command named like a plugin skill is named"
say "$(has "$D" "~/.claude/skills/diagnose/SKILL.md shadows flight-rules' /diagnose")" "0" "…so is a user skill"
say "$(has "$D" "standup")" "1" "…a command with its own name is not"
say "$(has "$D" ".claude/skills/dg/SKILL.md shadows")" "1" "…nor a pointer at the project's copy-in"
# The exemption is the pointer or handover LINE, not the string anywhere (#82): a full
# copy that mentions either in passing runs its own steps in place of the plugin's.
printf -- '---\nname: pre-merge-check\n---\nUnlike flight-rules:pre-merge-check, this one skips the docs step.\n1. Run the tests.\n' > "$D/.claude/commands/pre-merge-check.md"
printf -- '---\nname: docs-lint\n---\nAdapted from skills/docs-lint/SKILL.md in the playbook.\n1. Read every doc.\n' > "$D/.claude/commands/docs-lint.md"
# The real pointer shapes stay exempt: this repo's own, and AppliHawk's wrapper as it
# reads (frontmatter, a comment, the handover line, an arguments line; 2026-10-19).
mkdir -p "$D/.claude/skills/rules-sync"
printf -- '---\nname: rules-sync\n---\n\nRead and follow `skills/rules-sync/SKILL.md` (path relative to the repository root; this repository\nis the playbook, so the file is the skill itself, not a copy). Arguments: $ARGUMENTS\n' > "$D/.claude/skills/rules-sync/SKILL.md"
printf -- '---\ndescription: x\nmodel: opus\n---\n<!-- description: states the invariant. -->\n\nUse the `flight-rules:feature-start` skill. It reads `.ai/skills/feature-start/EXTENSIONS.md` for the branch parameters.\n\nArguments: $ARGUMENTS\n' > "$D/.claude/commands/feature-start.md"
say "$(has "$D" ".claude/commands/pre-merge-check.md shadows flight-rules' /pre-merge-check")" "0" "…a copy that names flight-rules:<name> in prose still shadows"
say "$(has "$D" ".claude/commands/docs-lint.md shadows flight-rules' /docs-lint")" "0" "…so does one that names skills/<name>/SKILL.md in prose"
say "$(has "$D" "rules-sync/SKILL.md shadows")" "1" "…this repo's own pointer shape is not a shadow"
say "$(has "$D" "feature-start.md shadows")" "1" "…nor a downstream project's real wrapper"
say "$(rc "$D")" "0" "…and doctor still exits 0 with all of them present"
# Run by a relative path from a subdirectory: doctor cds to the repo root, and a plugin
# path resolved after that came back empty, so the check was skipped unsaid (release /dg,
# 2026-10-17).
mkdir -p "$D/plug" "$D/a/b"; cp -R "$H" "$D/plug/hooks"; cp -R "$H/../skills" "$D/plug/skills"
OUT=$(cd "$D/a/b" && HOME="$D/fakehome" bash ../../plug/hooks/flight-rules-doctor.sh 2>&1)
say "$(grep -c "commands/dg.md shadows" <<<"$OUT")" "1" "…also when doctor is run by a relative path from a subdirectory"
rm -rf "$D/plug" "$D/a"
# Plugin off: its skills are not in use here, so nothing is shadowed. Paired with a line
# doctor always prints, so a doctor that died also fails.
printf '{"enabledPlugins":{"flight-rules@flight-rules":false}}' > "$D/fakehome/.claude/settings.json"
OUT=$(run "$D")
say "$(grep -c 'shadows flight-rules' <<<"$OUT")" "0" "plugin off: nothing reported as shadowed"
say "$(grep -c 'warning(s)' <<<"$OUT")" "1" "…and doctor ran to its summary"
rm -rf "$D"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
