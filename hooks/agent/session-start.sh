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
INTEGRATION_BRANCH="$(conf_get INTEGRATION_BRANCH)"; INTEGRATION_BRANCH="${INTEGRATION_BRANCH:-main}"  # {INTEGRATION_BRANCH}
WORKTREE_DIR="$(conf_get WORKTREE_DIR)";             WORKTREE_DIR="${WORKTREE_DIR:-.ai/worktrees}"     # {WORKTREE_DIR}

# Once a day PER PROJECT. The flag used to carry only the date, so the first
# project opened each day took the reminder for all of them; and nothing pruned
# the flags, so they accumulated one per day forever.
FLAG_DIR="$HOME/.claude/hooks"
mkdir -p "$FLAG_DIR"
find "$FLAG_DIR" -maxdepth 1 -name '.worktree-check-*' -mtime +1 -delete 2>/dev/null
# The plugin version is in the name too, so an update re-runs doctor that day: it is
# where an upgrade's missing git hook is reported, and a flag touched that morning made
# the report wait a day (/dg, 2026-10-08). Hand-wired, there is no plugin.json and no
# version, and the flag is per day only.
PLUGIN_VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$(dirname "${BASH_SOURCE[0]}")/../../.claude-plugin/plugin.json" 2>/dev/null | head -1)
LAST_RUN_FILE="$FLAG_DIR/.worktree-check-$(printf '%s' "$PROJECT_ROOT" | tr '/' '-')-$(date +%Y%m%d)${PLUGIN_VERSION:+-$PLUGIN_VERSION}"

if [ -f "$LAST_RUN_FILE" ]; then
  exit 0
fi

touch "$LAST_RUN_FILE"

# HOOK_SYNC=auto: before asking whether the git hooks are current, make them so — for
# the copies that are provably unmodified (byte-identical to some release in the
# plugin cache) or missing. A plugin update cannot touch the project's committed hooks,
# so AppliHawk ran 0.22.0 hooks under a 0.23.0 plugin and the only signal was a
# CHANGELOG paragraph (2026-10-12). The owner opts in through the conf — a hook
# rewriting committed files unasked is the surprise that gets guards switched off —
# and still commits the result. A hook that matches no release is left alone: it may
# be the project's own adaptation, and doctor names it below. Nothing runs when no
# hooks are installed (that is the owner's install step, not an update) or when this
# script was copied in by hand and has no git/ beside it to sync from. LOCAL config
# only: a global core.hooksPath names a directory outside every repo, and following it
# wrote the hooks there (review, 2026-10-12). Nor mid-merge, -rebase, -cherry-pick or -revert (review, 2026-10-12), where an
# unattended write to a tracked file is what makes `--continue` refuse.
HOOK_SYNC="$(conf_get HOOK_SYNC)"
GIT_HOOKS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../git" 2>/dev/null && pwd)"
if [ "$HOOK_SYNC" = "auto" ] && [ -f "$GIT_HOOKS_SRC/install.sh" ] \
   && [ -n "$(git config --local core.hooksPath 2>/dev/null)" ] \
   && ! git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && ! git rev-parse -q --verify REBASE_HEAD >/dev/null 2>&1 \
   && ! git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 \
   && ! git rev-parse -q --verify REVERT_HEAD >/dev/null 2>&1 \
   && [ ! -d "$(git rev-parse --git-path rebase-merge 2>/dev/null)" ] \
   && [ ! -d "$(git rev-parse --git-path rebase-apply 2>/dev/null)" ]; then
  SYNC_OUT=$(bash "$GIT_HOOKS_SRC/install.sh" --from "$GIT_HOOKS_SRC" --stale-only 2>&1); SYNC_RC=$?
  if [ "$SYNC_RC" -ne 0 ]; then
    echo "⚠️ flight-rules HOOK_SYNC=auto could not update the git hooks:"
    echo "$SYNC_OUT" | sed 's/^/  /'
    echo ""
  elif echo "$SYNC_OUT" | grep -q '^   synced '; then
    echo "🔁 flight-rules HOOK_SYNC=auto updated git hooks in this project — review the diff and commit it:"
    echo "$SYNC_OUT" | grep -E '^   (synced |[a-z.-]+: )' | sed 's/^  //'
    echo ""
  fi
fi

# Is the enforcement actually installed? Silent when it is.
DOCTOR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/flight-rules-doctor.sh"
if [ -x "$DOCTOR" ]; then
  PROBLEMS=$("$DOCTOR" --problems-only 2>/dev/null)
  if [ -n "$PROBLEMS" ]; then
    echo "🩺 flight-rules doctor — the enforcement is not fully installed here:"
    echo "$PROBLEMS"
    echo ""
  fi
fi

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

  # for-each-ref + an exact whole-line match, not `git branch --merged | grep -w`.
  # grep -w counts `-` as a word boundary, so with fix/a merged a worktree on
  # fix/a-x was reported merged — and the reminder's whole job is to say which
  # worktrees are safe to remove. -F matters too: a branch named fix/a.b is a
  # BRE that matches fix/axb. for-each-ref also emits undecorated names.
  # `lstrip=2`, not `short`: `short` abbreviates against ALL refs, so a tag sharing a
  # branch's name yields `heads/<name>` and the whole-line match below never fires —
  # the reminder silently stops reporting. `refs/heads/` on --merged for the same
  # reason: a bare name there resolves to the tag. (Found by review, 2026-09-12.)
  if git for-each-ref --format='%(refname:lstrip=2)' --merged "refs/heads/$INTEGRATION_BRANCH" refs/heads 2>/dev/null \
       | grep -qxF "$BRANCH"; then
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
