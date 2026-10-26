#!/bin/bash
# Agent hook: Worktree Cleanup Reminder
# Wire as a Claude Code SessionStart hook, and as a UserPromptSubmit one with --prompt
# (see hooks/README.md). Runs the stale-worktree check at most once per day (flag file);
# --prompt only says when this session's plugin version has changed.
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

# An exported CDPATH holding `.` makes cd print where it went, so a $(cd … && pwd -P)
# came back as two lines and named no directory: the guard's project comparison never
# matched and its branch policy was off (third fix review). Nothing here wants it.
unset CDPATH
# The checkout's top, as the guard and doctor find the conf: from a session started in
# a subdirectory, $(pwd) found none, and HOOK_SYNC, the open-branch count and the
# branch parameters went quietly to their defaults (full release review, S2).
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT=$(pwd)

# Parameters: .ai/flight-rules.conf when it has them (parsed as data, never
# sourced), else the defaults on the right.
# read_conf <key> <file>: pre-commit-check.sh's, verbatim — quotes, trailing comments —
# so a key reads here as the guard and doctor read it (session-start.test.sh compares).
read_conf() {
  local key="$1" file="$2"
  [ -r "$file" ] || return 1
  sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$/\1/p" "$file" \
    | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/' \
    | tail -1
}
# conf_get <key>: read_conf on this project's conf. It had its own sed, which kept
# single quotes: INTEGRATION_BRANCH='dev' counted open branches against a branch named
# 'dev', quotes and all, while doctor showed ✅ (0.27.0 release review).
conf_get() { read_conf "$1" "$PROJECT_ROOT/.ai/flight-rules.conf"; }
# shq <s>: <s> quoted for a shell to paste, bare when it is plain, else in '…' with each
# ' written '\''. Not printf %q: macOS bash 3.2's splits a multibyte character and
# leaves a raw byte, so `fix/ü-ß` printed as invalid UTF-8 (fix review, 2026-10-24).
# Nor sed: BSD sed stops on bytes that are not UTF-8 and printed '' (fourth review).
# Leading = and ~ are quoted too: zsh expands both. The letters are spelled out: a
# range like A-Z follows the locale's collation. Kept verbatim in step across
# post-merge, install.sh, flight-rules-doctor.sh and session-start.sh (tested).
shq() {
  local q="'\\''"
  case "$1" in
    ''|=*|'~'*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+,:-]*) printf "'%s'" "${1//\'/$q}" ;;
    *) printf '%s' "$1" ;;
  esac
}
INTEGRATION_BRANCH="$(conf_get INTEGRATION_BRANCH)"; INTEGRATION_BRANCH="${INTEGRATION_BRANCH:-main}"  # {INTEGRATION_BRANCH}
# The environment first, as the guard reads it: the conf alone, the stale-worktree
# reminder looked where the guard did not send them (full release review, S6).
WORKTREE_DIR="${FLIGHT_RULES_WORKTREE_DIR:-$(conf_get WORKTREE_DIR)}"; WORKTREE_DIR="${WORKTREE_DIR:-.ai/worktrees}"     # {WORKTREE_DIR}

# Once a day PER PROJECT. The flag used to carry only the date, so the first
# project opened each day took the reminder for all of them; and nothing pruned
# the flags, so they accumulated one per day forever.
FLAG_DIR="$HOME/.claude/hooks"
# The plugin version is in the name too, so an update re-runs doctor that day: it is
# where an upgrade's missing git hook is reported, and a flag touched that morning made
# the report wait a day (/dg, 2026-10-08). Hand-wired, there is no plugin.json and no
# version, and the flag is per day only.
PLUGIN_VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$(dirname "${BASH_SOURCE[0]}")/../../.claude-plugin/plugin.json" 2>/dev/null | head -1)

# The version this session started on, recorded at SessionStart under the session id
# Claude Code passes on stdin, and compared by --prompt (#94). /plugin update then
# /reload-plugins loads the new version's hooks, but no hook event fires on a reload
# and SessionStart does not fire again, so nothing said the session's rules, and the
# project's git hooks, were still the old version's: three hooks stayed stale under
# 0.26.0 (AppliHawk, 2026-10-21). --prompt only says so; the new session it asks for
# runs the sync and doctor. It once ran them itself, keyed on the per-project daily
# flag, and the batch review (2026-10-24) found what that flag cannot tell apart: an
# older session left open past midnight re-synced the hooks back to its own version
# and called itself updated, a reloaded session missed the notice whenever another
# had run the new version first, and a prompt from a subdirectory or worktree ran
# everything again. Keyed on the session, none of the three can happen. Only
# characters a session id has: the id names a file. A session started before this was
# recorded, or with no id on stdin, is never told. Only as the plugin, which hooks.json
# says with --plugin: /reload-plugins swaps only the plugin's copy, and a session
# running two copies (the plugin and a hand-wired one, or this repo's own wiring, which
# follows the cwd into a release worktree's bumped plugin.json) recorded whichever ran
# last and flipped the notice on every prompt (fix review, 2026-10-24: six notices in
# three prompts). A flag, not CLAUDE_PLUGIN_ROOT in the environment: that the loader
# exports it to a hook was never shown, and the notice would have failed silently;
# hooks.json's ${CLAUDE_PLUGIN_ROOT} substitution is what every plugin hook runs on,
# and wiring.test.sh checks the flag is there. Hand-wired, it is never told.
# `read -t`, not `cat`: Claude Code closes stdin after the JSON, but a caller that
# leaves it open (a test runner's socket did, 2026-10-24) would hold the hook until
# its timeout, and a timed-out run's whole output is dropped — the day's doctor with it.
# What a timed-out read keeps differs: bash 4+ leaves the partial line in _l, bash 3.2
# drops it, so there JSON with no final newline on a stdin held open gives no session
# id and no notice. Claude Code closes stdin, so that is a test runner's case, not a
# session's.
SESSION_FILE=""; _in=""
_as_plugin=""; _prompt=""
for _a in "$@"; do
  case "$_a" in --plugin) _as_plugin=1 ;; --prompt) _prompt=1 ;; esac
done
if [ -n "$_as_plugin" ] && [ -n "$PLUGIN_VERSION" ] && [ ! -t 0 ]; then
  while IFS= read -r -t 2 _l; do _in="$_in$_l"; done; _in="$_in${_l-}"
  _sid=$(printf '%s' "$_in" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9-]\{1,64\}\)".*/\1/p' | head -1)
  [ -n "$_sid" ] && SESSION_FILE="$FLAG_DIR/.session-version-$_sid"
fi
# On a prompt, not on PreToolUse, which fires mid-turn. Not headless: `claude -p` does
# not reload. Every other prompt costs the reads above and one of the record (about
# 15 ms, measured 2026-10-24).
if [ -n "$_prompt" ]; then
  [ "${CLAUDE_CODE_SESSION_ATTENDED-}" = "0" ] && exit 0
  [ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ] || exit 0
  _was=$(head -1 "$SESSION_FILE" 2>/dev/null)
  [ -n "$_was" ] && [ "$_was" != "$PLUGIN_VERSION" ] || exit 0
  printf '%s\n' "$PLUGIN_VERSION" > "$SESSION_FILE" 2>/dev/null
  # Said rather than injected a second time beside the first copy (owner, 2026-10-24).
  MSG="🔄 flight-rules is now $PLUGIN_VERSION in this session (it was $_was). Its agent hooks are running; its rules are not — the ones injected when this session started are the old version's — and the git hook sync and doctor checks for $PLUGIN_VERSION run at session start. Start a new session to get both."
  CTX="$MSG

(Already on the user's screen with this prompt.)"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg u "$MSG" --arg c "$CTX" \
      '{systemMessage: $u, hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json, sys
print(json.dumps({"systemMessage": sys.argv[1], "hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": sys.argv[2]}}))' "$MSG" "$CTX" 2>/dev/null \
      || printf '%s\n' "$MSG"
  else
    printf '%s\n' "$MSG"
  fi
  exit 0
fi
mkdir -p "$FLAG_DIR"
# Attended only: the record exists for --prompt, which a headless session never runs.
# Every SessionStart (startup, resume, clear, compact) rewrites it: each one injects
# the running version's rules. Pruned at a week, so a session open longer is not told.
if [ -n "$SESSION_FILE" ] && [ "${CLAUDE_CODE_SESSION_ATTENDED-}" != "0" ]; then
  printf '%s\n' "$PLUGIN_VERSION" > "$SESSION_FILE" 2>/dev/null
fi
find "$FLAG_DIR" -maxdepth 1 -name '.worktree-check-*' -mtime +1 -delete 2>/dev/null
find "$FLAG_DIR" -maxdepth 1 -name '.session-version-*' -mtime +7 -delete 2>/dev/null
LAST_RUN_FILE="$FLAG_DIR/.worktree-check-$(printf '%s' "$PROJECT_ROOT" | tr '/' '-')-$(date +%Y%m%d)${PLUGIN_VERSION:+-$PLUGIN_VERSION}"

if [ -f "$LAST_RUN_FILE" ]; then
  exit 0
fi

# Protected as pre-commit-check.sh decides it: the environment first, then the conf
# read by the same read_conf, the same default (session-start.test.sh compares them).
# Read once, for the sync and the open-branch count below.
PROT="${FLIGHT_RULES_PROTECTED_BRANCHES:-$(read_conf PROTECTED_BRANCHES "$PROJECT_ROOT/.ai/flight-rules.conf")}"
PROT="${PROT:-^(main|master|dev|develop|development|staging|stage|qa|uat|prod|production)$|^release(/|$)}"

# A headless session (`claude -p`, observed; other callers only if they set the variable
# below) has no screen. Spending the flag on
# it hid that day's ❌ from every attended session after it, and silently — the miss
# could never surface as an incident (owner, 2026-10-17). It still runs, for its own
# assistant's context. Claude Code sets CLAUDE_CODE_SESSION_ATTENDED=0 for `claude -p`
# (probe on 2.1.301, 2026-10-17); the variable is undocumented, so only an exact 0
# counts — unset, or renamed away, is the old once-a-day behaviour, never worse.
[ "${CLAUDE_CODE_SESSION_ATTENDED-}" = "0" ] || touch "$LAST_RUN_FILE"

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
# touching the synced hooks makes `--continue` refuse (review, 2026-10-17). And a
# `git bisect`, which git status also reports: a synced hook on the commit under test
# made the next `bisect good` refuse to check out (final release /dg, 2026-10-17).
#
# A headless session syncs too: the synced hook protects the clone at once, which a
# headless-only setup would otherwise never get. Its "commit the diff" reaches no
# screen, though, so an attended session that finds the hook directory changed and
# uncommitted says so (final release /dg, 2026-10-17).
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
  [ -f "$(git rev-parse --git-path sequencer/todo 2>/dev/null)" ] && { echo "cherry-pick or revert"; return; }
  [ -f "$(git rev-parse --git-path BISECT_LOG 2>/dev/null)" ] && echo bisect
}
SYNC_MSG=$(
if [ "$HOOK_SYNC" = "auto" ] && [ -f "$GIT_HOOKS_SRC/install.sh" ] \
   && [ -n "$(git config --local core.hooksPath 2>/dev/null)" ]; then
  # On a protected branch nothing is written: the diff could not be committed there,
  # and `git restore` to clear it is refused as discarding work, so it sat in the
  # checkout blocking the very merge that would land it (AppliHawk, 2026-10-21, #99).
  # Compared only, and said when something is behind, with the command for a branch.
  # Not a worktree made on the developer's behalf (owner, 2026-10-21): they choose
  # where to run it. Protected is decided as pre-commit-check.sh decides it: PROT above,
  # and bash's =~ case-insensitively. Its own parse, grep and case missed `'^trunk$'`,
  # `QA` and the environment, and wrote where the guard refuses (fix review, F1).
  _prot="$PROT"
  _br=$(git branch --show-current 2>/dev/null)
  _check=""; _bad=""
  if [ -n "$_br" ] && [ "$_prot" != off ] && [ "$_prot" != none ]; then
    shopt -s nocasematch; [[ "$_br" =~ $_prot ]]; _m=$?; shopt -u nocasematch
    [ "$_m" -eq 0 ] && _check=--check-only
    # 2: a pattern bash cannot compile. Taken as protected, and said — writing is the
    # failure that costs work (fix review, F5).
    [ "$_m" -eq 2 ] && { _check=--check-only; _bad=1; }
  fi
  # Decided before this exit: mid-merge on a protected branch, the plain command for
  # afterwards wrote there once the merge was done, the #99 state (full release
  # review, S5).
  OP=$(in_progress)
  if [ -n "$OP" ]; then
    if [ -n "$_check" ]; then
      echo "⏸️ flight-rules HOOK_SYNC=auto skipped the git hooks: a $OP is in progress, on \"$_br\", a protected branch. Once it is finished, run this in a worktree on a branch, then commit and merge it:"
      printf '  bash %s --from %s --stale-only --this-checkout\n' "$(shq "$GIT_HOOKS_SRC/install.sh")" "$(shq "$GIT_HOOKS_SRC")"   # shq: it is pasted
    else
      echo "⏸️ flight-rules HOOK_SYNC=auto skipped the git hooks: a $OP is in progress. Once it is finished:"
      printf '  bash %s --from %s --stale-only\n' "$(shq "$GIT_HOOKS_SRC/install.sh")" "$(shq "$GIT_HOOKS_SRC")"   # shq: it is pasted
    fi
    echo "Not doing one? A leftover never finishes: \`git status\` names it and the command that clears it."
    echo ""
    exit 0
  fi
  SYNC_OUT=$(bash "$GIT_HOOKS_SRC/install.sh" --from "$GIT_HOOKS_SRC" --stale-only $_check 2>&1); SYNC_RC=$?
  # Behind is stale or missing; the rest — adapted, differing, unreadable — the command
  # leaves alone, and listing them as behind beside it misled (fix review, F3).
  _behind=$(echo "$SYNC_OUT" | grep -E '^   [a-z.-]+: (missing|.* — stale)$' | sed 's/^  //')
  _left=$(echo "$SYNC_OUT" | grep -E '^   [a-z.-]+: ' | grep -vE '^   [a-z.-]+: (missing|.* — stale)$' | sed 's/^  //')
  # A hook the sync could not read, with nothing else to say: silent, the check that
  # could not run read as "current" (group A fix review, F4). Its own if, before the chain: an
  # elif in it, it kept the uncommitted-changes check below from ever running while
  # any hook was unreadable (group A fix review, F2).
  if [ "$SYNC_RC" -eq 0 ] && ! echo "$SYNC_OUT" | grep -q '^   synced ' \
     && echo "$_left" | grep -q 'could not check it'; then
    echo "⚠️ flight-rules HOOK_SYNC=auto could not check every git hook:"
    echo "$_left" | grep 'could not check it'
    echo ""
  fi
  if [ -n "$_check" ] && [ "$SYNC_RC" -eq 3 ]; then
    if [ -n "$_bad" ]; then
      echo "⏸️ flight-rules HOOK_SYNC=auto did not update the git hooks: PROTECTED_BRANCHES ($_prot) is not a pattern bash can read, so \"$_br\" is taken as protected. It is the project owner's to fix, in .ai/flight-rules.conf (or FLIGHT_RULES_PROTECTED_BRANCHES); an assistant does not edit it. Behind or missing:"
    else
      echo "⏸️ flight-rules HOOK_SYNC=auto did not update the git hooks: this checkout is on \"$_br\", a protected branch, where the change could not be committed. Behind or missing:"
    fi
    echo "$_behind"
    # --this-checkout: from a worktree whose git runs the hooks from this checkout, the
    # plain form refused and sent the user back here (#99 review, 2026-10-21).
    echo "To update them, run this in a worktree on a branch, then commit and merge it:"
    printf '  bash %s --from %s --stale-only --this-checkout\n' "$(shq "$GIT_HOOKS_SRC/install.sh")" "$(shq "$GIT_HOOKS_SRC")"   # shq: it is pasted
    [ -z "$_left" ] || { echo "Left alone (the command does not touch these):"; echo "$_left"; }
    echo ""
  elif [ "$SYNC_RC" -ne 0 ]; then
    echo "⚠️ flight-rules HOOK_SYNC=auto could not update the git hooks:"
    echo "$SYNC_OUT" | sed 's/^/  /'
    echo ""
  elif echo "$SYNC_OUT" | grep -q '^   synced '; then
    echo "🔁 flight-rules HOOK_SYNC=auto updated git hooks in this project — review the diff and commit it:"
    echo "$SYNC_OUT" | grep -E '^   (synced |[a-z.-]+: )' | sed 's/^  //'
    echo ""
  elif [ "${CLAUDE_CODE_SESSION_ATTENDED-}" != "0" ]; then
    # Asked from the directory that holds the hooks, not this checkout's top: from a
    # worktree whose hooks are in the main checkout, `status -- <that path>` is refused
    # (exit 128), and with 2>/dev/null that read as "no changes" (#93 batch review, B8).
    # A check that could not run is "could not check", with git's reason — never clean,
    # never "changed" (the rule each review of #93 found another case of: the third,
    # 2026-10-21). One run, both streams: a status line is two status letters and a
    # space; anything else is git saying something, a warning on a status that still
    # succeeded included. Read apart, the warning was either shown as a change (C2) or
    # dropped (E1), and a failed status asked again lost its reason (E2).
    _top=$(git rev-parse --show-toplevel 2>/dev/null)
    _hp=$(git config --local --path core.hooksPath)
    # if, not case: a case pattern's `)` inside this $( … ) is a syntax error to bash 3.2.
    if [ "${_hp#/}" != "$_hp" ]; then _hd="$_hp"; else _hd="$_top/$_hp"; fi
    _own=$(git -C "$_hd" rev-parse --show-toplevel 2>/dev/null)
    _in=""; [ "$_own" = "$_top" ] || _in=" in $_own"
    # status.branch=false: set true, it adds a `## <branch>` line that is not a status
    # line, and every session said the hooks could not be checked (#93 fix review, F2).
    # --untracked-files=all: status.showUntrackedFiles=no hid a hook the sync copied in
    # (group A fix review, F12).
    _all=$(git -C "$_hd" -c status.relativePaths=false -c color.status=false -c status.branch=false status --short --untracked-files=all -- . 2>&1); _st=$?
    _changed=$(printf '%s\n' "$_all" | grep -E '^[ MADRCUT?!]{2} ')
    _said=$(printf '%s\n' "$_all" | grep -vE '^[ MADRCUT?!]{2} ' | grep .)
    if [ "$_st" -ne 0 ] || [ -n "$_said" ]; then
      echo "⚠️ flight-rules could not fully check the git hooks$_in for uncommitted changes — git said:"
      printf '%s\n' "${_said:-(nothing; git status exited $_st)}" | sed 's/^/  /'
      [ -n "$_changed" ] && printf '%s\n' "$_changed" | sed 's/^/  /'
      echo ""
    elif [ -n "$_changed" ]; then
      echo "📝 flight-rules: the git hooks have uncommitted changes$_in — yours, or a headless session's HOOK_SYNC=auto, whose notice no one saw. \`git status\` and \`git diff HEAD\` there show them; commit what should stay:"
      printf '%s\n' "$_changed" | sed 's/^/  /'
      echo ""
    fi
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
    _common=$(cd -P "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)
    HINT_FILE="$FLAG_DIR/.flight-rules-hinted-$(printf '%s' "${_common:-$TOP}" | tr '/' '-')"
    [ -f "$HINT_FILE" ] && { DOCTOR_SCREEN=""; HINT_FILE=""; }
  fi
fi

# OPEN_BRANCH_LIMIT: how many branches are open at once, warned at the limit and never
# refused (#108). More than ten sat unmerged in this repo (2026-10-20 to 10-23), each
# small alone, and the owner saw the backlog only once they had begun to depend on each
# other. Open is a worktree's branch with commits not in the integration branch, a
# protected one aside; waiting is one whose tip has a passing pre-merge-check note.
# Default 5, warning only (owner, 2026-10-24); `off` stands it down; anything but a
# positive whole number is 5, which doctor says. Only where the project uses
# flight-rules: a repo without the conf is not told how to run its branches. The key
# is read as doctor reads it (read_conf strips the quotes doctor strips): `'2'` was
# ✅ to doctor and 5 here (batch review, G6). Merged means in the local integration
# branch or in origin's: a clone with only origin/dev was silently never counted (P1),
# and against local dev alone every branch merged by PR stayed open, because
# /feature-start fetches origin and never moves local dev (full release review, A2). A count that cannot be made is said, to the assistant only, as
# "?" lines split off below: a missed reminder, but never one that reads as "under
# the limit".
OPEN_MSG=$(
  [ -f "$PROJECT_ROOT/.ai/flight-rules.conf" ] || exit 0
  _lim="${FLIGHT_RULES_OPEN_BRANCH_LIMIT:-$(read_conf OPEN_BRANCH_LIMIT "$PROJECT_ROOT/.ai/flight-rules.conf")}"
  # Where it came from, said: raising it in the conf does nothing when the environment set it.
  _src="in .ai/flight-rules.conf"; [ -n "${FLIGHT_RULES_OPEN_BRANCH_LIMIT-}" ] && _src="from FLIGHT_RULES_OPEN_BRANCH_LIMIT"
  [ "$_lim" = off ] && exit 0
  [[ "$_lim" =~ ^0*[1-9][0-9]*$ ]] && _lim=$((10#$_lim)) || _lim=5
  _base=""; _into=""
  for _r in "refs/heads/$INTEGRATION_BRANCH" "refs/remotes/origin/$INTEGRATION_BRANCH"; do
    git rev-parse --verify -q "$_r" >/dev/null || continue
    _base="$_base $_r"; _into="${_into:+$_into or }${_r#refs/*/}"
  done
  [ -n "$_base" ] \
    || { echo "?OPEN_BRANCH_LIMIT: no $INTEGRATION_BRANCH here, local or origin/ — open branches not counted"; exit 0; }
  _list=$(git worktree list --porcelain 2>/dev/null) \
    || { echo "?OPEN_BRANCH_LIMIT: git worktree list failed — open branches not counted"; exit 0; }
  _prot="$PROT"
  _n=0; _wait=""; _work=""; _fail=""
  while IFS= read -r _b; do
    [ "$_b" = "$INTEGRATION_BRANCH" ] && continue
    # A pattern that does not compile (2) protects, as the sync above takes it — and the
    # count is then not made, said so: silent, it read as under the limit (fourth review).
    if [ "$_prot" != off ] && [ "$_prot" != none ]; then
      shopt -s nocasematch; [[ "$_b" =~ $_prot ]]; _m=$?; shopt -u nocasematch
      [ "$_m" -eq 2 ] && { echo "?OPEN_BRANCH_LIMIT: the protected pattern does not compile — open branches not counted"; exit 0; }
      [ "$_m" -eq 1 ] || continue
    fi
    # $_base unquoted: one or two refs that exist, so no spaces or glob characters.
    _ahead=$(git rev-list --count "refs/heads/$_b" --not $_base 2>/dev/null) || { _fail="$_fail $_b"; continue; }
    [ "$_ahead" -gt 0 ] || continue
    _n=$((_n+1))
    if git notes --ref=pre-merge-check show "refs/heads/$_b" 2>/dev/null | grep -q '^passed:'; then
      _wait="$_wait $_b"
    else
      _work="$_work $_b"
    fi
  done < <(printf '%s\n' "$_list" | sed -n 's|^branch refs/heads/||p')
  [ -z "$_fail" ] || echo "?OPEN_BRANCH_LIMIT: could not compare with $_into:$_fail — not counted"
  [ "$_n" -ge "$_lim" ] || exit 0
  echo "⏳ flight-rules: $_n branches are open and not yet merged into $_into (OPEN_BRANCH_LIMIT is $_lim, $_src). /feature-start asks before it opens another; merging some first keeps them from depending on each other."
  [ -z "$_wait" ] || echo "  Passed pre-merge-check, waiting to merge:$_wait"
  [ -z "$_work" ] || echo "  Not yet passed:$_work"
)
OPEN_NOTE=$(printf '%s\n' "$OPEN_MSG" | sed -n 's/^?//p')
OPEN_MSG=$(printf '%s\n' "$OPEN_MSG" | grep -v '^?')

FOR_USER="$SYNC_MSG${SYNC_MSG:+${DOCTOR_SCREEN:+
}}$DOCTOR_SCREEN"
FOR_USER="$FOR_USER${FOR_USER:+${OPEN_MSG:+

}}$OPEN_MSG"

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
FOR_ASSISTANT="$FOR_ASSISTANT${FOR_ASSISTANT:+${OPEN_MSG:+

}}$OPEN_MSG"
FOR_ASSISTANT="$FOR_ASSISTANT${FOR_ASSISTANT:+${OPEN_NOTE:+

}}$OPEN_NOTE"
[ -n "$FOR_ASSISTANT$REMINDER" ] || exit 0
PLAIN="$FOR_ASSISTANT${FOR_ASSISTANT:+${REMINDER:+

}}$REMINDER"
# Said only on the JSON branches: with plain text the user saw nothing, and the
# assistant is the relay (pre-review, 2026-10-13).
SHOWN=""
[ -n "$SYNC_MSG" ] && SHOWN="the hook-sync result"
[ -n "$DOCTOR_SCREEN" ] && SHOWN="${SHOWN:+$SHOWN and }doctor's ❌ lines"
[ -n "$OPEN_MSG" ] && SHOWN="${SHOWN:+$SHOWN and }the open-branch warning"
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
