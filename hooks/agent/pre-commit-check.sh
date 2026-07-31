#!/bin/bash
# Agent hook: Branch Policy Enforcer + Secret Leak Watcher
# Wire as a Claude Code PreToolUse hook on the Bash tool (see hooks/README.md).
# Fires on every Bash tool use; only acts on git commands that could damage a
# protected branch — the commit itself, or a working-tree mutation that would
# land there without ever reaching a commit.
#
# I/O protocol is Claude Code's: tool input as JSON on stdin, a structured
# permissionDecision on stdout. Another assistant needs a thin adapter around the
# same checks.

# Project configuration. Override per project WITHOUT forking this file by setting
# these in the consuming project's .claude/settings.json "env" block, e.g.:
#   "env": { "FLIGHT_RULES_PROTECTED_BRANCHES": "^(main|release/.*)$" }
# Deliberately environment-only: sourcing a config file out of the repo would let
# any cloned repository run code in this hook.
PROTECTED_RE="${FLIGHT_RULES_PROTECTED_BRANCHES:-^(main|staging|dev)\$}"
WORKTREE_DIR="${FLIGHT_RULES_WORKTREE_DIR:-.ai/worktrees}"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Does this command destroy work in the tree without going through a commit?
# Gating only on "git commit" leaves the branch policy bypassable: `git rm`,
# `git reset --hard`, `git clean -f` and `git checkout -- .` all mutate a
# protected branch's tree, and the guard never sees them because no commit
# follows. `git clean -n` and a bare `git checkout <branch>` are not destructive
# and stay allowed.
is_destructive() {
  # Normalise away an explicit "-C <dir>" so "git -C /x rm" matches like "git rm".
  local c
  c=$(printf '%s' "$1" | sed -E 's/git[[:space:]]+-C[[:space:]]+[^[:space:]]+/git/g')
  [[ "$c" =~ (^|[[:space:]\;\&\|])git[[:space:]]+(rm|restore)([[:space:]]|$) ]] && return 0
  [[ "$c" =~ (^|[[:space:]\;\&\|])git[[:space:]]+reset[[:space:]]+.*--hard ]] && return 0
  [[ "$c" =~ (^|[[:space:]\;\&\|])git[[:space:]]+clean[[:space:]]+.*-[a-zA-Z]*f ]] && return 0
  [[ "$c" =~ (^|[[:space:]\;\&\|])git[[:space:]]+checkout[[:space:]]+(--|\.)([[:space:]]|$) ]] && return 0
  return 1
}

if [[ "$COMMAND" == *"git commit"* ]]; then
  ACTION="commit"
elif is_destructive "$COMMAND"; then
  ACTION="destructive"
else
  exit 0
fi

# ─────────────────────────────────────────────
# 1. BRANCH POLICY CHECK
# ─────────────────────────────────────────────
WORK_DIR=""
if [[ "$COMMAND" =~ cd[[:space:]]+([^[:space:]&;]+) ]]; then
  WORK_DIR="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  # `git -C <dir>` retargets the repo just as surely as a `cd` does. Without this
  # the guard resolves the branch from the shell's cwd and can clear a command
  # that is actually aimed at a protected branch in another checkout.
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
  if [[ "$ACTION" == "destructive" ]]; then
    VERB="This command would modify or discard files in the working tree."
  else
    VERB="Never commit directly to a protected branch."
  fi
  jq -n --arg branch "$CURRENT_BRANCH" --arg wt "$WORKTREE_DIR" --arg verb "$VERB" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("⛔ BLOCKED: You are on the protected branch \"" + $branch + "\".\n\n" + $verb + "\n\nCreate a feature worktree instead:\n  git worktree add " + $wt + "/<name> -b feature/<name>\n  cd " + $wt + "/<name>\n\nUse absolute paths in the same command as every git operation — a drifting cwd is how the wrong repo gets modified.")
    }
  }'
  exit 0
fi

# Destructive commands never reach the staged-secret scan below — there is nothing
# staged to inspect, and the branch policy above is the whole check for them.
[[ "$ACTION" == "destructive" ]] && exit 0

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
