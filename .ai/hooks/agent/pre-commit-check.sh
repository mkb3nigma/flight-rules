#!/bin/bash
# Agent hook: Branch Policy Enforcer + Secret Leak Watcher
# Wire as a Claude Code PreToolUse hook on the Bash tool (see hooks/README.md).
# Fires on every Bash tool use; only acts when the command contains "git commit".
#
# I/O protocol is Claude Code's: tool input as JSON on stdin, a structured
# permissionDecision on stdout. Another assistant needs a thin adapter around the
# same checks.

PROTECTED_RE='^main$'   # project parameter: {PROTECTED_BRANCHES}
WORKTREE_DIR='.ai/worktrees'          # project parameter: {WORKTREE_DIR}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Only run on git commit commands
if [[ "$COMMAND" != *"git commit"* ]]; then
  exit 0
fi

# ─────────────────────────────────────────────
# 1. BRANCH POLICY CHECK
# ─────────────────────────────────────────────
WORK_DIR=""
if [[ "$COMMAND" =~ cd[[:space:]]+([^[:space:]&;]+) ]]; then
  WORK_DIR="${BASH_REMATCH[1]}"
fi
if [[ -n "$WORK_DIR" ]]; then
  CURRENT_BRANCH=$(git -C "$WORK_DIR" branch --show-current 2>/dev/null)
else
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
fi

# Scope the branch policy to the project this hook belongs to. Without this, the
# guard applies the project's branch rules to every repo the session touches —
# including a sibling repo whose normal working branch IS main. (The secret scan
# below stays global on purpose: secrets are bad in any repo.)
IN_THIS_PROJECT=1
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  TARGET_ROOT=$(git -C "${WORK_DIR:-.}" rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$TARGET_ROOT" && "$TARGET_ROOT" != "$CLAUDE_PROJECT_DIR" ]]; then
    IN_THIS_PROJECT=0
  fi
fi

# Allow merge commits on protected branches — merging feature branches in is the intended workflow
GIT_DIR_PATH=$(git -C "${WORK_DIR:-.}" rev-parse --git-dir 2>/dev/null)
if [[ "$IN_THIS_PROJECT" == "0" ]]; then
  # Another repo — its branch policy is not ours to enforce
  :
elif [[ -f "$GIT_DIR_PATH/MERGE_HEAD" ]]; then
  # This is a merge commit; let it through
  :
elif [[ "$CURRENT_BRANCH" =~ $PROTECTED_RE ]]; then
  jq -n --arg branch "$CURRENT_BRANCH" --arg wt "$WORKTREE_DIR" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("⛔ BLOCKED: You are on the protected branch \"" + $branch + "\".\n\nNever commit directly to a protected branch.\n\nCreate a feature worktree instead:\n  git worktree add " + $wt + "/<name> -b feature/<name>\n  cd " + $wt + "/<name>")
    }
  }'
  exit 0
fi

# ─────────────────────────────────────────────
# 2. SECRET LEAK CHECK
# ─────────────────────────────────────────────
GIT="git"
[[ -n "$WORK_DIR" ]] && GIT="git -C $WORK_DIR"

STAGED_DIFF=$($GIT diff --cached 2>/dev/null)
STAGED_FILES=$($GIT diff --cached --name-only 2>/dev/null)
FINDINGS=""

# .env file staged (matches .env, .env.local, path/.env — but not .env.example)
if echo "$STAGED_FILES" | grep -E '(^|/)\.env(\.|$)' | grep -qv '\.env\.example'; then
  FINDINGS="$FINDINGS\n  • .env file is staged for commit"
fi

# Cloud access key
if echo "$STAGED_DIFF" | grep -qE '^\+[^+].*AKIA[A-Z0-9]{16}'; then
  FINDINGS="$FINDINGS\n  • AWS access key pattern detected (AKIA...)"
fi

# API-key literal (OpenAI/Anthropic style)
if echo "$STAGED_DIFF" | grep -qE '^\+[^+].*sk-[a-zA-Z0-9]{32,}'; then
  FINDINGS="$FINDINGS\n  • API key pattern detected (sk-...)"
fi

# Private key header
if echo "$STAGED_DIFF" | grep -qE '^\+[^+].*(BEGIN PRIVATE KEY|BEGIN RSA PRIVATE KEY)'; then
  FINDINGS="$FINDINGS\n  • Private key header detected"
fi

# Hardcoded password/secret/token literals in non-test source files only.
# Test fixtures legitimately use literal passwords — exclude tests/ dirs and *_test.* / *.spec.* files.
NON_TEST_FILES=$($GIT diff --cached --name-only 2>/dev/null | grep -Ev '(^|/)tests?/|_test\.(py|ts|js)$|\.spec\.(ts|js)$|conftest\.py$')
if [[ -n "$NON_TEST_FILES" ]]; then
  NON_TEST_DIFF=$($GIT diff --cached -- $NON_TEST_FILES 2>/dev/null)
  if echo "$NON_TEST_DIFF" | grep -qE '^\+[^+].*(password|secret|api_key)\s*=\s*["'"'"'][^"'"'"'$\{]{8,}'; then
    FINDINGS="$FINDINGS\n  • Possible hardcoded credential (password/secret/api_key assigned to string literal)"
  fi
fi

if [ -n "$FINDINGS" ]; then
  jq -n --arg findings "$(echo -e "$FINDINGS")" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("🔐 BLOCKED: Possible secret detected in staged files:\n" + $findings + "\n\nRemove these before committing. If this is a false positive, unstage and re-check.")
    }
  }'
  exit 0
fi

exit 0
