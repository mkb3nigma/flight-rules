#!/bin/bash
# Agent hook: Worktree Cleanup Reminder
# Wire as a Claude Code SessionStart hook (see hooks/README.md).
# Runs the stale-worktree check at most once per day (flag file); stdout is added
# to the assistant's context for the session.

PROJECT_ROOT=$(pwd)

# Parameters: .ai/flight-rules.conf when it has them (parsed as data, never
# sourced), else the defaults on the right.
conf_get() {
  sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"[:space:]]+)\"?.*$/\\1/p" \
    "$PROJECT_ROOT/.ai/flight-rules.conf" 2>/dev/null | tail -1
}
INTEGRATION_BRANCH="$(conf_get INTEGRATION_BRANCH)"; INTEGRATION_BRANCH="${INTEGRATION_BRANCH:-dev}"   # {INTEGRATION_BRANCH}
WORKTREE_DIR="$(conf_get WORKTREE_DIR)";             WORKTREE_DIR="${WORKTREE_DIR:-.ai/worktrees}"     # {WORKTREE_DIR}

# Once a day PER PROJECT. The flag used to carry only the date, so the first
# project opened each day took the reminder for all of them; and nothing pruned
# the flags, so they accumulated one per day forever.
FLAG_DIR="$HOME/.claude/hooks"
mkdir -p "$FLAG_DIR"
find "$FLAG_DIR" -maxdepth 1 -name '.worktree-check-*' -mtime +1 -delete 2>/dev/null
LAST_RUN_FILE="$FLAG_DIR/.worktree-check-$(printf '%s' "$PROJECT_ROOT" | tr '/' '-')-$(date +%Y%m%d)"

if [ -f "$LAST_RUN_FILE" ]; then
  exit 0
fi

touch "$LAST_RUN_FILE"

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
