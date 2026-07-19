#!/bin/bash
# Agent hook: Worktree Cleanup Reminder
# Wire as a Claude Code SessionStart hook (see hooks/README.md).
# Runs the stale-worktree check at most once per day (flag file); stdout is added
# to the assistant's context for the session.

INTEGRATION_BRANCH='dev'      # project parameter: {INTEGRATION_BRANCH}
WORKTREE_DIR='.ai/worktrees'  # project parameter: {WORKTREE_DIR}

LAST_RUN_FILE="$HOME/.claude/hooks/.worktree-check-$(date +%Y%m%d)"

if [ -f "$LAST_RUN_FILE" ]; then
  exit 0
fi

touch "$LAST_RUN_FILE"

PROJECT_ROOT=$(pwd)
WORKTREES_DIR="$PROJECT_ROOT/$WORKTREE_DIR"

if [ ! -d "$WORKTREES_DIR" ]; then
  exit 0
fi

# Find worktrees whose branches have been merged into the integration branch
STALE=""
for WORKTREE_PATH in "$WORKTREES_DIR"/*/; do
  [ -d "$WORKTREE_PATH" ] || continue

  BRANCH=$(git -C "$WORKTREE_PATH" branch --show-current 2>/dev/null)
  [ -z "$BRANCH" ] && continue

  MERGED=$(git branch --merged "$INTEGRATION_BRANCH" 2>/dev/null | grep -w "$BRANCH")
  if [ -n "$MERGED" ]; then
    WORKTREE_NAME=$(basename "$WORKTREE_PATH")
    STALE="$STALE\n  Branch: $BRANCH  →  $WORKTREE_DIR/$WORKTREE_NAME"
  fi
done

if [ -n "$STALE" ]; then
  echo "🧹 Worktree cleanup reminder: the following branches are merged into $INTEGRATION_BRANCH but worktrees still exist:"
  echo -e "$STALE"
  echo ""
  echo "Clean up with:"
  echo "  git worktree remove $WORKTREE_DIR/<name>"
  echo "  git branch -d <branch-name>"
fi

exit 0
