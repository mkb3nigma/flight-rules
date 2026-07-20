#!/usr/bin/env bash
# flight-rules SessionStart hook.
#
# Plugins surface skills/commands/hooks as active primitives, but a plugin's
# rules/*.md are just files — installing the plugin does NOT put them in the
# model's context. This hook fixes that for the behavioural rules: it injects
# engineering-principles.md into every session (startup, resume, clear, compact)
# so the principles are actually followed wherever the plugin is enabled, not
# merely shipped as documentation.
#
# SessionStart context injection requires JSON on stdout of the shape:
#   {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}
# Raw stdout is not the documented contract, so we build that JSON with jq
# (preferred) or python3, and no-op cleanly if neither is available.
set -euo pipefail

RULES="${CLAUDE_PLUGIN_ROOT}/rules/engineering-principles.md"
[ -r "$RULES" ] || exit 0

HEADER="The flight-rules plugin is active. These engineering principles govern how you work in this session — follow them:"

if command -v jq >/dev/null 2>&1; then
  jq -Rs --arg h "$HEADER" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:($h + "\n\n" + .)}}' \
    "$RULES"
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$RULES" "$HEADER" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": sys.argv[2] + "\n\n" + text,
    }
}))
PY
else
  # No JSON tool available — skip injection rather than emit malformed output.
  exit 0
fi
