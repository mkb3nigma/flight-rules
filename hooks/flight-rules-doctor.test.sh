#!/usr/bin/env bash
# Tests for flight-rules-doctor.sh — each case is an install state that has silently failed
# for real. Run: ./flight-rules-doctor.test.sh (no args, no network; builds throwaway repos).
set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="$H/flight-rules-doctor.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-lib.sh" || exit 2


# A repo with the hooks copied in and installed the documented way.
mkrepo() {
  local d; d=$(tmpd)
  git -C "$d" init -q -b main || die "git init failed in $d"
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  mkdir -p "$d/.flight-rules/hooks"
  # A cp that fails leaves doctor reporting a missing hook, which several cases here
  # expect for other reasons — the 2026-09-11 shape where a suite silently tested the
  # wrong copy. So it is checked, not assumed.
  cp "$H/git/pre-merge-commit" "$H/git/commit-msg" "$H/git/pre-rebase" "$H/git/post-merge" \
     "$H/git/reference-transaction" "$H/git/pre-commit" "$H/git/pre-push" "$d/.flight-rules/hooks/" || die "could not copy the git hooks from $H/git"
  chmod +x "$d"/.flight-rules/hooks/*
  git -C "$d" config core.hooksPath .flight-rules/hooks
  git -C "$d" config merge.ff false
  printf 'PROTECTED_BRANCHES=^main$\n' > "$d/.flight-rules/conf"
  printf '.flight-rules/worktrees/\n' > "$d/.gitignore"   # as a healthy project has it (D1)
  # What every assertion assumes: a repo, and seven hooks that are there to be broken.
  [ -d "$d/.git" ] || die "no .git in the fixture at $d"
  for _h in pre-merge-commit commit-msg pre-rebase post-merge reference-transaction pre-commit pre-push; do
    [ -x "$d/.flight-rules/hooks/$_h" ] || die "$_h missing or not executable in the fixture"
  done
  printf '%s' "$d"
}
# run <dir> → prints "<exit> <output>"; HOME is redirected so the plugin check is deterministic.
run() { local d="$1" out rc; out=$(cd "$d" && HOME="$d/fakehome" bash "$DOCTOR" 2>&1); rc=$?; printf '%s\n%s' "$rc" "$out"; }
rc()  { run "$1" | head -1; }
has() { run "$1" | tail -n +2 | grep -qF -- "$2"; echo $?; }
# git with no hooks, to build a fixture's history: the hooks under test are not its subject.
GN=(git -c core.hooksPath=/dev/null)

echo "Healthy install:"
D=$(mkrepo)
say "$(rc "$D")" "0" "installed repo passes"
say "$(has "$D" "merge.ff=false")" "0" "reports merge.ff"
# "Run from anywhere inside the repo": from a subdirectory it reads the repo's conf.
mkdir -p "$D/sub"; OUT=$(cd "$D/sub" && HOME="$D/fakehome" bash "$DOCTOR" 2>&1)
say "$(grep -cF '✅ PROTECTED_BRANCHES=^main$' <<<"$OUT")" "1" "…and, run from a subdirectory, reads the repo's conf"
rm -rf "$D"

echo "Hooks missing or not executable — the silent failures:"
D=$(mkrepo); git -C "$D" config --unset core.hooksPath
say "$(rc "$D")" "1" "no core.hooksPath → problem"
say "$(has "$D" "core.hooksPath is not set")" "0" "…and says so"
rm -rf "$D"

echo "A fresh repo is given a command that installs, not a path inside the plugin:"
# The bare "hooks/git/install.sh" named nothing a fresh plugin user could run (2026-10-13).
# The printed command is run as printed, and doctor afterwards is the proof it works.
D=$(tmpd); git -C "$D" init -q -b main || die "git init failed in $D"
OUT=$(run "$D")
# A clone of a project that committed its hooks: wired by the PLUGIN's install.sh
# without --from, which would replace hooks the project adapted (pre-review), and never
# by the repo's own install.sh, which a cloned repo can make anything (security review,
# 2026-10-13). The repo's copy here would print PLANTED if it were the one recommended.
C=$(mkrepo); git -C "$C" config --unset core.hooksPath; git -C "$C" config --unset merge.ff
printf '#!/bin/bash\necho PLANTED > "%s/PLANTED"\n' "$C" > "$C/.flight-rules/hooks/install.sh"
echo "# my own tweak" >> "$C/.flight-rules/hooks/post-merge"
CMD=$(run "$C" | sed -n 's/.*To wire them up: \(bash .*\)   (git config is per clone.*/\1/p')
say "$(printf '%s' "$CMD" | grep -c "$H/git/install.sh")" "1" "a clone with committed hooks is given the plugin's install.sh"
say "$(printf '%s' "$CMD" | grep -c -- '--from\|\.flight-rules/hooks/install.sh')" "0" "…not --from, and not the repo's own copy"
[ -n "$CMD" ] && (cd "$C" && eval "$CMD" >/dev/null 2>&1); say "$?" "0" "…which runs as printed"
say "$([ -e "$C/PLANTED" ] && echo ran || echo not)" "not" "…without running the repo's install.sh"
say "$(run "$C" | grep -cE 'core.hooksPath is not set|merge.ff is')" "0" "…and afterwards doctor reports neither"
say "$(grep -c 'my own tweak' "$C/.flight-rules/hooks/post-merge")" "1" "…with the project's adapted hook kept"
rm -rf "$C"
# A 0.22.0-shaped set has no pre-commit, and install.sh refuses it: the printed
# command copies the missing hook first, and then works (fix review, 2026-10-13).
C=$(mkrepo); git -C "$C" config --unset core.hooksPath; rm "$C/.flight-rules/hooks/pre-commit"
CMD=$(run "$C" | sed -n 's/.*To wire them up: \(.*bash .*\)   (git config is per clone.*/\1/p')
say "$(printf '%s' "$CMD" | grep -c 'cp .*pre-commit .*\.flight-rules/hooks/ && bash')" "1" "a committed set missing pre-commit: the copy comes first"
# From a subdirectory: the person runs it from wherever the session is (fix review).
mkdir -p "$C/sub"; [ -n "$CMD" ] && (cd "$C/sub" && eval "$CMD" >/dev/null 2>&1); say "$?" "0" "…and the command runs as printed, from a subdirectory"
say "$(git -C "$C" config --local core.hooksPath)" ".flight-rules/hooks" "…and wires the hooks"
rm -rf "$C"

# From a plugin directory with a space in its path — what %q quoting is for.
P="$(tmpd)/my plugin"; mkdir -p "$P/hooks" && cp "$DOCTOR" "$P/hooks/" && cp -R "$H/git" "$P/hooks/git" || die "could not lay out the spaced plugin"
OUT=$(cd "$D" && HOME="$D/fakehome" bash "$P/hooks/flight-rules-doctor.sh" 2>&1)
CMD=$(printf '%s\n' "$OUT" | sed -n 's/.*To install them into \.flight-rules\/hooks\/: \(bash .*\)   (it also sets.*/\1/p')
say "$([ -n "$CMD" ] && echo printed)" "printed" "no core.hooksPath → the full install command is printed"
[ -n "$CMD" ] && (cd "$D" && eval "$CMD" >/dev/null 2>&1); say "$?" "0" "…it runs as printed, from a path with a space"
say "$(run "$D" | grep -cE 'core.hooksPath is not set|missing from|merge.ff is')" "0" "…and afterwards doctor reports no hook or merge.ff problem"
say "$(has "$D" "core.hooksPath=.flight-rules/hooks")" "0" "…with the relative path installed"
rm -rf "$D" "$(dirname "$P")"
# An .ai/hooks/ that holds no git hooks (the agent guard's copy alone) and no
# .flight-rules/hooks/: install.sh installs into .ai/hooks, so that is the folder named —
# the message said .flight-rules/hooks/ while its command wrote .ai/hooks (V16).
D=$(tmpd); git -C "$D" init -q -b main || die "git init failed in $D"
mkdir -p "$D/.ai/hooks/agent" && cp "$H/agent/pre-commit-check.sh" "$D/.ai/hooks/agent/" || die "could not lay out $D/.ai/hooks"
OUT=$(run "$D")
say "$(grep -c 'To install them into .ai/hooks/: bash .*(it also sets merge.ff false; then commit .ai/hooks/)' <<<"$OUT")$(grep -c '\.flight-rules/hooks' <<<"$OUT")" "10" "an .ai/hooks/ with no git hooks in it: the folder install.sh uses is the one named"
CMD=$(printf '%s\n' "$OUT" | sed -n 's/.*To install them into \.ai\/hooks\/: \(bash .*\)   (it also sets.*/\1/p')
[ -n "$CMD" ] && (cd "$D" && eval "$CMD" >/dev/null 2>&1); say "$?$(git -C "$D" config --local core.hooksPath)" "0.ai/hooks" "…and the command, run as printed, installs there"
rm -rf "$D"

D=$(mkrepo); git -C "$D" config core.hooksPath .ai/gone
say "$(rc "$D")" "1" "hooksPath at a missing directory → problem"
say "$(has "$D" "git runs NO hooks")" "0" "…and says git runs nothing"
rm -rf "$D"

D=$(mkrepo); chmod -x "$D/.flight-rules/hooks/commit-msg"
say "$(rc "$D")" "1" "commit-msg without +x → problem"
say "$(has "$D" "commit-msg is not executable")" "0" "…names the hook"
rm -rf "$D"

D=$(mkrepo); rm "$D/.flight-rules/hooks/pre-rebase"
say "$(rc "$D")" "1" "pre-rebase missing → problem"
rm -rf "$D"
# The merge gate itself: left off the list doctor walks, a missing one went unreported.
D=$(mkrepo); rm "$D/.flight-rules/hooks/pre-merge-commit"
say "$(has "$D" "pre-merge-commit missing from")" "0" "pre-merge-commit missing → named"
rm -rf "$D"

# Without this one, cherry-pick / revert / branch -f / update-ref and a CONFLICTED
# merge all reach a PR-only branch unguarded — and every other hook still reports
# healthy, which is the exact "looks installed" failure flight-rules-doctor.sh exists to catch.
D=$(mkrepo); rm "$D/.flight-rules/hooks/reference-transaction"
say "$(rc "$D")" "1" "reference-transaction missing → problem"
say "$(has "$D" "reference-transaction missing")" "0" "…names the hook"
rm -rf "$D"

# The secret scan for commits (#71): without it, `git add f && git commit` is scanned by
# nothing, and every other hook still reports healthy.
D=$(mkrepo); rm "$D/.flight-rules/hooks/pre-commit"
say "$(rc "$D")" "1" "pre-commit missing → problem"
say "$(has "$D" "pre-commit missing")" "0" "…names the hook"
# A plugin upgrade cannot copy it in, so this line is how an upgraded project learns of
# it — and it must say how. Following it must actually clear the problem.
FIX=$(run "$D" | sed -n 's/.*Copy it in from this flight-rules: \(cp .*\/git\/pre-commit .* && chmod +x .*\)$/\1/p' | head -1)
say "$([ -n "$FIX" ] && echo yes)" "yes" "…and gives the command that copies it in"
say "$(has "$D" "On a branch (in a worktree when this checkout is on a protected branch), then commit it.")" "0" "…saying where to run it: on a protected branch it could not be committed (S5)"
(cd "$D" && eval "$FIX") >/dev/null 2>&1
say "$(rc "$D")" "0" "…which, run, clears it"
rm -rf "$D"
# A flight-rules-doctor.sh copied in by hand, with no git/ beside it, printed a cp from a directory
# that does not exist (/dg, 2026-10-08). It names flight-rules' hooks/git/ instead.
D=$(mkrepo); rm "$D/.flight-rules/hooks/pre-commit"; mkdir -p "$D/lone"; cp "$DOCTOR" "$D/lone/flight-rules-doctor.sh"
LONE=$(cd "$D" && HOME="$D/fakehome" bash "$D/lone/flight-rules-doctor.sh" 2>&1)
say "$(grep -c "$D/lone/git" <<<"$LONE")" "0" "doctor with no git/ beside it prints no cp from there"
say "$(grep -c "from flight-rules' hooks/git/" <<<"$LONE")" "1" "…and names where the hook comes from"
rm -rf "$D"

D=$(mkrepo); printf 'MERGE_NEEDS_INSTRUCTION=off\n' >> "$D/.flight-rules/conf"
say "$(has "$D" "⚠️  MERGE_NEEDS_INSTRUCTION=off — a merge into a protected branch no longer needs the user")" "0" "MERGE_NEEDS_INSTRUCTION=off is surfaced as a warning, not silent"
rm -rf "$D"

# doctor strips inline comments; the hooks did not. It validated a value that was never
# the one in force, and reported ✅ on a repo whose enforcement was off.
D=$(mkrepo); printf 'PROTECTED_BRANCHES=^main$   # trunk-based\n' > "$D/.flight-rules/conf"
say "$(has "$D" "PROTECTED_BRANCHES=^main\$")" "0" "a commented value is reported as the hooks see it"
say "$(run "$D" | grep -cxF '  ✅ PROTECTED_BRANCHES=^main$')" "1" "…the whole line, without the comment the match above would allow"
rm -rf "$D"

# PR_ONLY_BRANCHES=off and NOTE_GATED_BRANCHES=off are both honoured — by
# reference-transaction and commit-msg respectively. Calling them errors was false, and
# it made doctor nag daily about a correctly configured repo.
D=$(mkrepo); printf 'PROTECTED_BRANCHES=^main$\nPR_ONLY_BRANCHES=off\n' > "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "PR_ONLY_BRANCHES=off is not an error"
say "$(has "$D" "⚠️  PR_ONLY_BRANCHES=off — no branch is PR-only")" "0" "…but a warning naming what stands down"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=^main$\nNOTE_GATED_BRANCHES=off\n' > "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "NOTE_GATED_BRANCHES=off is not an error"
say "$(has "$D" "⚠️  NOTE_GATED_BRANCHES=off — no branch requires a pre-merge-check note")" "0" "…but a warning"
rm -rf "$D"

# Three "looks installed but isn't" states doctor could not see (D4, 2026-09-11). Each
# one leaves every existing check green while the enforcement does nothing.

# 1. The hooks are present, executable, and empty. doctor already content-checks the
#    AGENT guard for a pre-conf copy; the five git hooks had no equivalent, and
#    AGENTS.md calls a drifted hook copy the failure this repo cannot afford.
D=$(mkrepo)
for f in "$D"/.flight-rules/hooks/*; do printf '#!/bin/sh\nexit 0\n' > "$f"; done
chmod +x "$D"/.flight-rules/hooks/*
say "$(rc "$D")" "1" "hooks replaced by no-op stubs → problem"
say "$(has "$D" "does not look like")" "0" "…and says which"
rm -rf "$D"

# 1b. A project upgrading to 0.23.0 already had its own pre-commit (a linter). doctor
#     called it a possible stub and never said where it goes (/dg, 2026-10-08).
D=$(mkrepo)
printf '#!/bin/sh\nnpx lint-staged\n' > "$D/.flight-rules/hooks/pre-commit"
say "$(has "$D" "rename it pre-commit.local")" "0" "a foreign pre-commit → told about pre-commit.local"
rm -rf "$D"
# The same for pre-push, from 0.29.0: git-lfs installs one (#144).
D=$(mkrepo)
printf '#!/bin/sh
git lfs pre-push "$@"
' > "$D/.flight-rules/hooks/pre-push"
say "$(rc "$D")$(has "$D" "If it is your project's own pre-push, rename it pre-push.local")" "10" "a foreign pre-push → problem, told about pre-push.local"
rm -rf "$D"

# 1c. A pre-commit.local without its executable bit is skipped by the scan without a
#     word, so the project's own linter stops running unnoticed (/dg, 2026-10-08).
D=$(mkrepo)
printf '#!/bin/sh\nexit 0\n' > "$D/.flight-rules/hooks/pre-commit.local"
say "$(rc "$D")" "1" "a non-executable pre-commit.local → problem"
say "$(has "$D" "pre-commit.local is not executable")" "0" "…and says so"
chmod +x "$D/.flight-rules/hooks/pre-commit.local"
say "$(rc "$D")" "0" "…and an executable one is fine"
rm -rf "$D"
D=$(mkrepo)
printf '#!/bin/sh\nexit 0\n' > "$D/.flight-rules/hooks/pre-push.local"
say "$(rc "$D")$(has "$D" "pre-push.local is not executable — pre-push skips it silently")" "10" "a non-executable pre-push.local → problem, and says so"
chmod +x "$D/.flight-rules/hooks/pre-push.local"
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
D=$(mkrepo); mkdir -p "$D/fakehome"; mv "$D/.flight-rules/hooks" "$D/fakehome/hk"
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
say "$(has "$D" "⚠️  no agent guard wired")" "0" "a disabled plugin does not count as wired"
rm -rf "$D"

D=$(mkrepo); git -C "$D" config --unset merge.ff
say "$(rc "$D")" "1" "merge.ff unset → problem"
say "$(has "$D" "fast-forward merge creates no commit")" "0" "…explains why"
rm -rf "$D"

# Neither jq nor python3: the agent guard cannot read its input and denies every git
# command. A PATH of the tools doctor runs, without those two.
NJ=$(tmpd)
for t in git sed grep awk head tail sort cmp dirname basename cat tr; do ln -s "$(command -v "$t")" "$NJ/$t" || die "could not link $t"; done
D=$(mkrepo); OUT=$(cd "$D" && HOME="$D/fakehome" PATH="$NJ" "$BASH" "$DOCTOR" 2>&1); RC=$?
say "$RC" "1" "neither jq nor python3 on PATH → problem"
say "$(grep -c '❌ neither jq nor python3 on PATH' <<<"$OUT")" "1" "…named"
rm -rf "$D" "$NJ"

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
cp "$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/commit-msg" "$D/.flight-rules/hooks/commit-msg"
say "$(rc "$D")" "1" "a copy identical to a cached older release → problem"
say "$(has "$D" "commit-msg is the flight-rules 0.0.1 copy")" "0" "…naming the release it came from"
say "$(has "$D" "to update: bash")" "0" "…and printing the sync command"
say "$(has "$D" "HOOK_SYNC=auto in .flight-rules/conf runs this")" "0" "…naming the conf HOOK_SYNC goes in"
# A project on the old conf: the hint named the new path, and following it made a
# one-line conf that hid the whole old one (D4).
mkdir -p "$D/.ai"; mv "$D/.flight-rules/conf" "$D/.ai/flight-rules.conf" || die "could not move the conf in $D"
say "$(has "$D" "HOOK_SYNC=auto in .ai/flight-rules.conf runs this")$(has "$D" "HOOK_SYNC=auto in .flight-rules/conf")" "01" "…the old conf, where the project's is still there"
mv "$D/.ai/flight-rules.conf" "$D/.flight-rules/conf" || die "could not move the conf back in $D"
SYNC=$(run "$D" | grep -o 'to update: bash .*--from [^ ]* --stale-only' | sed 's/^to update: //' | head -1)
say "$([ -n "$SYNC" ] && echo yes)" "yes" "…which can be lifted from the output, in its --stale-only form"
(cd "$D" && HOME="$D/fakehome" eval "$SYNC") >/dev/null 2>&1
say "$(rc "$D")" "0" "…and, run as printed, clears it"
say "$(has "$D" "to update:")" "1" "…after which no sync command is printed"
rm -rf "$D"
# The plugin under a path with ß and a quote, under a UTF-8 locale: printf %q in macOS
# bash 3.2 split the ß and left a raw byte, so the command on screen was not UTF-8 and
# named a path that does not exist (fix review, 2026-10-24). shq keeps the bytes.
U8=$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -1); U8=${U8:-en_US.UTF-8}
L="$(tmpd)/Straße it's"; mkdir -p "$L/hooks" && cp -R "$H/git" "$L/hooks/" && cp "$DOCTOR" "$L/hooks/" || die "could not lay out the ß plugin"
D=$(mkrepo); mkcache "$D" commit-msg
cp "$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/commit-msg" "$D/.flight-rules/hooks/commit-msg"
OUT=$(cd "$D" && LC_ALL=$U8 HOME="$D/fakehome" bash "$L/hooks/flight-rules-doctor.sh" 2>&1)
SYNC=$(sed -n 's/.*to update: \(bash .* --stale-only --this-checkout\)   (.*/\1/p' <<<"$OUT" | head -1)
say "$(grep -c 'Straße' <<<"$SYNC")" "1" "a plugin path with ß and a quote: the sync command names it"
say "$([ -n "$SYNC" ] && printf '%s' "$SYNC" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && echo utf8)" "utf8" "…in valid UTF-8"
(cd "$D" && LC_ALL=$U8 HOME="$D/fakehome" eval "$SYNC") >/dev/null 2>&1; SRC_RC=$?
say "$SRC_RC" "0" "…which, run as printed, exits 0"
say "$(cmp -s "$D/.flight-rules/hooks/commit-msg" "$L/hooks/git/commit-msg" && echo same)" "same" "…and syncs from that exact path"
# A missing hook's cp line was quoted by hand in '…', so the quote in that path broke it
# (fourth review, D2).
rm -f "$D/.flight-rules/hooks/post-merge"
OUT=$(cd "$D" && LC_ALL=$U8 HOME="$D/fakehome" bash "$L/hooks/flight-rules-doctor.sh" 2>&1)
CP=$(sed -n 's/.*Copy it in from this flight-rules: \(cp .*\)$/\1/p' <<<"$OUT" | head -1)
say "$(grep -c "post-merge" <<<"$CP")" "1" "…a missing hook's cp line names it"
bash -n -c "$CP" 2>/dev/null; say "$?" "0" "…and parses, the quote in the path and all"
(cd "$D" && eval "$CP") >/dev/null 2>&1
say "$(cmp -s "$D/.flight-rules/hooks/post-merge" "$L/hooks/git/post-merge" && [ -x "$D/.flight-rules/hooks/post-merge" ] && echo copied)" "copied" "…and, run as printed, copies it in executable"
rm -rf "$D" "$(dirname "$L")"

D=$(mkrepo); echo "# this project's own change" >> "$D/.flight-rules/hooks/post-merge"
say "$(rc "$D")" "0" "a copy matching no release is a warning, not a problem"
say "$(has "$D" "⚠️  post-merge differs from this flight-rules' copy")" "0" "…that names the hook"
say "$(has "$D" "to update: bash")" "0" "…and still prints the sync command"
# "re-run without <flags> to replace it", followed as written, replaces it: the hint
# named only --stale-only, and --this-checkout without it was refused (group A fix review, F12).
# Since F1 that is one flag, --stale-only, wherever it sits in the command.
OUT=$(run "$D")
FULL=$(grep -o 'to update: bash .*--this-checkout   (' <<<"$OUT" | sed 's/^to update: //; s/   ($//' | head -1)
DROP=$(grep -o 're-run without [^)]* to replace every' <<<"$OUT" | sed 's/^re-run without //; s/ to replace every$//')
(cd "$D" && HOME="$D/fakehome" eval "${FULL/ $DROP/}") >/dev/null 2>&1; RC=$?
say "$DROP" "--stale-only" "…the hint naming --stale-only alone, so --this-checkout stays"
say "$RC" "0" "…and the command without the flags the hint names runs"
say "$(cmp -s "$D/.flight-rules/hooks/post-merge" "$H/git/post-merge" && echo replaced)" "replaced" "…and replaces the differing copy"
# "to replace it" undersold that: the full form replaces every copy that differs, adapted
# ones too (group A fix review round 2, D2).
say "$(grep -c 'to replace every copy that differs, adapted ones included' <<<"$OUT")" "1" "…a hint that says it replaces every differing copy, adapted ones included"
rm -rf "$D"

# Marked adapted, the project's own hook is accepted: a ⚠️ every session with no way to
# accept it was the complaint (review, 2026-10-12).
D=$(mkrepo); printf '# flight-rules: adapted\n# own change\n' >> "$D/.flight-rules/hooks/post-merge"
say "$(rc "$D")" "0" "a hook marked 'flight-rules: adapted' is not a problem"
say "$(has "$D" "post-merge adapted here (marked")" "0" "…and is reported as adapted"
say "$(has "$D" "post-merge differs from")" "1" "…not as differing"
say "$(has "$D" "to update:")" "1" "…and no sync command is printed for it"
rm -rf "$D"

# Indented, the comment line is still the mark.
D=$(mkrepo); printf '  # flight-rules: adapted\n' >> "$D/.flight-rules/hooks/post-merge"
say "$(has "$D" "post-merge adapted here")" "0" "an indented '# flight-rules: adapted' is the mark too"
rm -rf "$D"
# The phrase inside a line of code is not the mark: only a comment line of its own is.
D=$(mkrepo); printf 'echo "flight-rules: adapted"\n' >> "$D/.flight-rules/hooks/post-merge"
say "$(has "$D" "post-merge adapted here")" "1" "the phrase inside code is not the adapted mark"
say "$(has "$D" "post-merge differs from")" "0" "…the hook is reported as differing"
rm -rf "$D"

# The printed command, run as printed, keeps an unmarked adapted hook beside a stale one:
# the bare form overwrote it, and on screen the ⚠️ that would have warned is not shown
# (fix review, 2026-10-13 — reproduced).
D=$(mkrepo); mkcache "$D" commit-msg
cp "$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/commit-msg" "$D/.flight-rules/hooks/commit-msg"
echo "# my own tweak" >> "$D/.flight-rules/hooks/post-merge"
SYNC=$(run "$D" | grep -o 'to update: bash .*--from [^ ]* --stale-only' | sed 's/^to update: //' | head -1)
[ -n "$SYNC" ] && (cd "$D" && HOME="$D/fakehome" eval "$SYNC") >/dev/null 2>&1; say "$?" "0" "stale + adapted: the printed command runs"
say "$(cmp -s "$D/.flight-rules/hooks/commit-msg" "$H/git/commit-msg" && echo synced)" "synced" "…replaces the stale hook"
say "$(grep -c 'my own tweak' "$D/.flight-rules/hooks/post-merge")" "1" "…and keeps the adapted one"
rm -rf "$D"

# The missing-hook line already gives a cp; the sync command covers it too.
D=$(mkrepo); rm "$D/.flight-rules/hooks/pre-commit"
say "$(has "$D" "to update: bash")" "0" "a missing hook also prints the sync command"
rm -rf "$D"

# install.sh is synced with the hooks, so a stale copy is named too; 0.26.0 changed
# only it, and under HOOK_SYNC=report nothing said so (#90). It guards nothing, so a
# warning. mkrepo copies no install.sh: missing is a project that never had one.
D=$(mkrepo); mkcache "$D" install.sh
cp "$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/install.sh" "$D/.flight-rules/hooks/install.sh"
say "$(rc "$D")" "0" "a stale install.sh is a warning, not a problem"
say "$(has "$D" "install.sh is the flight-rules 0.0.1 copy")" "0" "…naming the release it came from"
SYNC=$(run "$D" | grep -o 'to update: bash .*--from [^ ]* --stale-only' | sed 's/^to update: //' | head -1)
say "$([ -n "$SYNC" ] && echo yes)" "yes" "…and printing the sync command"
(cd "$D" && HOME="$D/fakehome" eval "$SYNC") >/dev/null 2>&1
say "$(cmp -s "$D/.flight-rules/hooks/install.sh" "$H/git/install.sh" && echo synced)" "synced" "…which, run as printed, updates it"
say "$(run "$D" | grep -c -e 'install.sh is the' -e 'to update:')" "0" "…after which neither line is printed"
say "$(rc "$D")" "0" "…and doctor passes"
rm -rf "$D"
D=$(mkrepo); { cat "$H/git/install.sh"; echo "# own change"; } > "$D/.flight-rules/hooks/install.sh"
say "$(has "$D" "⚠️  install.sh differs from this flight-rules' copy")" "0" "an install.sh matching no release is named as differing"
printf '# flight-rules: adapted\n' >> "$D/.flight-rules/hooks/install.sh"
say "$(run "$D" | grep -c -e 'install.sh differs' -e 'to update:')" "0" "…and, marked adapted, is not"
say "$(rc "$D")" "0" "…with doctor passing"
rm -rf "$D"
# A project's own installer in the hooks directory — no flight-rules marker — is not
# flight-rules' to report: the printed hint would have replaced it (batch review,
# 2026-10-21). The ✅ for the hooks in the same run shows doctor got that far.
D=$(mkrepo); printf '#!/bin/sh\ngit config core.hooksPath .flight-rules/hooks\n' > "$D/.flight-rules/hooks/install.sh"
say "$(run "$D" | grep -c -e 'install.sh' -e 'to update:')" "0" "a project's own install.sh (no marker) is not reported"
say "$(run "$D" | grep -c 'pre-commit installed and executable')" "1" "…in a run that checked the hooks"
say "$(rc "$D")" "0" "…and doctor passes"
rm -rf "$D"
# …including one that follows the playbook's own advice and sets merge.ff, which every
# flight-rules project is told to do: merge.ff was the marker, and named it (second
# review, 2026-10-21).
D=$(mkrepo); printf '#!/bin/sh\ngit config core.hooksPath .flight-rules/hooks\ngit config merge.ff false\n' > "$D/.flight-rules/hooks/install.sh"
say "$(run "$D" | grep -c -e 'install.sh' -e 'to update:')" "0" "a project's own install.sh that sets merge.ff is not reported"
say "$(run "$D" | grep -c 'pre-commit installed and executable')" "1" "…in a run that checked the hooks"
rm -rf "$D"
# An install.sh doctor cannot read is said, not skipped: grep's error read as "no
# marker" and the file went unmentioned (second review, 2026-10-21). As root, chmod
# 000 blocks nothing, so the case would pass without testing anything: it says so.
D=$(mkrepo); { cat "$H/git/install.sh"; echo "# own change"; } > "$D/.flight-rules/hooks/install.sh"
chmod 000 "$D/.flight-rules/hooks/install.sh"
if [ -r "$D/.flight-rules/hooks/install.sh" ]; then
  echo "  ⏭️  an unreadable install.sh: skipped — running as root, chmod 000 does not block the read"
else
  say "$(has "$D" "install.sh is unreadable")" "0" "an unreadable install.sh is named, not skipped"
  say "$(rc "$D")" "0" "…as a warning"
fi
chmod 644 "$D/.flight-rules/hooks/install.sh"
rm -rf "$D"
# A grep that errors rather than answering is a check that could not run — not "no
# marker", which left the file unmentioned (third review, E12). It is reachable only by
# a race or an I/O error after the readability test, so a grep on PATH fails it here.
D=$(mkrepo); { cat "$H/git/install.sh"; echo "# own change"; } > "$D/.flight-rules/hooks/install.sh"
SHIM=$(tmpd); REAL_GREP=$(command -v grep)
printf '#!/bin/sh\nfor a; do last=$a; done\ncase "$last" in */.flight-rules/hooks/install.sh) case "$*" in *-qF*) exit 2 ;; esac ;; esac\nexec %s "$@"\n' "$REAL_GREP" > "$SHIM/grep"
chmod +x "$SHIM/grep"
OUT=$(cd "$D" && HOME="$D/fakehome" PATH="$SHIM:$PATH" bash "$DOCTOR" 2>&1); RC=$?
say "$RC" "0" "a marker grep that errors: doctor exits 0"
say "$(grep -c 'install.sh could not be read (grep exited 2) — could not check it' <<<"$OUT")" "1" "…and says install.sh could not be checked"
say "$(grep -c 'pre-commit installed and executable' <<<"$OUT")" "1" "…in a run that checked the hooks"
rm -rf "$D" "$SHIM"
# Missing: noted on the full report with the cp that restores it, not in the daily
# --problems-only one — nothing needs it, and a project may have removed it on purpose
# (owner, 2026-10-21). mkrepo copies no install.sh.
D=$(mkrepo)
say "$(has "$D" "install.sh is not in .flight-rules/hooks — nothing needs it to run the hooks; to restore it, on a branch: cp")" "0" "a missing install.sh is noted, with the cp that restores it"
# Paired with a problem the same run reports, so an empty --problems-only from a doctor
# that died is not read as "install.sh not mentioned" (fix review, F13).
chmod -x "$D/.flight-rules/hooks/post-merge"
P=$( (cd "$D" && HOME="$D/fakehome" bash "$DOCTOR" --problems-only 2>&1) ); RC=$?
say "$RC" "1" "…--problems-only, beside a hook that is not executable: exits 1"
say "$(grep -c 'post-merge is not executable' <<<"$P")" "1" "…and reports that hook"
say "$(grep -c 'install.sh' <<<"$P")" "0" "…but not the missing install.sh"
chmod +x "$D/.flight-rules/hooks/post-merge"
CMD=$(run "$D" | grep -o 'to restore it, on a branch: .*' | sed 's/^to restore it, on a branch: //')
(cd "$D" && eval "$CMD")
say "$(cmp -s "$D/.flight-rules/hooks/install.sh" "$H/git/install.sh" && echo restored)" "restored" "…and the cp, run as printed, restores it"
rm -rf "$D"
# From a worktree whose hooks are in the main checkout (an absolute core.hooksPath), the
# cp restores this worktree's copy: into the main checkout it was an untracked file a
# later merge bringing install.sh in refused to overwrite (fix review, F9).
D=$(mkrepo); git -C "$D" add -A && git -C "$D" commit -qm base --no-verify
git -C "$D" config core.hooksPath "$D/.flight-rules/hooks"
git -C "$D" worktree add -q "$D/.flight-rules/worktrees/wt" -b feature/wt 2>/dev/null || die "could not add a worktree in $D"
W="$D/.flight-rules/worktrees/wt"; mkdir -p "$W/fakehome"
CMD=$(run "$W" | grep -o 'to restore it, on a branch: .*' | sed 's/^to restore it, on a branch: //')
say "$([ -n "$CMD" ] && echo printed)" "printed" "from a worktree, hooks in the main checkout: the cp is printed"
(cd "$W" && eval "$CMD")
say "$(cmp -s "$W/.flight-rules/hooks/install.sh" "$H/git/install.sh" && echo restored)" "restored" "…and, run as printed, restores this worktree's copy"
say "$([ -e "$D/.flight-rules/hooks/install.sh" ] && echo written || echo untouched)" "untouched" "…not the main checkout's"
rm -rf "$D"
# …but when the hooks directory is untracked in the main checkout, this worktree has none,
# and the cp keeps the main checkout's path: redirected, it failed (group A fix review, F9).
D=$(mkrepo); echo base > "$D/f"; git -C "$D" add f && git -C "$D" commit -qm base --no-verify
git -C "$D" config core.hooksPath "$D/.flight-rules/hooks"
git -C "$D" worktree add -q "$D/.flight-rules/worktrees/wt" -b feature/wt 2>/dev/null || die "could not add a worktree in $D"
W="$D/.flight-rules/worktrees/wt"; mkdir -p "$W/fakehome"
CMD=$(run "$W" | grep -o 'to restore it, on a branch: .*' | sed 's/^to restore it, on a branch: //')
say "$([ -n "$CMD" ] && echo printed)" "printed" "from a worktree, hooks untracked in the main checkout: the cp is printed"
(cd "$W" && eval "$CMD") 2>/dev/null; RC=$?
say "$RC" "0" "…and, run as printed, succeeds"
say "$(cmp -s "$D/.flight-rules/hooks/install.sh" "$H/git/install.sh" && echo restored)" "restored" "…restoring the main checkout's copy, the only one there is"
rm -rf "$D"
# …nor when the worktree's hooks directory is a link to the main checkout's: redirected,
# the cp printed this worktree's path and wrote through the link into the main checkout
# (group A fix review round 2, F0). It names the main checkout's path instead.
D=$(mkrepo); git -C "$D" add -A && git -C "$D" commit -qm base --no-verify
git -C "$D" config core.hooksPath "$D/.flight-rules/hooks"
git -C "$D" worktree add -q "$D/.flight-rules/worktrees/wt" -b feature/wt 2>/dev/null || die "could not add a worktree in $D"
W="$D/.flight-rules/worktrees/wt"; mkdir -p "$W/fakehome"
mv "$W/.flight-rules/hooks" "$W/.flight-rules/hooks.real"; ln -s "$D/.flight-rules/hooks" "$W/.flight-rules/hooks"
CMD=$(run "$W" | grep -o 'to restore it, on a branch: .*' | sed 's/^to restore it, on a branch: //')
say "$([ -n "$CMD" ] && echo printed)" "printed" "from a worktree whose hooks directory links to the main checkout's: the cp is printed"
say "${CMD##* }" "$(printf '%q' "$(cd "$D" && pwd -P)/.flight-rules/hooks/install.sh")" "…naming the main checkout's path, where it writes"
rm "$W/.flight-rules/hooks"; rm -rf "$D"
# …nor through a link and a .. in core.hooksPath: plain cd read wt/lnk/.. by name, as the
# worktree, so the printed cp kept the link path, which the kernel walks into the main
# checkout (second fix review: every cd that judges a path is cd -P).
D=$(mkrepo); git -C "$D" add -A && git -C "$D" commit -qm base --no-verify
git -C "$D" worktree add -q "$D/.flight-rules/worktrees/wt" -b feature/wt 2>/dev/null || die "could not add a worktree in $D"
W="$D/.flight-rules/worktrees/wt"; mkdir -p "$W/fakehome"; ln -s "$D/.flight-rules" "$W/lnk" || die "could not link $W/lnk"
[ -d "$W/.flight-rules/hooks" ] || die "the worktree has no .flight-rules/hooks: the case below tests nothing"
git -C "$D" config core.hooksPath "$W/lnk/../.flight-rules/hooks"
CMD=$(run "$W" | grep -o 'to restore it, on a branch: .*' | sed 's/^to restore it, on a branch: //')
say "$([ -n "$CMD" ] && echo printed)" "printed" "core.hooksPath through a link and ..: the cp is printed"
say "${CMD##* }" "$(printf '%q' "$(cd "$W" && pwd -P)/.flight-rules/hooks/install.sh")" "…naming this worktree's copy, not the link path into the main checkout"
rm "$W/lnk"; rm -rf "$D"
# From the main checkout whose hooks path is a worktree's, git answers --git-common-dir
# relative (.git), and an exported CDPATH holding `.` made `cd .git` print where it
# went: the repos never compared equal, and the cp named the worktree's copy, an
# untracked file written into another checkout (#90's F9, by another road; third fix
# review — the first try at this test ran from a worktree, where git answers an
# absolute path, and could not fail).
D=$(mkrepo); git -C "$D" add -A && git -C "$D" commit -qm base --no-verify
git -C "$D" worktree add -q "$D/.flight-rules/worktrees/wt" -b feature/wt 2>/dev/null || die "could not add a worktree in $D"
git -C "$D" config core.hooksPath "$D/.flight-rules/worktrees/wt/.flight-rules/hooks"; mkdir -p "$D/fakehome"
[ -e "$D/.flight-rules/worktrees/wt/.flight-rules/hooks/install.sh" ] && die "the worktree has an install.sh: the case below tests nothing"
CMD=$(CDPATH=.:/usr run "$D" | grep -o 'to restore it, on a branch: .*' | sed 's/^to restore it, on a branch: //')
say "${CMD##* }" "$(printf '%q' "$(cd "$D" && pwd -P)/.flight-rules/hooks/install.sh")" "CDPATH=.:/usr, the main checkout's hooks path in a worktree: the cp names this checkout's copy"
rm -rf "$D"
# An unreadable hook could not be checked: said so, not "may be a stub", and grep's
# error is not on screen (fix review, F15). Git cannot run it, so it is a problem.
D=$(mkrepo); chmod 111 "$D/.flight-rules/hooks/post-merge"
if [ -r "$D/.flight-rules/hooks/post-merge" ]; then
  echo "  ⏭️  an unreadable hook: skipped — running as root, chmod 111 does not block the read"
else
  OUT=$(run "$D")
  say "$(head -1 <<<"$OUT")" "1" "an unreadable hook: a problem"
  say "$(grep -c 'post-merge is unreadable — git cannot run it' <<<"$OUT")" "1" "…said to be unreadable"
  say "$(grep -c 'so what it checks does not happen and a command it gates fails' <<<"$OUT")" "1" "…in words true of post-merge too, whose status git ignores"
  say "$(grep -c 'post-merge does not look like' <<<"$OUT")" "0" "…not called a stub"
  say "$(grep -ci 'permission denied' <<<"$OUT")" "0" "…with no grep error on screen"
fi
chmod 755 "$D/.flight-rules/hooks/post-merge"; rm -rf "$D"
# A marker grep that errors on a readable hook: could not check it, not a stub.
D=$(mkrepo)
SHIM=$(tmpd); REAL_GREP=$(command -v grep)
printf '#!/bin/sh\nfor a; do last=$a; done\ncase "$last" in */.flight-rules/hooks/post-merge) case "$1" in -q) exit 2 ;; esac ;; esac\nexec %s "$@"\n' "$REAL_GREP" > "$SHIM/grep"
chmod +x "$SHIM/grep"
OUT=$(cd "$D" && HOME="$D/fakehome" PATH="$SHIM:$PATH" bash "$DOCTOR" 2>&1); RC=$?
say "$RC" "0" "a hook marker grep that errors: a warning, doctor exits 0"
say "$(grep -c 'post-merge could not be read (grep exited 2) — could not check it' <<<"$OUT")" "1" "…said as could not check"
say "$(grep -c 'post-merge does not look like' <<<"$OUT")" "0" "…not called a stub"
say "$(grep -c 'pre-commit installed and executable' <<<"$OUT")" "1" "…in a run that checked the other hooks"
rm -rf "$D" "$SHIM"
# The adapted-mark grep that errors: could not check it either, not "not adapted" with
# grep's error on screen (group A fix review, F13).
D=$(mkrepo)
SHIM=$(tmpd); REAL_GREP=$(command -v grep)
printf '#!/bin/sh\nfor a; do last=$a; done\ncase "$last" in */.flight-rules/hooks/post-merge) case "$1" in -qE) echo "grep: shim I/O error" >&2; exit 2 ;; esac ;; esac\nexec %s "$@"\n' "$REAL_GREP" > "$SHIM/grep"
chmod +x "$SHIM/grep"
OUT=$(cd "$D" && HOME="$D/fakehome" PATH="$SHIM:$PATH" bash "$DOCTOR" 2>&1); RC=$?
say "$RC" "0" "an adapted-mark grep that errors: a warning, doctor exits 0"
say "$(grep -c 'post-merge could not be read (grep exited 2) — could not check it' <<<"$OUT")" "1" "…said as could not check"
say "$(grep -c 'shim I/O error' <<<"$OUT")" "0" "…with grep's error not on screen"
say "$(grep -c 'pre-commit installed and executable' <<<"$OUT")" "1" "…in a run that checked the other hooks"
rm -rf "$D" "$SHIM"
# The same for install.sh's adapted-mark grep, which F13 missed (group A fix review
# round 2, F1): an error read as "not marked", with grep's error on screen.
D=$(mkrepo); { cat "$H/git/install.sh"; echo "# own change"; } > "$D/.flight-rules/hooks/install.sh"
SHIM=$(tmpd); REAL_GREP=$(command -v grep)
printf '#!/bin/sh\nfor a; do last=$a; done\ncase "$last" in */.flight-rules/hooks/install.sh) case "$1" in -qE) echo "grep: shim I/O error" >&2; exit 2 ;; esac ;; esac\nexec %s "$@"\n' "$REAL_GREP" > "$SHIM/grep"
chmod +x "$SHIM/grep"
OUT=$(cd "$D" && HOME="$D/fakehome" PATH="$SHIM:$PATH" bash "$DOCTOR" 2>&1); RC=$?
say "$RC" "0" "install.sh's adapted-mark grep that errors: doctor exits 0"
say "$(grep -c 'install.sh could not be read (grep exited 2) — could not check it' <<<"$OUT")" "1" "…said as could not check"
say "$(grep -c 'shim I/O error' <<<"$OUT")" "0" "…with grep's error not on screen"
say "$(grep -c 'pre-commit installed and executable' <<<"$OUT")" "1" "…in a run that checked the hooks"
rm -rf "$D" "$SHIM"
# A copy identical to this version's own release, while this checkout's differs: the
# development case, worded as such rather than as an old release.
D=$(mkrepo); _sv=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$H/../.claude-plugin/plugin.json" | head -1)
mkdir -p "$D/fakehome/.claude/plugins/cache/mp/flight-rules/$_sv/hooks/git"
{ cat "$H/git/install.sh"; echo "# released $_sv"; } > "$D/fakehome/.claude/plugins/cache/mp/flight-rules/$_sv/hooks/git/install.sh"
cp "$D/fakehome/.claude/plugins/cache/mp/flight-rules/$_sv/hooks/git/install.sh" "$D/.flight-rules/hooks/install.sh"
say "$(has "$D" "install.sh is the released $_sv copy, and this flight-rules checkout carries unreleased changes")" "0" "an install.sh of this version's release, under a changed checkout, is named as such"
say "$(has "$D" "to update: bash")" "0" "…with the sync command"
say "$(rc "$D")" "0" "…as a warning"
rm -rf "$D"
D=$(mkrepo)
cp "$H/git/install.sh" "$D/.flight-rules/hooks/"
say "$(run "$D" | grep -c -e 'install.sh' -e 'to update:')" "0" "a current install.sh is not reported"
say "$(rc "$D")" "0" "…and doctor passes"
rm -rf "$D"

echo "A later release's copy is not behind (fix review, 2026-10-24):"
# Run from an older plugin, doctor called a newer release's commit-msg "behind" with a
# ❌, and its sync hint led to a full install that downgraded it. Here the doctor is
# 0.0.5's, the project holds 0.0.9's commit-msg and install.sh.
say "$(sed -n '/^newer_than() {/,/^}/p' "$DOCTOR")" "$(sed -n '/^newer_than() {/,/^}/p' "$H/git/install.sh")" "newer_than is install.sh's, verbatim"
P=$(tmpd); mkdir -p "$P/.claude-plugin" "$P/hooks"; cp -R "$H/git" "$P/hooks/git"; cp "$DOCTOR" "$P/hooks/"
printf '{ "name": "flight-rules", "version": "0.0.5" }\n' > "$P/.claude-plugin/plugin.json"
D=$(mkrepo); N="$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.9/hooks/git"; mkdir -p "$N"
for h in commit-msg install.sh; do { cat "$H/git/$h"; echo "# flight-rules 0.0.9"; } > "$N/$h"; cp "$N/$h" "$D/.flight-rules/hooks/$h"; done
OUT=$(cd "$D" && HOME="$D/fakehome" bash "$P/hooks/flight-rules-doctor.sh" 2>&1); RC=$?
say "$RC" "0" "newer copies only: doctor exits 0"
say "$(grep -c '⚠️  commit-msg is the flight-rules 0.0.9 copy, newer than this flight-rules (0.0.5) — a session on 0.0.9 wrote it; start a new session' <<<"$OUT")" "1" "…names the newer commit-msg as a warning"
say "$(grep -c '⚠️  install.sh is the flight-rules 0.0.9 copy, newer than this flight-rules (0.0.5)' <<<"$OUT")" "1" "…and the newer install.sh"
say "$(grep -c -e '❌' -e 'behind' -e 'to update:' -e 're-run without' <<<"$OUT")" "0" "…with no ❌, no 'behind', and no sync hint"
say "$(grep -c 'pre-commit installed and executable' <<<"$OUT")" "1" "…in a run that checked the hooks"
# An older copy beside them is still behind, with the hint: the newer case silences only itself.
mkcache "$D" pre-rebase; cp "$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/pre-rebase" "$D/.flight-rules/hooks/pre-rebase"
OUT=$(cd "$D" && HOME="$D/fakehome" bash "$P/hooks/flight-rules-doctor.sh" 2>&1); RC=$?
say "$RC" "1" "an older pre-rebase beside them: a problem"
say "$(grep -c '❌ pre-rebase is the flight-rules 0.0.1 copy' <<<"$OUT")$(grep -c 'to update:' <<<"$OUT")" "11" "…named behind, with the sync hint"
say "$(grep -c '❌ commit-msg' <<<"$OUT")" "0" "…while the newer commit-msg stays a warning"
rm -rf "$D" "$P"

echo "The conf — typos and bad values must not pass silently:"
D=$(mkrepo); printf 'HOOK_SYNC=auto\n' >> "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "HOOK_SYNC=auto is a known key"
say "$(has "$D" "HOOK_SYNC=auto")" "0" "…and is reported"
say "$(has "$D" "unknown key")" "1" "…not as unknown"
printf 'HOOK_SYNC=yes\n' >> "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "HOOK_SYNC=yes is a warning, not a failure"
say "$(has "$D" "⚠️  HOOK_SYNC='yes' is neither auto nor report")" "0" "…saying what the values are"
rm -rf "$D"

# /dg's comic settings (owner, 2026-10-17): read by a skill, so a typo would only show as
# a comic that appears, or lands in a PR, against the project's wish.
D=$(mkrepo); printf 'DG_COMIC=never\nDG_COMIC_PR=always\n' >> "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "DG_COMIC and DG_COMIC_PR are known keys"
say "$(has "$D" "unknown key")" "1" "…not reported as unknown"
say "$(has "$D" "DG_COMIC=never")" "0" "…and each is reported"
say "$(has "$D" "DG_COMIC_PR=always")" "0" "…both of them"
printf 'DG_COMIC=sometimes\nDG_COMIC_PR=yes\n' >> "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "a bad comic value is a warning, not a failure"
say "$(has "$D" "⚠️  DG_COMIC='sometimes' is neither always nor never")" "0" "…naming DG_COMIC's values"
say "$(has "$D" "⚠️  DG_COMIC_PR='yes' is not never, ask or always")" "0" "…and DG_COMIC_PR's"
say "$(has "$D" "treats it as never and keeps the comic out of PRs")" "0" "…falling back to never, the opt-in default"
rm -rf "$D"

# /dg's round-2 wait (owner, 2026-10-18): a value the skill cannot read as minutes would
# silently become the default, so doctor names it.
D=$(mkrepo); printf 'OPEN_BRANCH_LIMIT=3\n' >> "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "OPEN_BRANCH_LIMIT is a known key"
say "$(has "$D" "OPEN_BRANCH_LIMIT=3")" "0" "…and is reported"
printf 'OPEN_BRANCH_LIMIT=lots\n' > "$D/.flight-rules/conf"
say "$(has "$D" "⚠️  OPEN_BRANCH_LIMIT='lots' is neither a positive whole number nor off")" "0" "…a value that is not a number is warned about"
printf 'OPEN_BRANCH_LIMIT=off\n' > "$D/.flight-rules/conf"
say "$(has "$D" "OPEN_BRANCH_LIMIT=off")" "0" "…off is accepted"
rm -rf "$D"
D=$(mkrepo); printf 'DG_WAIT_MINUTES=30\n' >> "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "DG_WAIT_MINUTES is a known key"
say "$(has "$D" "unknown key")" "1" "…not reported as unknown"
say "$(has "$D" "DG_WAIT_MINUTES=30")" "0" "…and is reported"
printf 'DG_WAIT_MINUTES=08\n' > "$D/.flight-rules/conf"
say "$(has "$D" "DG_WAIT_MINUTES=08")" "0" "…a leading zero is still minutes"
for v in 15m 0 -5 ''; do
  printf 'DG_WAIT_MINUTES=%s\n' "$v" > "$D/.flight-rules/conf"
  say "$(rc "$D")" "0" "DG_WAIT_MINUTES='$v' is a warning, not a failure"
  say "$(has "$D" "⚠️  DG_WAIT_MINUTES='$v' is not a positive whole number of minutes")" "0" "…naming the value '$v'"
  say "$(has "$D" "treats it as 15")" "0" "…and the default it falls back to"
done
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCH=^main$\n' > "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "unknown key is a warning, not a failure"
say "$(has "$D" "⚠️  .flight-rules/conf: unknown key 'PROTECTED_BRANCH'")" "0" "…and is named"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=^(main$\n' > "$D/.flight-rules/conf"
say "$(rc "$D")" "1" "invalid regex → problem"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=main\n' > "$D/.flight-rules/conf"
say "$(has "$D" "⚠️  PROTECTED_BRANCHES='main' is unanchored")" "0" "unanchored pattern → warning"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\n' > "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "PROTECTED_BRANCHES=off is allowed"
say "$(has "$D" "⚠️  PROTECTED_BRANCHES=off — no protected branches in the agent guard")" "0" "…with a warning naming the layers it stands down"
# It used to say "the branch policy is off", which is not what happens: pre-merge-commit,
# pre-rebase and the squash guard read PR_ONLY_BRANCHES directly and keep refusing local
# merges and rebases into a PR-only branch. A reader turning `off` on to work locally
# would have been told more was disabled than is.
say "$(has "$D" "PR_ONLY_BRANCHES still refuses")" "0" "…and says what it does NOT disable"
rm -rf "$D"

D=$(mkrepo); rm "$D/.flight-rules/conf"
say "$(rc "$D")" "0" "no conf at all is a warning only"
say "$(has "$D" "⚠️  .flight-rules/conf absent")" "0" "…named as one"
rm -rf "$D"

echo "PROTECTED_BRANCHES=off empties the note gate, and doctor says so:"
# The note gate's default set is DERIVED from PROTECTED_BRANCHES — "protected but not
# PR-only" — so turning protection off empties it. Measured 2026-09-13: a merge landed
# on an integration branch with no pre-merge-check note and no layer said a word. Only
# worth saying when the project integrates somewhere other than main; a trunk-only
# project has no note-gated branch either way.
D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\nINTEGRATION_BRANCH=dev\n' > "$D/.flight-rules/conf"
say "$(has "$D" "⚠️  …and with NOTE_GATED_BRANCHES unset, that empties the note gate")" "0" "off + a dev integration branch → warned"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\nINTEGRATION_BRANCH=main\n' > "$D/.flight-rules/conf"
say "$(has "$D" "empties the note gate")" "1" "off on a trunk-only project → not warned"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\nNOTE_GATED_BRANCHES=^dev$\nINTEGRATION_BRANCH=dev\n' > "$D/.flight-rules/conf"
say "$(has "$D" "empties the note gate")" "1" "NOTE_GATED_BRANCHES named → not warned"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=^(main|dev)$\nINTEGRATION_BRANCH=dev\n' > "$D/.flight-rules/conf"
say "$(has "$D" "empties the note gate")" "1" "policy on → not warned"
rm -rf "$D"

D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\nPR_ONLY_BRANCHES=^(main|dev)$\nINTEGRATION_BRANCH=dev\n' > "$D/.flight-rules/conf"
say "$(has "$D" "empties the note gate")" "1" "integration branch is PR-only → not warned, there is no gate to lose"
rm -rf "$D"
# Case-insensitively, as the hooks decide PR-only (#103 review).
D=$(mkrepo); printf 'PROTECTED_BRANCHES=off\nPR_ONLY_BRANCHES=^(MAIN|DEV)$\nINTEGRATION_BRANCH=dev\n' > "$D/.flight-rules/conf"
say "$(has "$D" "empties the note gate")" "1" "…matched case-insensitively, as the hooks match it"
rm -rf "$D"

echo "Guard wiring — once, not twice, not a stale copy:"
D=$(mkrepo); mkdir -p "$D/.claude" "$D/fakehome/.claude"
printf '{"enabledPlugins":{"flight-rules@flight-rules":true}}' > "$D/fakehome/.claude/settings.json"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash x/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
say "$(has "$D" "⚠️  the flight-rules plugin is enabled AND")" "0" "plugin + local wiring → double-fire warning"
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
say "$(has "$D" "⚠️  the flight-rules plugin is enabled AND")" "0" "plugin enabled in .claude/settings.json + local wiring in the same file → double-fire warning"
rm -rf "$D"

# settings.local.json is git-ignored, so it exists only in the checkout that wrote it,
# and Claude Code applies the MAIN worktree's to a session in any linked one (probe,
# 2026-10-19). doctor read only the worktree's own and warned "no agent guard" in every
# worktree of a project that enables the plugin there (#88).
D=$(mkrepo); mkdir -p "$D/.claude" "$D/fakehome/.claude"
printf '{}' > "$D/fakehome/.claude/settings.json"
printf '{"enabledPlugins":{"flight-rules@flight-rules":true}}' > "$D/.claude/settings.local.json"
git -C "$D" commit -q --allow-empty -m init
git -C "$D" worktree add -q "$D/.flight-rules/worktrees/w" -b w || die "worktree add failed in $D"
mkdir -p "$D/.flight-rules/worktrees/w/fakehome/.claude"; printf '{}' > "$D/.flight-rules/worktrees/w/fakehome/.claude/settings.json"
[ -e "$D/.flight-rules/worktrees/w/.claude/settings.local.json" ] && die "the fixture's worktree has its own settings.local.json"
say "$(has "$D/.flight-rules/worktrees/w" "agent guard via the plugin")" "0" "a linked worktree: plugin enabled in the main checkout's settings.local.json → wired"
say "$(has "$D/.flight-rules/worktrees/w" "no agent guard wired")" "1" "…and not declared absent"
rm -rf "$D"

D=$(mkrepo); mkdir -p "$D/.claude/" "$D/.flight-rules/hooks/agent"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash .flight-rules/hooks/agent/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
printf '#!/bin/bash\n[[ "$COMMAND" == *"git commit"* ]]\n' > "$D/.flight-rules/hooks/agent/pre-commit-check.sh"
say "$(rc "$D")" "1" "pre-conf copy of the guard → problem"
say "$(has "$D" "pre-conf copy")" "0" "…identified as such"
rm -rf "$D"
# Where such a copy actually is: it predates 0.29.0, so it was committed in .ai/ (D2).
D=$(mkrepo); mkdir -p "$D/.claude/" "$D/.ai/hooks/agent"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash .ai/hooks/agent/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
printf '#!/bin/bash\n[[ "$COMMAND" == *"git commit"* ]]\n' > "$D/.ai/hooks/agent/pre-commit-check.sh"
say "$(rc "$D")" "1" "pre-conf copy of the guard in .ai/hooks/agent/ → problem"
say "$(has "$D" ".ai/hooks/agent/pre-commit-check.sh is a pre-conf copy")" "0" "…named by where it is"
rm -rf "$D"

echo "--problems-only is silent on a healthy repo:"
D=$(mkrepo); rm "$D/.flight-rules/conf"; printf 'PROTECTED_BRANCHES=^main$\n' > "$D/.flight-rules/conf"
mkdir -p "$D/.claude" "$D/hooks/agent"; printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash hooks/agent/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
# The wired script has to be THERE: a healthy repo is one where the path resolves.
cp "$H/agent/pre-commit-check.sh" "$D/hooks/agent/pre-commit-check.sh"
OUT=$(cd "$D" && HOME="$D/fakehome" bash "$DOCTOR" --problems-only 2>&1); RC=$?
say "$(printf '%s' "$OUT" | grep -c .)" "0" "no output when nothing is wrong"
say "$RC" "0" "…and exits 0, so the silence is not a doctor that died"
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
say "$(has "$D" "⚠️  ~/.claude/commands/dg.md shadows flight-rules' /dg")" "0" "…a user command named like a plugin skill is named"
say "$(has "$D" "⚠️  ~/.claude/skills/diagnose/SKILL.md shadows flight-rules' /diagnose")" "0" "…so is a user skill"
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
say "$(has "$D" "⚠️  .claude/commands/pre-merge-check.md shadows flight-rules' /pre-merge-check")" "0" "…a copy that names flight-rules:<name> in prose still shadows"
say "$(has "$D" "⚠️  .claude/commands/docs-lint.md shadows flight-rules' /docs-lint")" "0" "…so does one that names skills/<name>/SKILL.md in prose"
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

echo "What a project still on .ai/ is told (#153):"
D=$(mkrepo); mkdir -p "$D/.ai"; mv "$D/.flight-rules/conf" "$D/.ai/flight-rules.conf" || die "could not move the conf to its old place"
printf 'PROTECTD_BRANCHES=^main$\n' >> "$D/.ai/flight-rules.conf"
OUT=$(run "$D")
# A copy, not a git mv: a 0.28.0 hook or plugin reads only the old file, and moved, it
# fell back to its defaults without a word — a custom pattern undone (V3, reproduced).
say "$(grep -c 'the conf is at .ai/flight-rules.conf, its place before 0.29.0 — still read there. To move it, on a branch: mkdir -p .flight-rules && cp .ai/flight-rules.conf .flight-rules/conf, and commit both. Leave the old file for now: a 0.28.0 hook or plugin reads only that one' <<<"$OUT")$(grep -c 'git mv' <<<"$OUT")" "10" "the conf in its old place: said, with the copy, not a move"
say "$(grep -c ".ai/flight-rules.conf: unknown key 'PROTECTD_BRANCHES'" <<<"$OUT")" "1" "…and it is the file that is checked"
printf 'PROTECTED_BRANCHES=^main$\n' > "$D/.flight-rules/conf"
OUT=$(run "$D")
say "$(grep -c '.ai/flight-rules.conf is not read: .flight-rules/conf is there, and wins' <<<"$OUT")$(grep -c 'unknown key' <<<"$OUT")" "10" "a conf in both places: the old one is said not to be read, and is not"
say "$(grep -c 'Only a 0.28.0 hook or plugin reads the old one; once every committed hook copy is 0.29.0'"'"'s and every clone'"'"'s plugin is on 0.29.0, on a branch: git rm .ai/flight-rules.conf' <<<"$OUT")$(grep -c 'the two files differ, so a 0.28.0 reader follows another policy than this one' <<<"$OUT")" "11" "…who still reads it, when to remove it, and that the two differ"
cp "$D/.flight-rules/conf" "$D/.ai/flight-rules.conf"
OUT=$(run "$D")
say "$(grep -c 'Only a 0.28.0 hook or plugin reads the old one' <<<"$OUT")$(grep -c 'differ' <<<"$OUT")" "10" "…and the same two files: no word of a difference"
rm "$D/.ai/flight-rules.conf"
OUT=$(run "$D")
# By its sentences, not by ".ai/": a path the doctor prints may hold that itself.
say "$(head -1 <<<"$OUT")$(grep -c 'flight-rules\.conf\|WORKTREE_DIR is not set\|the hooks moved' <<<"$OUT")" "00" "a project on the new places: exit 0, and no word of the old ones"
# The new default folder has no fallback (owner, 2026-11-11): said whenever .gitignore
# does not cover it, not only while .ai/worktrees/ held worktrees (D1).
NOT_IGNORED='WORKTREE_DIR is not set, so new worktrees go to .flight-rules/worktrees/, which .gitignore does not cover. On a branch, add the line .flight-rules/worktrees/ to .gitignore'
rm "$D/.gitignore"
OUT=$(run "$D")
say "$(head -1 <<<"$OUT")$(grep -c "$NOT_IGNORED" <<<"$OUT")$(grep -c 'stay where they are' <<<"$OUT")" "010" "the new worktree folder not ignored, and no old one: said, with the line to add"
mkdir -p "$D/.ai/worktrees/x"
OUT=$(run "$D")
say "$(grep -c "$NOT_IGNORED" <<<"$OUT")$(grep -c 'The worktrees in .ai/worktrees/ stay where they are until they are removed' <<<"$OUT")" "11" "…with worktrees in the old folder: said, and that those stay"
printf '.flight-rules/\n' > "$D/.gitignore"
OUT=$(run "$D")
say "$(head -1 <<<"$OUT")$(grep -c 'WORKTREE_DIR is not set' <<<"$OUT")" "00" "…and nothing once .gitignore covers it, here through its parent"
rm "$D/.gitignore"; printf 'WORKTREE_DIR=.ai/worktrees\n' >> "$D/.flight-rules/conf"
OUT=$(run "$D")
say "$(head -1 <<<"$OUT")$(grep -c 'WORKTREE_DIR is not set' <<<"$OUT")" "00" "…nor once WORKTREE_DIR is set"
# Set empty, it is not set: the hooks read the default (V17), where the line's mere
# presence silenced this.
printf 'PROTECTED_BRANCHES=^main$\nWORKTREE_DIR=\n' > "$D/.flight-rules/conf"
OUT=$(run "$D")
say "$(grep -c "$NOT_IGNORED" <<<"$OUT")" "1" "…but WORKTREE_DIR= set empty: said, as for unset"
rm -rf "$D"
# A repository that never adopted flight-rules — no conf, no flight-rules hook where
# core.hooksPath points — is not told where its worktrees go: the plugin met it in every
# session and said so every day (V17).
D=$(tmpd); git -C "$D" init -q -b main || die "git init failed in $D"
OUT=$(run "$D")
say "$(grep -c 'WORKTREE_DIR is not set' <<<"$OUT")$(grep -c 'problem(s),' <<<"$OUT")" "01" "a repository that never adopted flight-rules: no word of the worktree folder"
mkdir -p "$D/.ai"; printf 'PROTECTED_BRANCHES=^main$\n' > "$D/.ai/flight-rules.conf"
OUT=$(run "$D")
say "$(grep -c "$NOT_IGNORED" <<<"$OUT")" "1" "…one with a conf, if only in the old place, is told"
rm "$D/.ai/flight-rules.conf"; cp -R "$H/git" "$D/hk" && git -C "$D" config core.hooksPath hk || die "could not wire hooks in $D"
OUT=$(run "$D")
say "$(grep -c "$NOT_IGNORED" <<<"$OUT")" "1" "…and so is one with no conf whose core.hooksPath runs flight-rules' hooks"
rm -rf "$D"
# The hook copies: committed in the old folder, a fresh clone is pointed at those; a
# clone that pulled the move still names the old folder, and git then runs no hooks.
D=$(mkrepo); mv "$D/.flight-rules/hooks" "$D/.ai-hooks-tmp"; mkdir -p "$D/.ai"; mv "$D/.ai-hooks-tmp" "$D/.ai/hooks" || die "could not move the hooks to their old place"
git -C "$D" config --unset core.hooksPath
OUT=$(run "$D")
say "$(grep -c 'not running the hooks committed in .ai/hooks/' <<<"$OUT")" "1" "hooks committed in .ai/hooks, core.hooksPath unset: named as the ones to wire"
git -C "$D" config core.hooksPath .ai/hooks; mkdir -p "$D/.flight-rules"; mv "$D/.ai/hooks" "$D/.flight-rules/hooks" || die "could not move the hooks to their new place"
OUT=$(run "$D")
say "$(grep -c 'core.hooksPath=.ai/hooks but that directory does not exist — git runs NO hooks — the hooks moved to .flight-rules/hooks/: git config core.hooksPath .flight-rules/hooks' <<<"$OUT")" "1" "core.hooksPath still naming .ai/hooks after the move: said, with the command"
# Not only when the old folder is gone and spelled exactly: a stray file keeping it, or
# half the hooks left there, drew a `cp … .ai/hooks/` per hook (D3).
MOVED='the folder before 0.29.0, but the hooks moved to .flight-rules/hooks/ — git runs whatever is left in the old one. To run the moved ones: git config core.hooksPath .flight-rules/hooks'
mkdir -p "$D/.ai/hooks"; : > "$D/.ai/hooks/.DS_Store"
OUT=$(run "$D")
say "$(head -1 <<<"$OUT")$(grep -c "core.hooksPath=.ai/hooks, $MOVED" <<<"$OUT")$(grep -c 'missing from\|\.ai/hooks/ &&\|\.ai/hooks/'"'"' &&' <<<"$OUT")" "110" "the old folder still there with only a stray file: the move said, and no copy back into it"
git -C "$D" config core.hooksPath ./.ai/hooks/
OUT=$(run "$D")
say "$(grep -c "core.hooksPath=./.ai/hooks/, $MOVED" <<<"$OUT")" "1" "…spelled ./.ai/hooks/: the same"
rm -rf "$D/.ai/hooks"
OUT=$(run "$D")
say "$(grep -c 'core.hooksPath=./.ai/hooks/ but that directory does not exist — git runs NO hooks — the hooks moved' <<<"$OUT")" "1" "…and spelled so with the old folder gone: the move said"
say "$(grep -c 'git runs NO hooks' <<<"$OUT")$(grep -c 'commit-msg installed and executable' <<<"$OUT")" "11" "…once, and the moved hooks checked in the new folder"
git -C "$D" config core.hooksPath .ai/hooks; mkdir -p "$D/.ai/hooks"
mv "$D/.flight-rules/hooks/pre-merge-commit" "$D/.flight-rules/hooks/commit-msg" "$D/.ai/hooks/" || die "could not split the hooks in $D"
OUT=$(run "$D")
# Git runs the old folder, so the hooks left there are checked there; the ones gone from
# it are not named, in either folder: the move's ❌ and its command cover them (R1, #160).
say "$(head -1 <<<"$OUT")$(grep -c "core.hooksPath=.ai/hooks, $MOVED" <<<"$OUT")$(grep -c 'missing from' <<<"$OUT")$(grep -c 'cp .*\.ai/hooks/' <<<"$OUT")" "1100" "half moved: the move said, no hook named missing, and no cp into the old folder"
say "$(grep -c 'pre-merge-commit installed and executable' <<<"$OUT")$(grep -c 'commit-msg installed and executable' <<<"$OUT")$(grep -c 'pre-rebase installed and executable' <<<"$OUT")" "110" "…the hooks left in the old folder checked there, where git runs them"
rm -rf "$D"
# Both folders full, core.hooksPath still on the old one — the documented mid-move
# state. Checked in the new folder, a stub left in the old one, which git runs, passed as
# installed (R1, #160).
D=$(mkrepo); mkdir -p "$D/.ai/hooks"; cp -p "$D"/.flight-rules/hooks/* "$D/.ai/hooks/" || die "could not copy the hooks to the old folder in $D"
git -C "$D" config core.hooksPath .ai/hooks
printf '#!/bin/sh\nexit 0\n' > "$D/.ai/hooks/commit-msg"
echo '# a tweak' >> "$D/.ai/hooks/post-merge"
OUT=$(run "$D")
say "$(head -1 <<<"$OUT")$(grep -c "core.hooksPath=.ai/hooks, $MOVED" <<<"$OUT")$(grep -c 'commit-msg does not look like the flight-rules hook' <<<"$OUT")$(grep -c 'commit-msg installed and executable' <<<"$OUT")" "1110" "both folders full, still on the old one: the move said, and the stub in the old folder named"
say "$(grep -c 'post-merge differs from' <<<"$OUT")$(grep -c 'to update:' <<<"$OUT")$(grep -c 'cp .*\.ai/hooks/' <<<"$OUT")" "100" "…a changed copy there named, with no sync and no cp into the old folder offered"
rm -rf "$D"
# core.hooksPath is one setting for a clone and all its worktrees, and a relative value
# resolves in each. Judged from a worktree holding the unmerged copy, the bare command,
# followed, left the main checkout running no hooks: a staged AWS key committed with
# exit 0 (0.29.0 release review, second pass, V1).
D=$(mkrepo); mv "$D/.flight-rules/hooks" "$D/.ai-hooks-tmp"; mkdir -p "$D/.ai"; mv "$D/.ai-hooks-tmp" "$D/.ai/hooks" || die "could not move the hooks to their old place"
git -C "$D" config core.hooksPath .ai/hooks
"${GN[@]}" -C "$D" add -A && "${GN[@]}" -C "$D" commit -qm base || die "could not commit the fixture in $D"
WT=$(tmpd); "${GN[@]}" -C "$D" worktree add -q "$WT/move" -b chore/move-hooks main || die "could not add a worktree to $D"
mkdir -p "$WT/move/.flight-rules" && cp -R "$WT/move/.ai/hooks" "$WT/move/.flight-rules/hooks" || die "could not copy the hooks in $WT/move"
OUT=$(run "$WT/move")
say "$(head -1 <<<"$OUT")$(grep -c 'git config core.hooksPath .flight-rules/hooks' <<<"$OUT")" "10" "a worktree ahead of the main checkout (the copy unmerged): no command to change core.hooksPath"
say "$(grep -c "one setting for every checkout of this clone, and these have no copy in .flight-rules/hooks/ yet: $D" <<<"$OUT")" "1" "…and the main checkout, which has none, is named"
# A copy in the main checkout, not committed: the integration branch still lacks it, so
# a checkout of it made later would run no hooks (W1).
mkdir -p "$D/.flight-rules" && cp -R "$D/.ai/hooks" "$D/.flight-rules/hooks" || die "could not copy the hooks in $D"
OUT=$(run "$WT/move")
say "$(grep -c "$MOVED" <<<"$OUT")$(grep -c 'have no copy in .flight-rules/hooks/ yet: the integration branch main' <<<"$OUT")" "01" "…every checkout with a copy, the integration branch without: still no command, and it is named"
rm -rf "$D/.flight-rules/hooks"
"${GN[@]}" -C "$WT/move" add -A && "${GN[@]}" -C "$WT/move" commit -qm move \
  && "${GN[@]}" -C "$D" merge -q --no-ff --no-edit chore/move-hooks || die "could not merge the move in $D"
OUT=$(run "$WT/move")
say "$(grep -c "$MOVED" <<<"$OUT")$(grep -c 'have no copy in' <<<"$OUT")" "10" "…and once the move is merged into it, the command"
# After it, a branch cut before the move has only the old folder: git runs no hooks
# there, and the doctor named no remedy (V1).
"${GN[@]}" -C "$D" worktree remove --force "$WT/move" || die "could not remove the worktree"
# Its path has a space in it, and is named whole.
"${GN[@]}" -C "$D" worktree add -q "$WT/old one" -b feature/old 'main^1' || die "could not add the old branch's worktree"
git -C "$D" config core.hooksPath .flight-rules/hooks
OUT=$(run "$WT/old one")
say "$(head -1 <<<"$OUT")$(grep -c 'core.hooksPath=.flight-rules/hooks but that directory does not exist in this checkout — this branch predates the hooks'"'"' move from .ai/hooks/, so git runs NO hooks here. Bring the move in: git merge main' <<<"$OUT")" "11" "a worktree behind the move (setting on the new folder, only the old one here): the merge that brings it"
# From the main checkout, which has the move, that worktree was not mentioned: only a
# doctor run inside it said it ran no hooks (0.29.0 release review, third pass, W1 (b)).
OUT=$(run "$D")
say "$(head -1 <<<"$OUT")$(grep -c "core.hooksPath=.flight-rules/hooks is one setting for every checkout of this clone, and $WT/old one has no copy in .flight-rules/hooks/ — git runs NO hooks there. Bring the move in, in that checkout: git merge main" <<<"$OUT")" "11" "…and from the main checkout, moved, that worktree is named whole, with the merge"
"${GN[@]}" -C "$WT/old one" merge -q --no-edit main || die "could not merge main into the old branch"
OUT=$(run "$D")
say "$(head -1 <<<"$OUT")$(grep -c 'core.hooksPath' <<<"$OUT")$(grep -c '✅ core.hooksPath=.flight-rules/hooks$' <<<"$OUT")" "011" "…and once it has the move, the one ok line and nothing else"
rm -rf "$D" "$WT"
# One checkout, the move committed on a branch not yet in the integration branch: the
# command was printed, and a switch to the integration branch ran no hooks (W1 (a)).
D=$(mkrepo); mv "$D/.flight-rules/hooks" "$D/.ai-hooks-tmp"; mkdir -p "$D/.ai"; mv "$D/.ai-hooks-tmp" "$D/.ai/hooks" || die "could not move the hooks to their old place"
git -C "$D" config core.hooksPath .ai/hooks
"${GN[@]}" -C "$D" add -A && "${GN[@]}" -C "$D" commit -qm base || die "could not commit the fixture in $D"
"${GN[@]}" -C "$D" switch -q -c chore/move && cp -R "$D/.ai/hooks" "$D/.flight-rules/hooks" \
  && "${GN[@]}" -C "$D" add -A && "${GN[@]}" -C "$D" commit -qm move || die "could not commit the move in $D"
OUT=$(run "$D")
say "$(head -1 <<<"$OUT")$(grep -c 'git config core.hooksPath .flight-rules/hooks' <<<"$OUT")$(grep -c 'have no copy in .flight-rules/hooks/ yet: the integration branch main (merge the move into it first)' <<<"$OUT")" "101" "one checkout, the move not in the integration branch: no command, and the integration branch named"
"${GN[@]}" -C "$D" switch -q main && "${GN[@]}" -C "$D" merge -q --no-ff --no-edit chore/move || die "could not merge the move in $D"
OUT=$(run "$D")
say "$(grep -c "$MOVED" <<<"$OUT")$(grep -c 'have no copy in' <<<"$OUT")" "10" "…once it has the move, the command"
# A worktree whose branch has neither folder (an orphan docs branch) loses nothing when
# the setting changes, and held the command back for as long as it existed (W1 (c)).
WT=$(tmpd); "${GN[@]}" -C "$D" worktree add -q --detach "$WT/docs" || die "could not add the docs worktree"
"${GN[@]}" -C "$WT/docs" checkout -q --orphan docs && "${GN[@]}" -C "$WT/docs" rm -rqf . && echo d > "$WT/docs/d.md" \
  && "${GN[@]}" -C "$WT/docs" add d.md && "${GN[@]}" -C "$WT/docs" commit -qm docs || die "could not make the orphan docs branch"
OUT=$(run "$D")
say "$(grep -c "$MOVED" <<<"$OUT")$(grep -c 'have no copy in' <<<"$OUT")" "10" "…and a worktree on an orphan branch with neither folder does not hold it back"
rm -rf "$D" "$WT"
# The setting on the new folder, in a checkout of an integration branch the move has not
# reached: a pull of it was printed, which brings nothing (W1, 3).
D=$(mkrepo); mv "$D/.flight-rules/hooks" "$D/.ai-hooks-tmp"; mkdir -p "$D/.ai"; mv "$D/.ai-hooks-tmp" "$D/.ai/hooks" || die "could not move the hooks to their old place"
"${GN[@]}" -C "$D" add -A && "${GN[@]}" -C "$D" commit -qm base || die "could not commit the fixture in $D"
OUT=$(run "$D")
say "$(head -1 <<<"$OUT")$(grep -c 'git pull\|git merge' <<<"$OUT")$(grep -c 'so git runs NO hooks here. The move has not reached main either: merge the branch that carries it into main. Until then, what runs this checkout'"'"'s hooks is git config core.hooksPath .ai/hooks, one setting for the whole clone, under which a checkout that has already removed .ai/hooks/ runs no hooks until it is changed back$' <<<"$OUT")" "101" "the setting moved, on an integration branch without the move: no pull of it, and the command that runs the old hooks, said to be the whole clone's"
rm -rf "$D"
# The other checkouts unread, with the setting on the new folder: said, not taken for
# none lagging (W1).
D=$(mkrepo); SH=$(tmpd); REALGIT=$(command -v git)
printf '#!/bin/sh\n[ "$1" = worktree ] && [ "$2" = list ] && exit 128\nexec "%s" "$@"\n' "$REALGIT" > "$SH/git" && chmod +x "$SH/git" || die "could not make the git shim"
OUT=$(cd "$D" && PATH="$SH:$PATH" HOME="$D/fakehome" bash "$DOCTOR" 2>&1)
say "$(grep -c '⚠️  core.hooksPath is one setting for every checkout of this clone, and (the other checkouts: git worktree list failed, so they could not be checked)' <<<"$OUT")" "1" "git worktree list failing, the setting on the new folder: said"
rm -rf "$D" "$SH"

echo "The doctor reads the conf as the hooks do (#127):"
say "$(sed -n '/^read_conf() {/,/^}/p' "$DOCTOR")" "$(sed -n '/^read_conf() {/,/^}/p' "$H/agent/pre-commit-check.sh")" "read_conf is pre-commit-check.sh's, verbatim"
while IFS='%' read -r desc line; do
  D=$(mkrepo); printf '%s\nINTEGRATION_BRANCH=dev\n' "$line" > "$D/.flight-rules/conf"
  OUT=$(run "$D")
  say "$(grep -c 'PROTECTED_BRANCHES=.* — no protected branches in the agent guard' <<<"$OUT")" "1" "$desc: said to be off"
  say "$(grep -c 'NOTE_GATED_BRANCHES unset — nothing is note-gated (no protected set)' <<<"$OUT")$(grep -c 'derived: protected' <<<"$OUT")" "10" "…with no derived note gate beside it"
  rm -rf "$D"
done <<'CASES'
off with a comment after it%PROTECTED_BRANCHES=off  # trunk only
off in single quotes%PROTECTED_BRANCHES='off'
none%PROTECTED_BRANCHES=none
CASES
# A quoted protected set equal to the PR-only one, quoted otherwise, is the same set.
D=$(mkrepo); printf 'PROTECTED_BRANCHES="^main$"\nPR_ONLY_BRANCHES='"'"'^main$'"'"'  # one branch\n' > "$D/.flight-rules/conf"
OUT=$(run "$D")
say "$(grep -c 'nothing is note-gated (every protected branch is PR-only)' <<<"$OUT")" "1" "the same pattern quoted two ways: every protected branch is PR-only"
rm -rf "$D"

echo "The way through, left set (#151):"
D=$(mkrepo)
OUT=$(cd "$D" && FLIGHT_RULES_GO_AHEAD=1 HOME="$D/fakehome" bash "$DOCTOR" 2>&1; echo "rc=$?")
say "$(grep -c '❌ FLIGHT_RULES_GO_AHEAD=1 is set in this environment — every stop of every git hook is passed' <<<"$OUT")" "1" "FLIGHT_RULES_GO_AHEAD=1 in the environment: a ❌"
OUT=$(run "$D")
say "$(head -1 <<<"$OUT")$(grep -c 'FLIGHT_RULES_GO_AHEAD' <<<"$OUT")" "00" "…and unset: exit 0, and no word of it"
rm -rf "$D"

finish
