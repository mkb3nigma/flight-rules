#!/usr/bin/env bash
# Tests for the WIRING — does each install path actually register every agent hook?
#
# This exists because the two paths shipped different subsets for the life of the
# plugin and nothing noticed (found 2026-09-10): hooks.json registered the principles
# injector and the guard but not session-start.sh, so plugin users got no install
# health check; hooks/README.md's snippet registered session-start.sh and the guard
# but not the injector, so hand-wired users got no rules injected — half of what this
# playbook does. The catalogue test keeps README/plugin.json/skills in agreement;
# nothing kept the wiring in agreement with the scripts that exist.
#
# Run: ./wiring.test.sh   (no args, no network)

set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$H/.." && pwd)"
PASS=0; FAIL=0
say() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); echo "  ✅ $2"; else FAIL=$((FAIL+1)); echo "  ❌ $2"; fi; }

# The agent-facing hooks this repo ships. Git hooks live in hooks/git/ and are wired by
# core.hooksPath (install.sh), not by either of these files, so they are not listed.
AGENT_HOOKS="session-start-rules.sh agent/session-start.sh agent/pre-commit-check.sh"

echo "Every agent hook that exists is registered by the plugin:"
for h in $AGENT_HOOKS; do
  [ -f "$ROOT/hooks/$h" ] || { FAIL=$((FAIL+1)); echo "  ❌ hooks/$h does not exist"; continue; }
  grep -qF "$h" "$H/hooks.json"; say "$?" "hooks.json registers $h"
done

echo "…and by the without-plugin snippet in the README:"
SNIPPET=$(sed -n '/^### Wiring (Claude Code)/,/^### /p' "$H/README.md")
for h in $AGENT_HOOKS; do
  grep -qF "$h" <<<"$SNIPPET"; say "$?" "README snippet registers $h"
done

echo "The registered paths point at files that exist:"
# ${CLAUDE_PLUGIN_ROOT}/hooks/x → hooks/x relative to the repo root.
while IFS= read -r p; do
  [ -z "$p" ] && continue
  [ -f "$ROOT/$p" ]; say "$?" "hooks.json path exists: $p"
done < <(grep -o '${CLAUDE_PLUGIN_ROOT}/[^"\\]*' "$H/hooks.json" | sed 's|${CLAUDE_PLUGIN_ROOT}/||')

echo "hooks.json is valid JSON and wires the guard exactly once:"
if command -v jq >/dev/null 2>&1; then
  jq -e . "$H/hooks.json" >/dev/null 2>&1; say "$?" "hooks.json parses"
  N=$(jq '[.hooks.PreToolUse[]?.hooks[]? | select(.command | test("pre-commit-check"))] | length' "$H/hooks.json")
  [ "$N" = "1" ]; say "$?" "the guard is registered once (got $N)"
  M=$(jq '[.hooks.SessionStart[]?.hooks[]?] | length' "$H/hooks.json")
  [ "$M" = "2" ]; say "$?" "both SessionStart hooks are registered (got $M)"
else
  echo "  ⚠️  jq absent — skipping the JSON assertions"
fi

echo "Every registered hook actually RUNS, in the environment each path provides:"
# This suite used to assert registration by grepping hooks.json and the README snippet
# for a filename. It passed 15/15 while the README's without-plugin snippet injected NO
# RULES AT ALL — session-start-rules.sh read ${CLAUDE_PLUGIN_ROOT} under `set -u`, and
# only the plugin sets that. A filename was present in both files; one of them did not
# work. Found 2026-09-11, in the suite written to stop exactly that divergence.
#
# So each path is now EXERCISED, not matched. The distinction matters because the two
# paths differ in more than their text: the plugin sets CLAUDE_PLUGIN_ROOT, and the
# hand-wired snippet does not.
LAB=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$LAB"' EXIT
git init -q "$LAB/proj"
( cd "$LAB/proj" && git config user.email t@t.t && git config user.name t \
  && echo x > f.txt && git add -A && git commit -qm base ) >/dev/null 2>&1

# Output goes to a FILE, not to stdout. An earlier draft returned it via `$(run_hook …)`,
# which runs the function in a subshell — so its FAIL increment was discarded and its ❌
# line was captured as data instead of printed. The suite then reported 23 passed, 0
# failed against a hook that aborts on an unbound variable. A test harness that loses
# failures is the thing this file exists to prevent.
HOOK_OUT="$LAB/hook.out"
run_hook() {   # <label> <env-shape: plugin|handwired> <script>  -> 0 ok, 1 failed
  local label="$1" shape="$2" script="$3" rc
  if [ "$shape" = plugin ]; then
    ( cd "$LAB/proj" && CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$LAB/proj" \
      bash "$script" </dev/null ) > "$HOOK_OUT" 2>&1; rc=$?
  else
    ( cd "$LAB/proj" && env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$LAB/proj" \
      bash "$script" </dev/null ) > "$HOOK_OUT" 2>&1; rc=$?
  fi
  if [ $rc -ne 0 ] || grep -qi 'unbound variable\|command not found\|No such file' "$HOOK_OUT"; then
    FAIL=$((FAIL+1)); printf '  ❌ %s exits %s: %s\n' "$label" "$rc" "$(head -1 "$HOOK_OUT")"
    return 1
  fi
  return 0
}

for shape in plugin handwired; do
  run_hook "session-start-rules.sh ($shape)" "$shape" "$ROOT/hooks/session-start-rules.sh" && {
    if grep -q 'Engineering Principles' "$HOOK_OUT"; then
      PASS=$((PASS+1)); printf '  ✅ session-start-rules.sh injects the principles (%s)\n' "$shape"
    else
      FAIL=$((FAIL+1)); printf '  ❌ session-start-rules.sh ran but injected nothing (%s)\n' "$shape"
    fi
  }
  run_hook "agent/session-start.sh ($shape)" "$shape" "$ROOT/hooks/agent/session-start.sh" && {
    PASS=$((PASS+1)); printf '  ✅ agent/session-start.sh runs clean (%s)\n' "$shape"
  }
done

# The guard is a decision function; exercise it rather than checking it exists.
for shape in plugin handwired; do
  if [ "$shape" = plugin ]; then
    OUT=$(cd "$LAB/proj" && CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$LAB/proj" \
          bash "$ROOT/hooks/agent/pre-commit-check.sh" \
          <<<'{"tool_input":{"command":"git commit -m x"}}' 2>&1)
  else
    OUT=$(cd "$LAB/proj" && env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$LAB/proj" \
          bash "$ROOT/hooks/agent/pre-commit-check.sh" \
          <<<'{"tool_input":{"command":"git commit -m x"}}' 2>&1)
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
    PASS=$((PASS+1)); printf '  ✅ pre-commit-check.sh denies a commit on master (%s)\n' "$shape"
  else
    FAIL=$((FAIL+1)); printf '  ❌ pre-commit-check.sh did not fire (%s): %s\n' "$shape" "$(head -1 <<<"$OUT")"
  fi
done

echo "The path this repo itself runs is wired too:"
# hooks.json and the README snippet were both checked; .claude/settings.json — the file
# this repo actually runs on — was not, and is where a drop would hurt most here.
for h in $AGENT_HOOKS; do
  grep -qF "$h" "$ROOT/.claude/settings.json"; say "$?" ".claude/settings.json wires $h"
done

echo "Every agent hook is executable (git records the mode; a non-exec hook is silent):"
for h in $AGENT_HOOKS; do
  [ -x "$ROOT/hooks/$h" ]; say "$?" "hooks/$h is executable"
done

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
