#!/usr/bin/env bash
# Wire the repo's committed git hooks into git — and, with --from, bring them up to
# date first. Run from anywhere inside the repo:
#   bash .ai/hooks/install.sh                               # one-time setup
#   bash <flight-rules>/hooks/git/install.sh --from <flight-rules>/hooks/git
#                                                           # after a plugin update
#                                                           # (a worktree: --this-checkout)
#   … --from <dir> --stale-only                             # what HOOK_SYNC=auto runs
#   … --from <dir> --stale-only --check-only                # …on a protected branch
#   … --from <dir> --stale-only --this-checkout             # a worktree's own copy
#   … --from <dir> --this-checkout                          # …replacing what differs
#
# A plugin update refreshes the agent hooks but cannot touch these: they are the
# project's own committed files (AppliHawk, 2026-10-12: four hooks stayed at 0.22.0
# after the update to 0.23.0, and the new pre-commit never arrived). --from copies the
# six hooks and this script in from the release named, then installs as usual. The
# result is a working-tree diff for the owner to review and commit.
#
# --stale-only overwrites a hook only when it is byte-identical to some release in the
# plugin cache — provably unmodified — and copies in one that is missing. A copy that
# matches no release may be the project's own adaptation, so it is left alone and
# named. Without --stale-only every differing hook is replaced, except a pre-commit
# that is not flight-rules' at all (a linter): that one is refused with the rename
# that keeps it running.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOKS='pre-merge-commit post-merge commit-msg pre-rebase reference-transaction pre-commit'

FROM=""; STALE_ONLY=0; CHECK_ONLY=0; THIS_CHECKOUT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --from) [ $# -ge 2 ] || { echo "❌ --from needs a directory"; exit 1; }; FROM="$2"; shift 2 ;;
        --stale-only) STALE_ONLY=1; shift ;;
        --check-only) CHECK_ONLY=1; shift ;;
        --this-checkout) THIS_CHECKOUT=1; shift ;;
        *) echo "❌ unknown argument: $1 (usage: install.sh [--from <dir> [--stale-only [--check-only]] [--this-checkout]])"; exit 1 ;;
    esac
done
[ "$STALE_ONLY" -eq 1 ] && [ -z "$FROM" ] && { echo "❌ --stale-only needs --from <dir>"; exit 1; }
[ "$CHECK_ONLY" -eq 1 ] && [ "$STALE_ONLY" -eq 0 ] && { echo "❌ --check-only needs --stale-only"; exit 1; }
[ "$THIS_CHECKOUT" -eq 1 ] && [ -z "$FROM" ] && { echo "❌ --this-checkout needs --from <dir>"; exit 1; }

# The directory git runs hooks from. LOCAL config only: the global one can name a
# directory outside every repo (~/.githooks), and a sync that followed it wrote seven
# files there and pointed this repo at them (review, 2026-10-12). A relative value is
# resolved against this checkout — a worktree's own copy, as git resolves it. --path,
# because git expands a leading ~: read raw, ~/x was joined to the repo root and an
# install wrote the hooks into a literal "~" directory there.
HOOKS_PATH=$(git config --local --path core.hooksPath 2>/dev/null || true)
HOOKS_DIR="$REPO_ROOT/.ai/hooks"; PATH_IS_SET=0
if [ -n "$HOOKS_PATH" ]; then
    PATH_IS_SET=1
    case "$HOOKS_PATH" in /*) HOOKS_DIR="$HOOKS_PATH" ;; *) HOOKS_DIR="$REPO_ROOT/$HOOKS_PATH" ;; esac
fi
# A path as `pwd -P` spells it, resolved through its nearest existing ancestor: a
# directory not made yet resolved to nothing, so the worktree refusal below missed a
# missing hooks directory in the main checkout and mkdir -p made it there (group A fix
# review round 3, 2026-10-22, V2).
resolved() {
    local d="$1" t=""
    [ "$d" = / ] || d="${d%/}"
    while [ ! -d "$d" ]; do t="/${d##*/}$t"; d=$(dirname "$d"); done
    printf '%s%s' "$(cd "$d" && pwd -P)" "$t"
}
inside() { case "$(resolved "$1")" in "$(cd "$2" && pwd -P)"/*) return 0 ;; esac; return 1; }
inside_repo() { inside "$1" "$REPO_ROOT"; }
# The main worktree's path, from a linked worktree; nothing in the main one itself, or
# when the main one is bare. It is the first entry `git worktree list` prints.
main_checkout() {
    local m; m=$(git worktree list --porcelain 2>/dev/null \
        | awk 'NR==1 && /^worktree /{w=substr($0,10)} /^$/{exit} $0=="bare"{b=1} END{if (w!="" && !b) print w}')
    [ -n "$m" ] && [ "$(cd "$m" 2>/dev/null && pwd -P)" != "$(cd "$REPO_ROOT" && pwd -P)" ] && printf '%s' "$m"
}

# Which flight-rules release shipped this exact file? Searches the plugin cache and
# prints the newest release's version directory, or nothing. The same function sits in
# flight-rules-doctor.sh, which reports what this one repairs; keep them in step.
release_of() {
    local f="$1" c found=""
    for c in "${HOME:-}"/.claude/plugins/cache/*/flight-rules/*/hooks/git/"$(basename "$f")"; do
        [ -f "$c" ] || continue
        cmp -s "$f" "$c" && found="$found$(basename "$(cd "$(dirname "$c")/../.." && pwd)")
"
    done
    [ -n "$found" ] || return 1
    # A hook unchanged across releases matches several; the newest is the honest answer
    # (AppliHawk's pre-merge-commit was 0.20.1's, 0.21.1's and 0.22.0's at once). Only
    # dotted-numeric names are ordered — a sha or "latest" as a directory name is not a
    # number and must not sort as the largest one.
    local best; best=$(printf '%s' "$found" | grep -E '^[0-9]+(\.[0-9]+)+$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)
    if [ -n "$best" ]; then printf '%s' "$best"; else printf '%s' "$found" | head -1; fi
}

# MAIN here, not only on the --stale-only path: it is read on every path below, and one
# exported by the caller made a plain install a silent no-op (#93 batch review, B1).
SYNCED=0; LEFT=0; MAIN=""; ACTIVE="Active hooks"
if [ -n "$FROM" ]; then
    [ -d "$FROM" ] || { echo "❌ --from $FROM is not a directory"; exit 1; }
    FROM=$(cd "$FROM" && pwd -P)
    for h in $HOOKS install.sh; do
        [ -f "$FROM/$h" ] || { echo "❌ $FROM/$h is missing — not a complete flight-rules hooks/git/"; exit 1; }
    done
    # `|| true`: under set -e with pipefail, a source with no plugin.json beside it
    # (a checkout, not a plugin) must mean "no version", not an exit.
    FROM_VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$FROM/../../.claude-plugin/plugin.json" 2>/dev/null | head -1 || true)
    # --this-checkout without --stale-only takes this path too: it is the full replace
    # doctor's hint points at for a hook left alone as differing. Without it, that
    # command run in a worktree wrote into the main checkout (group A fix review, F1).
    if [ "$STALE_ONLY" -eq 1 ] || [ "$THIS_CHECKOUT" -eq 1 ]; then
        # The sync and --this-checkout update only an install that exists, inside this
        # repo. Installing from nothing is the owner's step; a directory outside the
        # repo is not this repo's to write; a missing one is doctor's to report.
        [ "$PATH_IS_SET" -eq 1 ] || { echo "❌ no local core.hooksPath — nothing is installed here to update (run install.sh --from <dir>, with neither --stale-only nor --this-checkout, to install)"; exit 1; }
        [ -d "$HOOKS_DIR" ] || { echo "❌ core.hooksPath=$HOOKS_PATH does not exist — git runs no hooks; not touched"; exit 1; }
        # From a linked worktree, the usual install — an absolute path into the main
        # checkout, which every worktree shares — is in the repository but not in this
        # worktree. It is not synced from here: the write would land in another
        # checkout's working tree. Said as such, with the command to run there: "outside
        # this repository; sync it by hand" was wrong on both counts (#87, 2026-10-18).
        # Said only when something there is stale or missing, after the comparison
        # below: said every time, a worktree session warned daily over current hooks
        # (#93, 2026-10-21).
        if ! inside_repo "$HOOKS_DIR"; then
            MAIN=$(main_checkout || true)
            if [ -z "$MAIN" ] || ! inside "$HOOKS_DIR" "$MAIN"; then
                echo "❌ core.hooksPath=$HOOKS_PATH is outside this repository — not touched; sync it by hand"; exit 1
            fi
            # --this-checkout: the same files at the same path in THIS checkout — the
            # copy a branch commits, which a merge then brings to the main checkout. The
            # way to land an update when the main checkout is on a protected branch: told
            # to run there, a worktree session was sent back to the branch nothing can be
            # committed on (#99, 2026-10-21). Git runs the main checkout's copy meanwhile.
            if [ "$THIS_CHECKOUT" -eq 1 ]; then
                _rel=$(cd "$HOOKS_DIR" && pwd -P); _rel=${_rel#"$(cd "$MAIN" && pwd -P)"/}
                [ -d "$REPO_ROOT/$_rel" ] || { echo "❌ $_rel is not in this checkout — nothing here to update (is it committed in the main checkout?)"; exit 1; }
                # Resolved, not only present: a link there to the main checkout's copy
                # took the write back into it (group A fix review round 2, F0).
                # With the way on: a refusal that named only its cause left the next step
                # to guess (round 3, V5).
                inside_repo "$REPO_ROOT/$_rel" || {
                    echo "❌ $_rel in this checkout leads to $(cd "$REPO_ROOT/$_rel" && pwd -P), outside it — not touched."
                    echo "   Replace the link with the committed directory (rm the link, then git checkout -- $_rel) and re-run, or update the main checkout's copy there, on a branch."
                    exit 1
                }
                HOOKS_DIR="$REPO_ROOT/$_rel"; MAIN=""; ACTIVE="This checkout's copy (git runs the main checkout's until it is merged there)"
                echo "   updating this checkout's copy, $_rel — git runs the main checkout's until this is merged there"
            fi
        fi
    # The plain form, from a linked worktree whose hooks are in the main checkout, wrote
    # into that checkout's working tree — the docs said to run it (group A fix review
    # round 2, 2026-10-22, D1). Refused before anything is compared, with both ways on.
    elif [ "$PATH_IS_SET" -eq 1 ] && ! inside_repo "$HOOKS_DIR" && _m=$(main_checkout) && inside "$HOOKS_DIR" "$_m"; then
        echo "❌ core.hooksPath=$HOOKS_PATH is in the main checkout, $_m — not written from this worktree. To update this worktree's copy, on its branch, then commit and merge it:"
        printf '   bash %q --from %q --this-checkout\n' "$FROM/install.sh" "$FROM"
        echo "   To update the main checkout's copy instead, run the command without --this-checkout there, on a branch."
        exit 1
    fi
    mkdir -p "$HOOKS_DIR"
    if [ "$FROM" = "$(cd "$HOOKS_DIR" && pwd -P)" ]; then
        echo "✅ $HOOKS_DIR is the source itself — nothing to sync"
        exit 0
    fi
    # Decide everything before copying anything, so a refusal leaves the directory as
    # it was rather than half updated.
    # Nothing is written from a worktree into the main checkout (MAIN), nor with
    # --check-only, which session-start passes on a protected branch, where the diff
    # could not be committed (#99): the comparison runs, and what is behind is named.
    NOWRITE=0; { [ -n "${MAIN:-}" ] || [ "$CHECK_ONLY" -eq 1 ]; } && NOWRITE=1
    TO_COPY=""; ACT=updating; [ "$NOWRITE" -eq 1 ] && ACT=stale
    for h in $HOOKS install.sh; do
        src="$FROM/$h"; dst="$HOOKS_DIR/$h"
        if [ ! -f "$dst" ]; then
            # A missing install.sh is not put back unattended: nothing needs it to run
            # the hooks, a project may have removed it on purpose, and from a worktree it
            # sent everyone to the main checkout every day (second review, C1). Doctor
            # names it, with the cp that restores it (owner, 2026-10-21). A missing hook
            # is still copied in. The full install still restores it.
            [ "$STALE_ONLY" -eq 1 ] && [ "$h" = install.sh ] && continue
            [ "$NOWRITE" -eq 0 ] || echo "   $h: missing"
            TO_COPY="$TO_COPY $h"
        elif cmp -s "$src" "$dst"; then
            :
        # A file this script cannot read is one it could not check — not stale, not
        # differing, not the project's own (third review, E3: an unreadable install.sh
        # was told to mark itself adapted, while doctor called it unreadable).
        elif [ "$STALE_ONLY" -eq 1 ] && [ ! -r "$dst" ]; then
            echo "   $h: unreadable — could not check it; left alone"
            LEFT=$((LEFT+1))
        elif [ "$STALE_ONLY" -eq 1 ]; then
            if ver=$(release_of "$dst"); then
                echo "   $h: the flight-rules $ver copy — $ACT"
                TO_COPY="$TO_COPY $h"
            # An install.sh without this header phrase is the project's own script, not
            # an edited copy of flight-rules': no stale copy, and not one to tell anyone
            # to mark `adapted` (second review, C4). The phrase is in every revision of
            # this file; flight-rules-doctor.sh's hook_marker holds the same one — keep
            # them in step. A heuristic, not a signature. The full install still
            # replaces such a file: #97. Exit 1 only — no match — so a grep that fails
            # (an unreadable file) is not taken for "the project's own" and skipped.
            elif [ "$h" = install.sh ] && { grep -qF 'committed git hooks into git' "$dst"; [ $? -eq 1 ]; }; then
                :
            # A comment line of its own, `# flight-rules: adapted`: the phrase also sits in
            # this script's text, so an unanchored match took an edited install.sh as
            # marked by nobody (release review, 2026-10-12). Same pattern in doctor.
            # The status is kept: a grep that errors on a readable file (I/O, a race)
            # could not check it, and was reported as "differs" (fix review, F14).
            elif { grep -qE '^[[:space:]]*#[[:space:]]*flight-rules: adapted' "$dst"; _a=$?; [ "$_a" -eq 0 ]; }; then
                echo "   $h: adapted here (marked flight-rules: adapted) — left alone"
                LEFT=$((LEFT+1))
            elif [ "$_a" -ne 1 ]; then
                echo "   $h: could not be read (grep exited $_a) — could not check it; left alone"
                LEFT=$((LEFT+1))
            else
                echo "   $h: differs from every flight-rules release in the plugin cache — left alone (adapted here? diff it against $src, and add a line '# flight-rules: adapted' if so)"
                LEFT=$((LEFT+1))
            fi
        # 'PRIVATE KEY' is what makes a pre-commit flight-rules' — the same marker
        # flight-rules-doctor.sh's hook_marker holds for it; keep them in step.
        elif [ "$h" = pre-commit ] && ! grep -q 'PRIVATE KEY' "$dst"; then
            echo "❌ $dst is not flight-rules' pre-commit (a linter? lint-staged?) and would be lost."
            echo "   Rename it first (merge by hand if a .local exists) and re-run: the flight-rules one runs it after a clean scan."
            # A line of its own, %q not '…': it is pasted (0.26.0 fix review).
            printf '   mv -n %q %q\n' "$dst" "$dst.local"
            exit 1
        else
            TO_COPY="$TO_COPY $h"
        fi
    done
    if [ "$CHECK_ONLY" -eq 1 ]; then
        [ -n "$TO_COPY" ] || exit 0
        exit 3   # behind or missing, nothing written: the caller says why
    fi
    if [ -n "${MAIN:-}" ]; then
        [ -n "$TO_COPY" ] || exit 0
        echo "❌ core.hooksPath=$HOOKS_PATH is in the main checkout, $MAIN, which this worktree shares — not touched from here, because the write would land in that checkout's working tree. To update this worktree's copy instead, on its branch, then commit and merge it:"
        # %q, not "…": the line is pasted, and a path holding `$(…)` ran when it was
        # (0.26.0 release review). Not `cd <main> && …`: a main checkout on a protected
        # branch is where the diff could not be committed (#99).
        printf '   bash %q --from %q --stale-only --this-checkout\n' "$FROM/install.sh" "$FROM"
        exit 1
    fi
    # Via a temporary name: when this script is the project's copy, install.sh is
    # itself one of the files, and bash reads a running script incrementally. mv swaps
    # the inode; the running shell keeps the old one. A failed cp or mv is an exit, not
    # a "synced" line over a file that did not change (review, 2026-10-12) — `a && b`
    # is exempt from set -e — and the temp name is removed on any exit.
    trap 'rm -f "$HOOKS_DIR"/.*.sync.$$' EXIT
    for h in $TO_COPY; do
        cp "$FROM/$h" "$HOOKS_DIR/.$h.sync.$$" || { echo "❌ could not write $h into $HOOKS_DIR"; exit 1; }
        mv -f "$HOOKS_DIR/.$h.sync.$$" "$HOOKS_DIR/$h" || { echo "❌ could not replace $h in $HOOKS_DIR"; exit 1; }
        echo "   synced $h${FROM_VERSION:+ (flight-rules $FROM_VERSION)}"
        SYNCED=$((SYNCED+1))
    done
fi

# commit-msg carries the note gate. Without it, pre-merge-commit blocks PR-only
# branches but nothing enforces the pre-merge-check note — a half-built gate that
# still looks installed. Fail loudly rather than degrade silently.
for required in $HOOKS; do
    if [ ! -f "$HOOKS_DIR/$required" ]; then
        echo "❌ $HOOKS_DIR/$required is missing — copy it in before installing."
        [ "$required" = "commit-msg" ] && echo "   Without it the note gate never runs and merges go unchecked."
        [ "$required" = "pre-rebase" ] && echo "   Without it a PR-only branch can be rewritten with a local rebase."
        [ "$required" = "pre-commit" ] && echo "   Without it nothing scans what \`git add f && git commit\` or \`commit -a\` stages for a key."
        [ "$required" = "reference-transaction" ] && echo "   Without it cherry-pick, revert, branch -f, update-ref and a CONFLICTED merge all reach a PR-only branch unguarded."
        exit 1
    fi
    chmod +x "$HOOKS_DIR/$required"
done
[ -f "$HOOKS_DIR/install.sh" ] && chmod +x "$HOOKS_DIR/install.sh"

# Point git at the hooks directory — once. A path already set is left exactly as it
# is: rewriting it absolute from a worktree put the worktree's path into the SHARED
# repo config, and when the worktree was removed git ran no hooks in any checkout
# (review, 2026-10-12). A fresh install writes a path relative to the repo root when
# the directory is inside it, so every worktree resolves its own copy.
if [ "$PATH_IS_SET" -eq 0 ]; then
    if inside_repo "$HOOKS_DIR"; then
        git config core.hooksPath "${HOOKS_DIR#"$REPO_ROOT"/}"
    else
        git config core.hooksPath "$HOOKS_DIR"
    fi
fi

# Disable fast-forward merges so pre-merge-commit always fires on merge
git config merge.ff false

echo "✅ git hooks installed"
echo "   core.hooksPath = $(git config --local core.hooksPath)"
echo ""
echo "   $ACTIVE:"
for f in "$HOOKS_DIR"/*; do
    [[ -d "$f" ]] && continue                    # a project's own agent/ scripts are not git hooks
    [[ "$(basename "$f")" == *.* ]] && continue  # skip .sh/.md — git only runs bare hook names
    echo "     $(basename "$f")"
done
if [ "$SYNCED" -gt 0 ]; then
    echo ""
    echo "   $SYNCED file(s) updated in $HOOKS_DIR — review \`git diff\` there and commit them, so every clone gets them."
fi
[ "$LEFT" -gt 0 ] && echo "   $LEFT hook(s) left as they were — see above."
exit 0
