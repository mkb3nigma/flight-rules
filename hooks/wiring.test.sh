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

echo "Every agent hook is executable (git records the mode; a non-exec hook is silent):"
for h in $AGENT_HOOKS; do
  [ -x "$ROOT/hooks/$h" ]; say "$?" "hooks/$h is executable"
done

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
