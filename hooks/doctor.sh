#!/usr/bin/env bash
# flight-rules doctor — is the enforcement actually installed, or does it just look
# installed? Every check here is a state that has silently failed at least once:
# a hook tracked without its executable bit, hooksPath pointing at a directory that
# no longer exists, merge.ff left at git's default so a fast-forward skips the gate,
# a conf key misspelled so the hook falls back to its default without a word, a
# local copy of the guard running beside the plugin's.
#
# Usage: hooks/doctor.sh [--problems-only]
#   Prints one line per check (✅ / ⚠️ / ❌). Exit 1 if any ❌. --problems-only
#   suppresses the ✅ lines (what session-start.sh uses, so a healthy repo is silent).
#
# Run from anywhere inside the repo. Reads the same conf the hooks read.

set -uo pipefail
QUIET=0; [[ "${1:-}" == "--problems-only" ]] && QUIET=1
FAIL=0; WARN=0
ok()   { [[ $QUIET -eq 1 ]] || printf '  ✅ %s\n' "$1"; }
warn() { WARN=$((WARN+1)); printf '  ⚠️  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { bad "not inside a git repository"; exit 1; }
cd "$ROOT" || exit 1

# ── 1. Git hooks: path set, directory present, every bare-named hook executable ──
HOOKS_PATH=$(git config core.hooksPath 2>/dev/null || true)
if [[ -z "$HOOKS_PATH" ]]; then
  bad "core.hooksPath is not set — the merge gate is not installed (hooks/git/install.sh, or: git config core.hooksPath <dir>)"
else
  HOOKS_DIR="$HOOKS_PATH"; [[ "$HOOKS_DIR" = /* ]] || HOOKS_DIR="$ROOT/$HOOKS_DIR"
  if [[ ! -d "$HOOKS_DIR" ]]; then
    bad "core.hooksPath=$HOOKS_PATH but that directory does not exist — git runs NO hooks"
  else
    ok "core.hooksPath=$HOOKS_PATH"
    for h in pre-merge-commit commit-msg pre-rebase post-merge reference-transaction; do
      if [[ ! -f "$HOOKS_DIR/$h" ]]; then
        bad "$h missing from $HOOKS_PATH — the gate is half built"
      elif [[ ! -x "$HOOKS_DIR/$h" ]]; then
        bad "$h is not executable — git ignores it silently (chmod +x, and commit the mode)"
      else
        ok "$h installed and executable"
      fi
    done
  fi
fi
MERGE_FF=$(git config merge.ff 2>/dev/null || true)
if [[ "$MERGE_FF" == "false" ]]; then
  ok "merge.ff=false (every real merge creates a commit, so the gate fires)"
else
  bad "merge.ff is '${MERGE_FF:-unset}' — a fast-forward merge creates no commit and no gate hook fires (git config merge.ff false)"
fi

# ── 2. The agent guard's parser ───────────────────────────────────────────────
if command -v jq >/dev/null 2>&1; then ok "jq on PATH"
elif command -v python3 >/dev/null 2>&1; then ok "python3 on PATH (jq fallback)"
else bad "neither jq nor python3 on PATH — the agent guard will deny every git command"; fi

# ── 3. The conf: known keys only, values that compile ─────────────────────────
CONF=".ai/flight-rules.conf"
KNOWN='PROTECTED_BRANCHES PR_ONLY_BRANCHES NOTE_GATED_BRANCHES INTEGRATION_BRANCH WORKTREE_DIR'
if [[ ! -f "$CONF" ]]; then
  warn "$CONF absent — every hook and skill is on its built-in default (fine for main-only trunk; otherwise create it)"
else
  ok "$CONF present"
  while IFS= read -r line; do
    line="${line%%#*}"; [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    key=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([A-Za-z_]+)[[:space:]]*=.*/\1/')
    val=$(printf '%s' "$line" | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/')
    if [[ " $KNOWN " != *" $key "* ]]; then
      warn "$CONF: unknown key '$key' — every hook ignores it and uses its default (typo?)"
      continue
    fi
    case "$key" in
      PROTECTED_BRANCHES|PR_ONLY_BRANCHES|NOTE_GATED_BRANCHES)
        if [[ "$val" == "off" || "$val" == "none" ]]; then
          [[ "$key" == PROTECTED_BRANCHES ]] && warn "$key=off — the branch policy is disabled in the agent guard (secret scan still on)" \
                                              || bad "$key=$val — only PROTECTED_BRANCHES understands off/none; this hook will treat it as a regex"
        elif ( [[ "x" =~ $val ]] ) 2>/dev/null; [[ $? -eq 2 ]]; then
          bad "$key='$val' is not a valid regex — bash rejects it and the hook fails closed or open depending on the path"
        elif [[ "$val" != ^* ]]; then
          warn "$key='$val' is unanchored — 'main' also matches 'maintenance'; use ^main\$"
        else ok "$key=$val"; fi ;;
      *) ok "$key=$val" ;;
    esac
  done < "$CONF"
fi

# ── 4. The guard is wired once, not twice ─────────────────────────────────────
PLUGIN_ON=0
grep -qs '"flight-rules@' "$HOME/.claude/settings.json" 2>/dev/null && PLUGIN_ON=1
LOCAL_WIRED=0
grep -qs 'pre-commit-check.sh' .claude/settings.json 2>/dev/null && LOCAL_WIRED=1
if [[ $PLUGIN_ON -eq 1 && $LOCAL_WIRED -eq 1 ]]; then
  warn "the flight-rules plugin is enabled AND .claude/settings.json wires a pre-commit-check.sh — the guard runs twice (drop the local wiring)"
elif [[ $PLUGIN_ON -eq 1 ]]; then ok "agent guard via the plugin"
elif [[ $LOCAL_WIRED -eq 1 ]]; then
  ok "agent guard via .claude/settings.json"
  if [[ -f .ai/hooks/agent/pre-commit-check.sh ]] && ! grep -q 'read_conf' .ai/hooks/agent/pre-commit-check.sh; then
    bad ".ai/hooks/agent/pre-commit-check.sh is a pre-conf copy of the guard — it matches 'git commit' as a substring and knows no other command; replace it with the current hooks/agent/ version"
  fi
else
  warn "no agent guard wired: neither the plugin nor .claude/settings.json runs pre-commit-check.sh — only the git hooks are protecting you"
fi

echo
if [[ $FAIL -gt 0 ]]; then printf '%d problem(s), %d warning(s)\n' "$FAIL" "$WARN"; exit 1; fi
[[ $QUIET -eq 1 && $WARN -eq 0 ]] || printf 'enforcement installed: %d warning(s)\n' "$WARN"
exit 0
