#!/usr/bin/env bash
# Tests for doctor.sh — each case is an install state that has silently failed
# for real. Run: ./doctor.test.sh (no args, no network; builds throwaway repos).
set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="$H/doctor.sh"
PASS=0; FAIL=0
say() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✅ $3"; else FAIL=$((FAIL+1)); echo "  ❌ $3 (got '$1', want '$2')"; fi; }

# A repo with the hooks copied in and installed the documented way.
mkrepo() {
  local d; d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  mkdir -p "$d/.ai/hooks"
  cp "$H/git/pre-merge-commit" "$H/git/commit-msg" "$H/git/pre-rebase" "$H/git/post-merge" \
     "$H/git/reference-transaction" "$d/.ai/hooks/"
  chmod +x "$d"/.ai/hooks/*
  git -C "$d" config core.hooksPath .ai/hooks
  git -C "$d" config merge.ff false
  printf 'PROTECTED_BRANCHES=^main$\n' > "$d/.ai/flight-rules.conf"
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
# healthy, which is the exact "looks installed" failure doctor.sh exists to catch.
D=$(mkrepo); rm "$D/.ai/hooks/reference-transaction"
say "$(rc "$D")" "1" "reference-transaction missing → problem"
say "$(has "$D" "reference-transaction missing")" "0" "…names the hook"
rm -rf "$D"

D=$(mkrepo); chmod -x "$D/.ai/hooks/reference-transaction"
say "$(rc "$D")" "1" "reference-transaction without +x → problem"
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

D=$(mkrepo); git -C "$D" config --unset merge.ff
say "$(rc "$D")" "1" "merge.ff unset → problem"
say "$(has "$D" "fast-forward merge creates no commit")" "0" "…explains why"
rm -rf "$D"

echo "The conf — typos and bad values must not pass silently:"
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
say "$(has "$D" "the branch policy is off")" "0" "…with a warning naming both layers"
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

echo "Guard wiring — once, not twice, not a stale copy:"
D=$(mkrepo); mkdir -p "$D/.claude" "$D/fakehome/.claude"
printf '{"enabledPlugins":{"flight-rules@flight-rules":true}}' > "$D/fakehome/.claude/settings.json"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash x/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
say "$(has "$D" "runs twice")" "0" "plugin + local wiring → double-fire warning"
rm -rf "$D"

D=$(mkrepo); mkdir -p "$D/.claude/" "$D/.ai/hooks/agent"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash .ai/hooks/agent/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
printf '#!/bin/bash\n[[ "$COMMAND" == *"git commit"* ]]\n' > "$D/.ai/hooks/agent/pre-commit-check.sh"
say "$(rc "$D")" "1" "pre-conf copy of the guard → problem"
say "$(has "$D" "pre-conf copy")" "0" "…identified as such"
rm -rf "$D"

echo "--problems-only is silent on a healthy repo:"
D=$(mkrepo); rm "$D/.ai/flight-rules.conf"; printf 'PROTECTED_BRANCHES=^main$\n' > "$D/.ai/flight-rules.conf"
mkdir -p "$D/.claude"; printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash hooks/agent/pre-commit-check.sh"}]}]}}' > "$D/.claude/settings.json"
OUT=$(cd "$D" && HOME="$D/fakehome" bash "$DOCTOR" --problems-only 2>&1)
say "$(printf '%s' "$OUT" | grep -c .)" "0" "no output when nothing is wrong"
rm -rf "$D"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
