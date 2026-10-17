#!/bin/bash
# Agent hook: Worktree Cleanup Reminder
# Wire as a Claude Code SessionStart hook (see hooks/README.md).
# Runs the stale-worktree check at most once per day (flag file).
#
# Output is one JSON object (plain text only when neither jq nor python3 can build it,
# see the end). What the PERSON must act on — doctor's ❌ problems, a hook
# sync — goes in `systemMessage`, which Claude Code shows the user; everything goes in
# `additionalContext` for the assistant. Doctor's ⚠️ warnings stay off the screen: some
# are true by choice (no conf in a main-only project) and could only be silenced by
# changing the project, so on screen they would repeat daily until the plugin was
# switched off (review, 2026-10-13). Plain stdout reaches the assistant only, so a
# fresh plugin user was never shown the install command doctor printed (measured in a
# live 2.1.296 session, 2026-10-13: a plain-stdout marker reached the model and not the
# screen, a systemMessage the screen and not the model).
#
# The screen is for projects that use flight-rules — a .ai/flight-rules.conf at the
# repo root, or flight-rules' gate where git runs hooks from. (Committed .ai/hooks/ alone
# is not adoption: beside another tool's global hooksPath it put a daily `cp` into that
# tool's directory on screen — fix review, 2026-10-13. A clone of that kind has no
# hooksPath and gets the once-ever hint, which is where its wire-up command belongs.) A plugin
# enabled for the whole account opens every repo, and a daily ❌ there, or in a
# directory that is no repo at all, is the nag that gets it switched off (fix review,
# 2026-10-13). Any core.hooksPath counted as adoption at first, and a husky repo got
# eight ❌ a day and a command that wrote the gates into .husky/ (fix review, same
# day). A repo with no core.hooksPath at any scope is shown the install hint once,
# ever; one whose hooks are someone else's, or no repo, is shown nothing. The
# assistant gets all of it daily.

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
# unattended write to a tracked file is what makes `--continue` refuse — and that skip
# is said, with the command for afterwards: silent, it read as "current". A rebase is
# in progress when git's rebase-merge or rebase-apply directory exists, as git status
# decides it; REBASE_HEAD is not a test of that, and one left over from March 2026 kept
# AppliHawk's hooks at 0.22.0 under 0.24.1 with nothing said (2026-10-17). git status
# also counts a stopped `git am` (rebase-apply/applying, named as such so nobody runs
# `rebase --continue` on it) and a multi-commit cherry-pick or revert whose conflict
# was committed by hand — CHERRY_PICK_HEAD gone, sequencer/todo left, and a later pick
# touching the synced hooks makes `--continue` refuse (review, 2026-10-17).
HOOK_SYNC="$(conf_get HOOK_SYNC)"
GIT_HOOKS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../git" 2>/dev/null && pwd)"
in_progress() {
  # Files, not refs: `rev-parse --verify MERGE_HEAD` also resolves a branch or tag of
  # that name (AppliHawk review, 2026-10-17).
  [ -f "$(git rev-parse --git-path MERGE_HEAD 2>/dev/null)" ] && { echo merge; return; }
  [ -f "$(git rev-parse --git-path CHERRY_PICK_HEAD 2>/dev/null)" ] && { echo cherry-pick; return; }
  [ -f "$(git rev-parse --git-path REVERT_HEAD 2>/dev/null)" ] && { echo revert; return; }
  [ -f "$(git rev-parse --git-path rebase-apply/applying 2>/dev/null)" ] && { echo "git am session"; return; }
  { [ -d "$(git rev-parse --git-path rebase-merge 2>/dev/null)" ] \
    || [ -d "$(git rev-parse --git-path rebase-apply 2>/dev/null)" ]; } && { echo rebase; return; }
  [ -f "$(git rev-parse --git-path sequencer/todo 2>/dev/null)" ] && echo "cherry-pick or revert"
}
SYNC_MSG=$(
if [ "$HOOK_SYNC" = "auto" ] && [ -f "$GIT_HOOKS_SRC/install.sh" ] \
   && [ -n "$(git config --local core.hooksPath 2>/dev/null)" ]; then
  OP=$(in_progress)
  if [ -n "$OP" ]; then
    echo "⏸️ flight-rules HOOK_SYNC=auto skipped the git hooks: a $OP is in progress. Once it is finished:"
    echo "  bash \"$GIT_HOOKS_SRC/install.sh\" --from \"$GIT_HOOKS_SRC\" --stale-only"
    echo ""
    exit 0
  fi
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
)

# Is the enforcement actually installed? Silent when it is.
DOCTOR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/flight-rules-doctor.sh"
DOCTOR_HEAD="🩺 flight-rules doctor — the enforcement is not fully installed here:"
DOCTOR_MSG=""; DOCTOR_SCREEN=""
if [ -x "$DOCTOR" ]; then
  PROBLEMS=$("$DOCTOR" --problems-only 2>/dev/null)
  [ -n "$PROBLEMS" ] && DOCTOR_MSG="$DOCTOR_HEAD
$PROBLEMS"
  # On screen: the ❌ lines, and the sync command only beside a ❌ about a hook copy —
  # the ⚠️ that also asks for it is not shown, and a bare command next to an unrelated
  # ❌ read as an instruction with no reason (fix review, 2026-10-13).
  if printf '%s\n' "$PROBLEMS" | grep -q '❌'; then
    _show='❌'
    printf '%s\n' "$PROBLEMS" | grep -qE '❌ .*(copy —|missing from)' && _show='❌|^[[:space:]]+to update:'
    DOCTOR_SCREEN="$DOCTOR_HEAD
$(printf '%s\n' "$PROBLEMS" | grep -E "$_show")"
  fi
fi
# fr_hooks <dir>: does it hold flight-rules' gate? Its marker, as doctor's hook_marker.
fr_hooks() { [ -f "$1/pre-merge-commit" ] && grep -q 'PR_ONLY' "$1/pre-merge-commit" 2>/dev/null; }
HINT_FILE=""
if [ -n "$DOCTOR_SCREEN" ]; then
  TOP=$(git rev-parse --show-toplevel 2>/dev/null)
  HP=$(git config --path core.hooksPath 2>/dev/null)   # --path: git expands a leading ~
  case "$HP" in ""|/*) HP_DIR="$HP" ;; *) HP_DIR="$TOP/$HP" ;; esac
  if [ -z "$TOP" ]; then
    DOCTOR_SCREEN=""
  elif [ -f "$TOP/.ai/flight-rules.conf" ] || { [ -n "$HP_DIR" ] && fr_hooks "$HP_DIR"; }; then
    :   # adopted: shown daily
  elif [ -n "$HP" ]; then
    DOCTOR_SCREEN=""   # another tool's hooks; adopting flight-rules there is a choice
  else
    # Keyed on the repository, not the worktree: per-session worktrees each got the
    # "once-ever" hint (fix review, 2026-10-13).
    _common=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)
    HINT_FILE="$FLAG_DIR/.flight-rules-hinted-$(printf '%s' "${_common:-$TOP}" | tr '/' '-')"
    [ -f "$HINT_FILE" ] && { DOCTOR_SCREEN=""; HINT_FILE=""; }
  fi
fi
FOR_USER="$SYNC_MSG${SYNC_MSG:+${DOCTOR_SCREEN:+
}}$DOCTOR_SCREEN"

WORKTREES_DIR="$PROJECT_ROOT/$WORKTREE_DIR"

REMINDER=$(
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
)

FOR_ASSISTANT="$SYNC_MSG${SYNC_MSG:+${DOCTOR_MSG:+
}}$DOCTOR_MSG"
[ -n "$FOR_ASSISTANT$REMINDER" ] || exit 0
PLAIN="$FOR_ASSISTANT${FOR_ASSISTANT:+${REMINDER:+

}}$REMINDER"
# Said only on the JSON branches: with plain text the user saw nothing, and the
# assistant is the relay (pre-review, 2026-10-13).
SHOWN=""
[ -n "$SYNC_MSG" ] && SHOWN="the hook-sync result"
[ -n "$DOCTOR_SCREEN" ] && SHOWN="${SHOWN:+$SHOWN and }doctor's ❌ lines"
NOTE=""
[ -n "$SHOWN" ] && NOTE="

(Already on the user's screen at session start: $SHOWN. Anything else above was not shown to them.)"
CONTEXT="$FOR_ASSISTANT$NOTE${FOR_ASSISTANT:+${REMINDER:+

}}$REMINDER"
# JSON built by jq or python3, as session-start-rules.sh does. With neither, plain
# stdout: the assistant still gets it, and the assistant is who relays it. `-I`: this
# runs in the project, and without it a json.py there is imported and run (security
# review, 2026-10-13 — reproduced). The once-ever hint is spent only when it went out
# as JSON, i.e. reached the screen. A python3 that fails — macOS's stub without the
# Command Line Tools exits non-zero with no output — falls back to plain text, not
# to silence.
if command -v jq >/dev/null 2>&1; then
  jq -n --arg u "$FOR_USER" --arg c "$CONTEXT" \
    '(if $u == "" then {} else {systemMessage: $u} end)
     + {hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}' \
    && { [ -z "$HINT_FILE" ] || touch "$HINT_FILE" 2>/dev/null; true; }
elif command -v python3 >/dev/null 2>&1; then
  python3 -I -c 'import json, sys
out = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.argv[2]}}
if sys.argv[1]: out["systemMessage"] = sys.argv[1]
print(json.dumps(out))' "$FOR_USER" "$CONTEXT" 2>/dev/null \
    && { [ -z "$HINT_FILE" ] || touch "$HINT_FILE" 2>/dev/null; true; } || printf '%s\n' "$PLAIN"
else
  printf '%s\n' "$PLAIN"
fi
exit 0
