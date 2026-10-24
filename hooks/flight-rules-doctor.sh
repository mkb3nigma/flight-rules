#!/usr/bin/env bash
# flight-rules doctor — is the enforcement actually installed, or does it just look
# installed? Every check here is a state that has silently failed at least once:
# a hook tracked without its executable bit, hooksPath pointing at a directory that
# no longer exists, merge.ff left at git's default so a fast-forward skips the gate,
# a conf key misspelled so the hook falls back to its default without a word, a
# local copy of the guard running beside the plugin's.
#
# Usage: hooks/flight-rules-doctor.sh [--problems-only]
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

GIT_HOOKS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git"   # the copies shipped beside this script
SRC_VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$(dirname "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json" 2>/dev/null | head -1)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { bad "not inside a git repository"; exit 1; }
cd "$ROOT" || exit 1

# Which flight-rules release shipped this exact file? Searches the plugin cache and
# prints the version directory's name, or nothing. The same function sits in
# hooks/git/install.sh, which repairs what this one reports; keep them in step.
release_of() {
  local f="$1" c found=""
  for c in "${HOME:-}"/.claude/plugins/cache/*/flight-rules/*/hooks/git/"$(basename "$f")"; do
    [[ -f "$c" ]] || continue
    cmp -s "$f" "$c" && found="$found$(basename "$(cd "$(dirname "$c")/../.." && pwd)")
"
  done
  [[ -n "$found" ]] || return 1
  # A hook unchanged across releases matches several; the newest is the honest answer
  # (AppliHawk's pre-merge-commit was 0.20.1's, 0.21.1's and 0.22.0's at once). Only
  # dotted-numeric names are ordered — a sha or "latest" as a directory name is not a
  # number and must not sort as the largest one.
  local best; best=$(printf '%s' "$found" | grep -E '^[0-9]+(\.[0-9]+)+$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
  if [[ -n "$best" ]]; then printf '%s' "$best"; else printf '%s' "$found" | head -1; fi
}

# A hook that is present, executable and EMPTY passes every other check here while
# enforcing nothing. doctor already content-checks the agent guard (for a pre-conf copy);
# these are the same idea for the six git hooks — one string each that a real copy must
# contain. It is a grep, so a determined edit defeats it; it catches the stub, the
# truncated copy and the wrong-file-name, which is what actually happens.
hook_marker() {
  case "$1" in
    pre-merge-commit)       printf 'PR_ONLY' ;;
    commit-msg)             printf 'pre-merge-check' ;;
    pre-rebase)             printf 'PR_ONLY' ;;
    post-merge)             printf 'post-merge-note' ;;
    reference-transaction)  printf 'is-ancestor' ;;
    pre-commit)             printf 'PRIVATE KEY' ;;
    # Not a hook: tells flight-rules' install.sh from a project's own — a heuristic,
    # like the rest. The phrase is in the header comment of every revision since it was
    # added (7b7f968, 2026-07-19). merge.ff and core.hooksPath would not do: every
    # flight-rules project is told to set both, so its own installer would match (second
    # review, 2026-10-21). install.sh's hook_marker holds the same table; keep them in
    # step.
    install.sh)             printf 'committed git hooks into git' ;;
    *)                      printf 'flight-rules' ;;
  esac
}

# ── 1. Git hooks: path set, directory present, every bare-named hook executable ──
# --path: git expands a leading ~ in this value. Read raw, ~/x was joined to the repo
# root and a working gate reported as "does not exist".
HOOKS_PATH=$(git config --path core.hooksPath 2>/dev/null || true)
if [[ -z "$HOOKS_PATH" ]]; then
  # A fresh plugin install lands here, and the bare "hooks/git/install.sh" this used to
  # print named a path inside the plugin that the user had no way to find (2026-10-13).
  # With the plugin's own copy beside this script, print the command that installs.
  # A clone of a project that already committed its hooks needs them wired, not
  # replaced: --from would overwrite hooks the project adapted (pre-review, 2026-10-13).
  # The PLUGIN's install.sh does it, never the repo's own copy — a cloned repo can
  # commit any script under that name, and this line is on the user's screen in
  # flight-rules' voice (security review, 2026-10-13). core.hooksPath and merge.ff are
  # per-clone config.
  if [[ -f "$ROOT/.ai/hooks/pre-merge-commit" && -f "$GIT_HOOKS_SRC/install.sh" ]]; then
    # install.sh refuses a set missing any of the six (a 0.22.0 one has no pre-commit),
    # so name the copy first rather than print a command that fails (fix review).
    _cp=""
    for h in pre-merge-commit commit-msg pre-rebase post-merge reference-transaction pre-commit; do
      [[ -f "$ROOT/.ai/hooks/$h" ]] || _cp="$_cp$(printf 'cp %q %q/ && ' "$GIT_HOOKS_SRC/$h" "$ROOT/.ai/hooks")"
    done
    [[ -n "$_cp" ]] && _cp_note=" Commit the hooks it copies in, so the next clone has them."
    bad "$(printf 'core.hooksPath is not set — this clone is not running the hooks committed in .ai/hooks/. To wire them up: %sbash %q   (git config is per clone; it also sets merge.ff false.%s Those hooks then run on your git commands — in a repo you do not trust, read them first)' "$_cp" "$GIT_HOOKS_SRC/install.sh" "${_cp_note:-}")"
  elif [[ -f "$GIT_HOOKS_SRC/install.sh" ]]; then
    bad "$(printf 'core.hooksPath is not set — the git hooks are not installed. To install them into .ai/hooks/: bash %q --from %q   (it also sets merge.ff false; then commit .ai/hooks/)' "$GIT_HOOKS_SRC/install.sh" "$GIT_HOOKS_SRC")"
  else
    bad "core.hooksPath is not set — the merge gate is not installed (flight-rules' hooks/git/install.sh, or: git config core.hooksPath <dir>)"
  fi
else
  HOOKS_DIR="$HOOKS_PATH"; [[ "$HOOKS_DIR" = /* ]] || HOOKS_DIR="$ROOT/$HOOKS_DIR"
  if [[ ! -d "$HOOKS_DIR" ]]; then
    bad "core.hooksPath=$HOOKS_PATH but that directory does not exist — git runs NO hooks"
  else
    ok "core.hooksPath=$HOOKS_PATH"
    for h in pre-merge-commit commit-msg pre-rebase post-merge reference-transaction pre-commit; do
      if [[ ! -f "$HOOKS_DIR/$h" ]]; then
        # A plugin upgrade cannot copy git hooks into a project, so a hook added in a
        # release (pre-commit, 0.23.0) arrives as this line; say where to copy it from.
        # A flight-rules-doctor.sh copied in by hand has no git/ beside it to copy from.
        if [[ -f "$GIT_HOOKS_SRC/$h" ]]; then
          bad "$h missing from $HOOKS_PATH — the gate is half built. Copy it in from this flight-rules: cp '$GIT_HOOKS_SRC/$h' '$HOOKS_PATH/' && chmod +x '$HOOKS_PATH/$h'"
          NEEDS_SYNC=1
        else
          bad "$h missing from $HOOKS_PATH — the gate is half built. Copy it in from flight-rules' hooks/git/ and chmod +x it"
        fi
      elif [[ ! -x "$HOOKS_DIR/$h" ]]; then
        bad "$h is not executable — git ignores it silently (chmod +x, and commit the mode)"
      # Unreadable, or a grep that errors, is a check that could not run — not "no
      # marker", which called the hook a stub and leaked grep's error (fix review, F15).
      # Unreadable is a problem on its own: git cannot run it, so a command it gates
      # fails, and what post-merge does just does not happen (group A fix review, F5).
      elif [[ ! -r "$HOOKS_DIR/$h" ]]; then
        bad "$h is unreadable — git cannot run it, so what it checks does not happen and a command it gates fails; doctor could not check it either (chmod +r, and commit the mode)"
      elif { grep -q "$(hook_marker "$h")" "$HOOKS_DIR/$h" 2>/dev/null; _m=$?; [[ $_m -ne 0 ]]; }; then
        if [[ $_m -ne 1 ]]; then
          warn "$h could not be read (grep exited $_m) — could not check it"
        else
          # pre-commit is the one hook a project is likely to have had already (a linter),
          # and the upgrade to 0.23.0 is when it meets this line; say where it goes.
          _own=""; [[ "$h" == pre-commit ]] && _own=". If it is your project's own pre-commit, rename it pre-commit.local (the flight-rules one runs it after its scan) and copy flight-rules' hooks/git/pre-commit in beside it"
          bad "$h does not look like the flight-rules hook — it is present and executable but has no '$(hook_marker "$h")' in it, so it may be a stub or a stale copy that silently allows everything$_own"
        fi
      # The status is kept, as in install.sh: a grep that errors could not check it, and
      # read as "not adapted", its error on screen (group A fix review, F13).
      elif { grep -qE '^[[:space:]]*#[[:space:]]*flight-rules: adapted' "$HOOKS_DIR/$h" 2>/dev/null; _a=$?; [[ $_a -eq 0 ]]; }; then
        # The project's own version, said so in the file: not compared with the release,
        # and never replaced by HOOK_SYNC=auto. Without the mark, an adapted hook drew a
        # ⚠️ into every session's context with no way to accept it (review, 2026-10-12).
        ok "$h adapted here (marked flight-rules: adapted) — not compared with this release; /rules-sync shows its diff against each new one"
      elif [[ $_a -ne 1 ]]; then
        warn "$h could not be read (grep exited $_a) — could not check it"
      elif [[ -f "$GIT_HOOKS_SRC/$h" ]] && ! cmp -s "$HOOKS_DIR/$h" "$GIT_HOOKS_SRC/$h"; then
        # Present, executable, the right hook — and not this release's. A plugin update
        # cannot touch it, so four hooks sat at 0.22.0 under a 0.23.0 plugin with every
        # line above green (AppliHawk, 2026-10-12). Byte-identical to an older cached
        # release is a stale copy, no doubt about it; matching no release may be the
        # project's own adaptation, which is a question, not a problem.
        if _ver=$(release_of "$HOOKS_DIR/$h"); then
          if [[ -n "$SRC_VERSION" && "$_ver" == "$SRC_VERSION" ]]; then
            # The copy IS the current release's; this doctor runs from a checkout whose
            # hooks/git has moved on since. Only a checkout can show this, never the plugin.
            warn "$h is the released $_ver copy, and this flight-rules checkout carries unreleased changes to it"
          else
            bad "$h is the flight-rules $_ver copy — this flight-rules is ${SRC_VERSION:-newer}, so the hook running here is behind the one you installed"
          fi
        else
          warn "$h differs from this flight-rules' copy (${SRC_VERSION:-hooks/git/$h}) — adapted here on purpose, or a stale copy? diff it against $GIT_HOOKS_SRC/$h; if adapted, add a line '# flight-rules: adapted' to it and this stops"
        fi
        NEEDS_SYNC=1
      else
        ok "$h installed and executable"
      fi
    done
    # The sync updates install.sh with the hooks, so a stale copy is named too: 0.26.0
    # changed only it, and under HOOK_SYNC=report nothing said so (#90). A warning, not a
    # problem — it guards nothing, an old copy works as it did, and the commands printed
    # here run this flight-rules' own. Not one that differs and lacks the marker: it is
    # the project's own installer, and the hint below would have replaced it (batch
    # review, 2026-10-21; install.sh leaves it alone since #97). A check that could not
    # run says so — an unreadable file, or a grep that errors rather than answering,
    # which read as "no marker" and left the file unmentioned (second and third reviews,
    # 2026-10-21).
    # Missing is noted on the full report only, with the cp that restores it: nothing
    # needs it to run the hooks, the sync no longer puts it back unattended, and a
    # project that removed it on purpose would get a warning every day (owner,
    # 2026-10-21).
    if [[ ! -e "$HOOKS_DIR/install.sh" && -f "$GIT_HOOKS_SRC/install.sh" ]]; then
      # From a worktree whose hooks are in another checkout, the cp lands at the same
      # path in this one: written into that checkout, it was an untracked file there that
      # a later merge bringing install.sh in refused to overwrite (#90 fix review, F9).
      # Only when that directory is in this checkout too — untracked there, it is not,
      # and the cp failed (group A fix review, F9) — and resolves inside it: a link back
      # to the other checkout's copy took the cp there (group A fix review round 2, F0).
      _dst="$HOOKS_DIR/install.sh"
      _own=$(cd "$HOOKS_DIR" && git rev-parse --show-toplevel 2>/dev/null)
      _hd=$(cd "$HOOKS_DIR" && pwd -P)
      _cd1=$(cd "$HOOKS_DIR" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)
      _cd2=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)
      _wd=$(cd "$ROOT/${_hd#"$_own"/}" 2>/dev/null && pwd -P)
      if [[ -n "$_own" && "$_own" != "$ROOT" && -n "$_cd1" && "$_cd1" == "$_cd2" && "$_hd" == "$_own"/* \
            && -n "$_wd" && "$_wd" == "$(cd "$ROOT" && pwd -P)"/* ]]; then
        _dst="$ROOT/${_hd#"$_own"/}/install.sh"
      fi
      ok "$(printf 'install.sh is not in %s — nothing needs it to run the hooks; to restore it, on a branch: cp %q %q' "$HOOKS_PATH" "$GIT_HOOKS_SRC/install.sh" "$_dst")"
    elif [[ -f "$HOOKS_DIR/install.sh" && ! -r "$HOOKS_DIR/install.sh" ]]; then
      warn "$HOOKS_PATH/install.sh is unreadable — could not check it"
    # The adapted grep keeps its status, as the hooks' does above: an error read as "not
    # marked" (group A fix review round 2, F1).
    elif [[ -f "$HOOKS_DIR/install.sh" && -f "$GIT_HOOKS_SRC/install.sh" ]] \
       && ! cmp -s "$HOOKS_DIR/install.sh" "$GIT_HOOKS_SRC/install.sh" \
       && { grep -qE '^[[:space:]]*#[[:space:]]*flight-rules: adapted' "$HOOKS_DIR/install.sh" 2>/dev/null; _a=$?; [[ $_a -ne 0 ]]; }; then
      if [[ $_a -ne 1 ]]; then
        warn "$HOOKS_PATH/install.sh could not be read (grep exited $_a) — could not check it"
      elif _ver=$(release_of "$HOOKS_DIR/install.sh"); then
        if [[ -n "$SRC_VERSION" && "$_ver" == "$SRC_VERSION" ]]; then
          warn "install.sh is the released $_ver copy, and this flight-rules checkout carries unreleased changes to it"
        else
          warn "install.sh is the flight-rules $_ver copy — this flight-rules is ${SRC_VERSION:-newer}; only running $HOOKS_PATH/install.sh by hand gets the old one"
        fi
        NEEDS_SYNC=1
      else
        grep -qF "$(hook_marker install.sh)" "$HOOKS_DIR/install.sh"; _m=$?
        if [[ $_m -eq 0 ]]; then
          warn "install.sh differs from this flight-rules' copy (${SRC_VERSION:-hooks/git/install.sh}) — adapted here on purpose, or a stale copy? diff it against $GIT_HOOKS_SRC/install.sh; if adapted, add a line '# flight-rules: adapted' to it and this stops"
          NEEDS_SYNC=1
        elif [[ $_m -ne 1 ]]; then
          warn "$HOOKS_PATH/install.sh could not be read (grep exited $_m) — could not check it"
        fi
      fi
    fi
    if [[ "${NEEDS_SYNC:-0}" -eq 1 ]]; then
      # The --stale-only form is the one printed: this line reaches the user's screen
      # without the ⚠️ beside it, and the bare form overwrote an unmarked adapted hook
      # when run as printed (fix review, 2026-10-13 — reproduced).
      # --this-checkout and "on a branch": the plain form, run in a main checkout on a
      # protected branch, left a diff that could not be committed or cleared there, and
      # from a worktree it sent the user back to that checkout (#99, 2026-10-21).
      printf '     to update: bash %q --from %q --stale-only --this-checkout   (run it on a branch — in a worktree when this checkout is on a protected branch — then commit and merge it; replaces only copies identical to an older release, and copies in missing ones; a hook that differs is left alone and named — diff it, then mark it '"'"'# flight-rules: adapted'"'"' or re-run without --stale-only to replace every copy that differs, adapted ones included. HOOK_SYNC=auto in .ai/flight-rules.conf runs this in the first session each day and after an update)\n' \
        "$GIT_HOOKS_SRC/install.sh" "$GIT_HOOKS_SRC"
    fi
    # The scan runs pre-commit.local only if it is executable, and skips it without a
    # word otherwise — a project's linter would stop running unnoticed.
    if [[ -f "$HOOKS_DIR/pre-commit.local" && ! -x "$HOOKS_DIR/pre-commit.local" ]]; then
      bad "pre-commit.local is not executable — pre-commit skips it silently, so your own pre-commit no longer runs (chmod +x)"
    fi
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
KNOWN='PROTECTED_BRANCHES PR_ONLY_BRANCHES NOTE_GATED_BRANCHES INTEGRATION_BRANCH WORKTREE_DIR MERGE_NEEDS_INSTRUCTION HOOK_SYNC DG_COMIC DG_COMIC_PR DG_WAIT_MINUTES'
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
          # All three are honoured, by three different layers: the agent guard reads
          # PROTECTED_BRANCHES, reference-transaction reads PROTECTED_BRANCHES and
          # PR_ONLY_BRANCHES, commit-msg reads NOTE_GATED_BRANCHES. Calling the latter
          # two errors was false, and it made this script report a problem every day
          # about a correctly configured project.
          case "$key" in
            PROTECTED_BRANCHES)
              warn "$key=$val — no protected branches in the agent guard, branch creation is no longer routed through a worktree, and the ref gate stands down (the secret scan stays on, and PR_ONLY_BRANCHES still refuses local merges and rebases into a PR-only branch)"
              # The note gate's default set is DERIVED from this key — "protected but
              # not PR-only" — so turning protection off empties it. Measured
              # 2026-09-13: a merge landed on an integration branch with no note and
              # nothing said a word. Only worth saying when the project actually
              # integrates somewhere other than the branch it releases from; a
              # trunk-only project has no note-gated branch either way.
              _ib=$(sed -n -E 's/^[[:space:]]*INTEGRATION_BRANCH[[:space:]]*=[[:space:]]*"?([^"[:space:]#]+)"?.*$/\1/p' "$CONF" | tail -1)
              # …unless the integration branch is itself PR-only, in which case local
              # merges into it are refused outright and there is no note gate to lose.
              _pr=$(sed -n -E 's/^[[:space:]]*PR_ONLY_BRANCHES[[:space:]]*=[[:space:]]*"?([^"[:space:]#]+)"?.*$/\1/p' "$CONF" | tail -1)
              _ib_is_pr_only=0
              if [[ -n "$_pr" && "$_pr" != "off" && "$_pr" != "none" && -n "$_ib" ]]; then
                ( shopt -s nocasematch; [[ "$_ib" =~ $_pr ]] ) 2>/dev/null && _ib_is_pr_only=1
              fi
              if ! grep -qE '^[[:space:]]*NOTE_GATED_BRANCHES[[:space:]]*=' "$CONF" \
                 && [[ -n "$_ib" && "$_ib" != "main" && "$_ib_is_pr_only" -eq 0 ]]; then
                warn "…and with NOTE_GATED_BRANCHES unset, that empties the note gate as well — a merge into $_ib needs no pre-merge-check note. Name NOTE_GATED_BRANCHES to keep it"
              fi
              ;;
            PR_ONLY_BRANCHES)    warn "$key=$val — no branch is PR-only: the ref gate, the local merge and rebase gates and the squash guard stand down (PROTECTED_BRANCHES still applies)" ;;
            NOTE_GATED_BRANCHES) warn "$key=$val — no branch requires a pre-merge-check note" ;;
          esac
        elif ( [[ "x" =~ $val ]] ) 2>/dev/null; [[ $? -eq 2 ]]; then
          bad "$key='$val' is not a valid regex — every branch is taken as matching it, so each gate it sets is closed on every branch until it is fixed"
        elif [[ "$val" != ^* ]]; then
          warn "$key='$val' is unanchored — 'main' also matches 'maintenance'; use ^main\$"
        else ok "$key=$val"; fi ;;
      MERGE_NEEDS_INSTRUCTION)
        [[ "$val" == "off" ]] && warn "$key=off — a merge into a protected branch no longer needs the user's say-so (recorded in each merge commit's Merge-authorisation trailer)" \
                              || ok "$key=$val" ;;
      HOOK_SYNC)
        case "$val" in
          auto)   ok "$key=auto — the first session each day, and after a plugin update, replaces git hooks that are byte-identical to an older release, and leaves the diff for you to commit" ;;
          report) ok "$key=report" ;;
          *)      warn "$key='$val' is neither auto nor report — session-start treats it as report and syncs nothing" ;;
        esac ;;
      DG_COMIC)
        case "$val" in
          always|never) ok "$key=$val" ;;
          *) warn "$key='$val' is neither always nor never — /dg treats it as always and ends every verdict with the comic" ;;
        esac ;;
      DG_COMIC_PR)
        case "$val" in
          never|ask|always) ok "$key=$val" ;;
          *) warn "$key='$val' is not never, ask or always — /dg treats it as never and keeps the comic out of PRs" ;;
        esac ;;
      DG_WAIT_MINUTES)
        if [[ "$val" =~ ^0*[1-9][0-9]*$ ]]; then ok "$key=$val"
        else warn "$key='$val' is not a positive whole number of minutes — /dg treats it as 15 and stops waiting for a pre-review after that"; fi ;;
      *) ok "$key=$val" ;;
    esac
  done < "$CONF"
  # NOTE_GATED_BRANCHES is the one key with no default names — unset, the gated set
  # is "protected but not PR-only". That is the right default, and it is invisible:
  # an owner cannot tell from the conf whether their second protected branch needs a
  # stamp. Silence about a rule that IS in force is the "looks installed" failure
  # this script exists to catch, so say what the derivation came to.
  if ! grep -qE '^[[:space:]]*NOTE_GATED_BRANCHES[[:space:]]*=' "$CONF"; then
    _prot=$(sed -n -E 's/^[[:space:]]*PROTECTED_BRANCHES[[:space:]]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/p' "$CONF" | tail -1)
    _pronly=$(sed -n -E 's/^[[:space:]]*PR_ONLY_BRANCHES[[:space:]]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/p' "$CONF" | tail -1)
    if [[ -z "$_prot" || "$_prot" == "off" ]]; then
      ok "NOTE_GATED_BRANCHES unset — nothing is note-gated (no protected set)"
    elif [[ "$_prot" == "$_pronly" ]]; then
      ok "NOTE_GATED_BRANCHES unset — nothing is note-gated (every protected branch is PR-only)"
    else
      ok "NOTE_GATED_BRANCHES unset — derived: protected ($_prot) minus PR-only ($_pronly) needs a pre-merge-check note"
    fi
  fi
fi

# ── 4. The guard is wired once, not twice ─────────────────────────────────────
PLUGIN_ON=0
# `"flight-rules@x": false` contains the name too. Match the VALUE, or a disabled plugin
# reports as a wired guard. Claude Code writes `enabledPlugins` to the user-level file
# for a user-scope install and to the repo's .claude/settings.json or
# .claude/settings.local.json for a project-scope one (#67): reading only ~/.claude
# declared the guard absent in a repo where it was running.
# settings.local.json is git-ignored, so only the checkout that wrote it has one, and
# Claude Code applies the MAIN worktree's to a session in any linked worktree (probe,
# 2026-10-19: a plugin enabled only there loaded in a nested and a sibling worktree, and
# not in an unrelated repo). Reading only this checkout's warned "no agent guard" in
# every worktree of such a project (#88). `worktree list` names the main worktree first.
MAIN_LOCAL=/dev/null
MAIN_WT=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
[[ -n "$MAIN_WT" && "$MAIN_WT" != "$ROOT" ]] && MAIN_LOCAL="$MAIN_WT/.claude/settings.local.json"
grep -qsE '"flight-rules@[^"]*"[[:space:]]*:[[:space:]]*true' \
  "$HOME/.claude/settings.json" .claude/settings.json .claude/settings.local.json "$MAIN_LOCAL" 2>/dev/null && PLUGIN_ON=1
LOCAL_WIRED=0
grep -qs 'pre-commit-check.sh' .claude/settings.json 2>/dev/null && LOCAL_WIRED=1
# Wiring a path is not the same as wiring a FILE. Every script named in the settings is
# checked for existence — a dangling path satisfies the grep above just as well as a real
# one, and the hook then silently never runs.
# A captured path, with its root marker, as a file to test and as a name to report.
wired_file() { case "$1" in @ROOT@/*) printf '%s' "$ROOT/${1#@ROOT@/}" ;; @HOME@/*) printf '%s' "$HOME/${1#@HOME@/}" ;;
                            /*) printf '%s' "$1" ;; *) printf '%s' "$ROOT/$1" ;; esac; }
wired_name() { printf '%s' "$1" | sed 's#@ROOT@/##g; s#@HOME@/#~/#g'; }
if [[ -f .claude/settings.json ]]; then
  while IFS= read -r cap; do
    [[ -z "$cap" ]] && continue
    case "$cap" in *@LITERAL@/*)
      bad ".claude/settings.json wires …/${cap#*@LITERAL@/} under a quoted \$VAR or ~, which the shell never expands — that hook never runs"
      continue ;; esac
    # A quoted capture with a space is a path with a space in it, or a wrapper and its
    # hook (`bash -c '/usr/bin/env bash ./hooks/x.sh'`); the text cannot tell them apart,
    # so either one existing is enough. Missing, the hook is named: the last word when it
    # starts like a path, else the whole.
    tail="${cap##* }"
    [[ "$tail" = @PLUGIN@/* ]] && continue
    [[ -f "$(wired_file "$cap")" || -f "$(wired_file "$tail")" ]] && continue
    case "$tail" in /*|.*|@*) [[ "$tail" = "$cap" ]] || cap="$tail" ;; esac
    bad ".claude/settings.json wires $(wired_name "$cap"), which does not exist — that hook never runs"
    # The whole path before `hooks/` is captured, not a list of known prefixes: the list
    # knew `.ai/` and missed `.claude/`, so `.claude/hooks/x.sh` was tested as `hooks/x.sh`
    # and reported missing while it ran (#66). A root prefix is marked first, then
    # captured with the path: `$(git rev-parse --show-toplevel)` IS $ROOT, and so is any
    # `$VAR` or `${VAR}` — $CLAUDE_PROJECT_DIR, Claude Code's documented form, or the
    # `R=$(git rev-parse --show-toplevel); … "$R/hooks/x.sh"` idiom this repo's own wiring
    # uses. ${CLAUDE_PLUGIN_ROOT} lives in the installed plugin, not here, and is dropped
    # rather than reported as missing. A closing quote may sit between the prefix and
    # its `/` (`"$CLAUDE_PROJECT_DIR"/.claude/hooks/x.sh`); unmarked, those captured as
    # the absolute `/.claude/hooks/x.sh` and were reported missing (/dg, 2026-10-08).
    # `$HOME`, `${HOME}` and a `~` the shell expands (unquoted, starting a word) are the
    # home directory; tested under the repo, a hook missing from home passed whenever the
    # repo held the same path. A `$VAR` or `~` inside single quotes, or `~` inside double
    # quotes, is never expanded — except a `bash -c '…'` script, which its own shell
    # expands — so that hook never runs, and is reported whatever exists. A quoted capture
    # runs quote to quote, spaces included; unquoted, a space ends it, as it does for the
    # shell (/dg G2-5, 2026-10-08; reviewed 2026-10-12).
  done < <(sed -E 's#\$\{?CLAUDE_PLUGIN_ROOT\}?(\\")?/#@PLUGIN@/#g
                   s#-c '"'"'\$#-c '"'"'@DOLLAR@#g
                   s#'"'"'\$\{?[A-Za-z_][A-Za-z0-9_]*\}?'"'"'?/#'"'"'@LITERAL@/#g
                   s#@DOLLAR@#$#g
                   s#(\\"|'"'"')~/#\1@LITERAL@/#g
                   s#\$\{?HOME\}?(\\")?/#@HOME@/#g
                   s#(^|[^\\])"~/#\1"@HOME@/#g
                   s#([ =;(|&])~/#\1@HOME@/#g
                   s#\$\(git rev-parse --show-toplevel\)(\\")?/#@ROOT@/#g
                   s#\$\{?[A-Za-z_][A-Za-z0-9_]*\}?(\\")?/#@ROOT@/#g' .claude/settings.json \
           | grep -oE '\\"[A-Za-z0-9_./@ -]*hooks/[A-Za-z0-9_/ -]*\.sh\\"|'"'"'[A-Za-z0-9_./@ -]*hooks/[A-Za-z0-9_/ -]*\.sh'"'"'|(@[A-Z]+@/)?[A-Za-z0-9_./-]*hooks/[A-Za-z0-9_/-]*\.sh' \
           | sed -E 's#^(\\"|'"'"')##; s#(\\"|'"'"')$##' \
           | grep -v '^@PLUGIN@' | sort -u)
fi
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

# ── 5. No command or skill of the user's or project's own shadows a plugin skill ──
# One named like a plugin skill is what `/dg` runs, and the plugin's stays unreached:
# AppliHawk's ~/.claude/commands/dg.md, a copy from 2026-06-11, ran in place of every
# release's /dg after it with nothing said (2026-10-13). A file whose line STARTS with a
# pointer at a skills/<name>/SKILL.md (a project's copy-in, or this repo's own pointers:
# "Read and follow `…skills/<name>/SKILL.md`") or a handover to the plugin's skill
# (AppliHawk's wrappers, flagged on the first real run, 2026-10-17: "Use the
# `flight-rules:<name>` skill") is no shadow. The string anywhere else is not enough: a
# full copy that mentions it in passing still runs its own steps (#82). A command nested
# in commands/<dir>/ registers as /<dir>:<name> and leaves /<name> to the plugin, so it
# is not checked (probe, 2026-10-19, #85). Only with the plugin on: off, its skills are
# not in use.
SKILLS_SRC="$(cd "${GIT_HOOKS_SRC%/git}/../skills" 2>/dev/null && pwd)"   # GIT_HOOKS_SRC was made absolute before the cd to $ROOT
if [[ $PLUGIN_ON -eq 1 && -n "$SKILLS_SRC" ]]; then
  for _s in "$SKILLS_SRC"/*/SKILL.md; do
    [[ -f "$_s" ]] || continue
    _n=$(basename "$(dirname "$_s")")
    for _f in "$HOME/.claude/commands/$_n.md" "$HOME/.claude/skills/$_n/SKILL.md" \
              ".claude/commands/$_n.md" ".claude/skills/$_n/SKILL.md"; do
      [[ -f "$_f" ]] || continue
      grep -qE -e '^Read and follow `([^`]*/)?skills/'"$_n"'/SKILL\.md`' \
               -e '^Use the `flight-rules:'"$_n"'` skill' "$_f" && continue
      # Not ${_f/#$HOME/~}: bash 5 tilde-expands that replacement back to $HOME, and
      # escaping it prints "\~" on bash 3.2 (Ubuntu CI, 2026-10-17).
      case "$_f" in "$HOME"/*) _f="~/${_f#"$HOME"/}" ;; esac
      warn "$_f shadows flight-rules' /$_n — /$_n runs that file, not this release's skill; delete or rename it if it is an old copy (/flight-rules:$_n reaches the plugin's either way)"
    done
  done
fi

echo
if [[ $FAIL -gt 0 ]]; then printf '%d problem(s), %d warning(s)\n' "$FAIL" "$WARN"; exit 1; fi
[[ $QUIET -eq 1 && $WARN -eq 0 ]] || printf 'enforcement installed: %d warning(s)\n' "$WARN"
exit 0
