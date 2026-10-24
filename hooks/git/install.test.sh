#!/usr/bin/env bash
# Tests for install.sh — the one-time wiring, and `--from`, the sync a plugin update
# cannot do for itself. Every case is a project state from 2026-10-12: four hooks at
# 0.22.0 under a 0.23.0 plugin, a pre-commit that never arrived, a linter's pre-commit
# that a blind copy would have destroyed.
# Run: ./install.test.sh [<hooks/git dir under test>]   (no args, no network; throwaway repos)
set -uo pipefail
H="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PASS=0; FAIL=0
say() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✅ $3"; else FAIL=$((FAIL+1)); echo "  ❌ $3 (got '$1', want '$2')"; fi; }
MAINPID=$$
trap 'printf "\n%s\n" "ABORTED: a fixture could not be built — no result above is meaningful" >&2; exit 2' TERM
die() { printf '  ❌ harness: %s\n' "$1" >&2; kill -s TERM "$MAINPID"; exit 2; }

HOOKS='pre-merge-commit post-merge commit-msg pre-rebase reference-transaction pre-commit'

# A "plugin" directory laid out as the cache has it: <root>/hooks/git/* and
# <root>/.claude-plugin/plugin.json, so install.sh can name the version it syncs from.
mkplugin() {
  local t; t=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$t/hooks/git" "$t/.claude-plugin"
  for h in $HOOKS install.sh; do cp "$H/$h" "$t/hooks/git/$h" || die "could not copy $h into the fake plugin"; done
  printf '{ "name": "flight-rules", "version": "9.9.9" }\n' > "$t/.claude-plugin/plugin.json"
  printf '%s' "$t"
}
# A project with the hooks installed, and a HOME whose plugin cache holds one older
# release, 0.0.1, so a copy can be provably stale. The older release is the current
# file plus a trailing comment: differs from current, identical to nothing else.
mkrepo() {
  local d; d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main || die "git init failed in $d"
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  mkdir -p "$d/.ai/hooks" "$d/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git"
  for h in $HOOKS install.sh; do
    cp "$H/$h" "$d/.ai/hooks/$h" || die "could not copy $h into the fixture"
    { cat "$H/$h"; echo "# flight-rules 0.0.1"; } > "$d/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/$h"
  done
  chmod +x "$d"/.ai/hooks/*
  git -C "$d" config core.hooksPath .ai/hooks
  git -C "$d" config merge.ff false
  for h in $HOOKS; do [ -x "$d/.ai/hooks/$h" ] || die "$h missing or not executable in the fixture"; done
  printf '%s' "$d"
}
# make_stale <repo> <hook>: the project's copy becomes the cached 0.0.1 one.
make_stale() { cp "$1/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/$2" "$1/.ai/hooks/$2"; }
# make_adapted <repo> <hook>: the project's copy differs from every release.
make_adapted() { echo "# this project's own change" >> "$1/.ai/hooks/$2"; }
# run <repo> <args…> → "<exit>\n<output>", with HOME at the fixture's fake home.
run() { local d="$1"; shift; local out rc; out=$(cd "$d" && HOME="$d/fakehome" bash "$@" 2>&1); rc=$?; printf '%s\n%s' "$rc" "$out"; }
rc()  { run "$@" | head -1; }
has() { local want="$1"; shift; run "$@" | tail -n +2 | grep -qF -- "$want"; echo $?; }
same() { cmp -s "$1" "$2" && echo same || echo differs; }
# sums <dir>: every file's checksum, dotfiles included — `cksum *` skipped them, and a
# leftover .h.sync.$$ temp file is one (#93 batch review, B6).
sums() { (cd "$1" && find . -type f -exec cksum {} + | sort); }

echo "Plain install still wires the hooks:"
D=$(mkrepo); git -C "$D" config --unset core.hooksPath; git -C "$D" config --unset merge.ff
say "$(rc "$D" .ai/hooks/install.sh)" "0" "install.sh exits 0"
say "$(git -C "$D" config core.hooksPath)" ".ai/hooks" "…sets core.hooksPath to .ai/hooks, relative, when nothing is set"
say "$(git -C "$D" config merge.ff)" "false" "…and merge.ff=false"
rm -rf "$D"

# Re-running install.sh on a project that keeps its hooks elsewhere re-pointed
# core.hooksPath at .ai/hooks, where there was nothing, so git ran no hooks.
D=$(mkrepo); mv "$D/.ai/hooks" "$D/.githooks"; git -C "$D" config core.hooksPath .githooks
say "$(rc "$D" .githooks/install.sh)" "0" "install.sh runs where core.hooksPath already points"
say "$(git -C "$D" config core.hooksPath)" ".githooks" "…and keeps that directory, as set"
say "$([ -d "$D/.ai/hooks" ] && echo created || echo absent)" "absent" "…without creating .ai/hooks"
rm -rf "$D"

echo "--from: a missing hook is copied in, executable:"
D=$(mkrepo); P=$(mkplugin); rm "$D/.ai/hooks/pre-commit"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "0" "exit 0"
say "$(grep -c 'synced pre-commit (flight-rules 9.9.9)' <<<"$OUT")" "1" "says it synced pre-commit, naming the release"
say "$([ -x "$D/.ai/hooks/pre-commit" ] && echo yes)" "yes" "pre-commit is there and executable"
say "$(same "$D/.ai/hooks/pre-commit" "$P/hooks/git/pre-commit")" "same" "…and is the source's copy"
say "$(grep -c 'updated in .*commit them' <<<"$OUT")" "1" "…and the owner is told to commit the result"
rm -rf "$D" "$P"

echo "--from --stale-only: provably stale replaced, adapted left alone, current untouched:"
D=$(mkrepo); P=$(mkplugin); make_stale "$D" commit-msg; make_adapted "$D" post-merge
ADAPTED=$(cat "$D/.ai/hooks/post-merge")
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "exit 0"
say "$(grep -c 'commit-msg: the flight-rules 0.0.1 copy' <<<"$OUT")" "1" "names the release the stale copy came from"
say "$(same "$D/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")" "same" "the stale commit-msg is now the source's"
say "$([ "$(cat "$D/.ai/hooks/post-merge")" = "$ADAPTED" ] && echo kept)" "kept" "the adapted post-merge is untouched"
say "$(grep -c 'post-merge: differs from every flight-rules release' <<<"$OUT")" "1" "…and named as left alone"
say "$(grep -c 'synced pre-rebase' <<<"$OUT")" "0" "a current hook is not reported synced"
say "$(grep -c 'synced commit-msg' <<<"$OUT")" "1" "(the stale one is, on the same run)"
say "$(grep -c '1 hook(s) left as they were' <<<"$OUT")" "1" "the summary counts what was left"
rm -rf "$D" "$P"

echo "A hook unchanged across releases is reported as the newest one it matches:"
# Compared numerically, so 0.0.10 beats 0.0.9 — a lexical sort would say 0.0.9.
D=$(mkrepo); P=$(mkplugin); make_stale "$D" commit-msg
for v in 0.0.9 0.0.10; do mkdir -p "$D/fakehome/.claude/plugins/cache/mp/flight-rules/$v/hooks/git"
  cp "$D/.ai/hooks/commit-msg" "$D/fakehome/.claude/plugins/cache/mp/flight-rules/$v/hooks/git/"; done
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "exit 0"
say "$(grep -c 'commit-msg: the flight-rules 0.0.10 copy' <<<"$OUT")" "1" "names 0.0.10, the newest of 0.0.1, 0.0.9 and 0.0.10"
rm -rf "$D" "$P"

echo "--from without --stale-only: an adapted hook is replaced too:"
D=$(mkrepo); P=$(mkplugin); make_adapted "$D" post-merge
say "$(rc "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")" "0" "exit 0"
say "$(same "$D/.ai/hooks/post-merge" "$P/hooks/git/post-merge")" "same" "post-merge is the source's copy"
rm -rf "$D" "$P"

echo "A project's own pre-commit is refused, and nothing else is touched either:"
# AppliHawk's shape with a linter: a blind cp would have replaced it. Refusal has to
# come before any copy, or the directory is left half updated.
D=$(mkrepo); P=$(mkplugin); make_stale "$D" commit-msg
printf '#!/bin/sh\nnpx lint-staged\n' > "$D/.ai/hooks/pre-commit"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "1" "exit 1"
say "$(grep -c 'pre-commit.local' <<<"$OUT")" "1" "says to rename it pre-commit.local"
say "$(grep -c 'lint-staged' "$D/.ai/hooks/pre-commit")" "1" "the project's pre-commit is still there"
say "$(same "$D/.ai/hooks/commit-msg" "$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/commit-msg")" "same" "the stale commit-msg was NOT updated on the refused run"
# --stale-only leaves it alone instead of refusing: it matches no release.
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "--stale-only exits 0 on the same project"
say "$(grep -c 'lint-staged' "$D/.ai/hooks/pre-commit")" "1" "…the project's pre-commit is still there"
say "$(same "$D/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")" "same" "…and the stale commit-msg IS updated"
rm -rf "$D" "$P"

# The rename is printed on a line of its own for pasting, its paths quoted for the
# shell. In '…' a path holding a quote and `$(…)` ran that command when pasted (0.26.0
# fix review, W1) — the class the --stale-only command was fixed for one screen away.
D0=$(mkrepo); P=$(mkplugin); D="$(dirname "$D0")/p '\$(touch pwned)' q"; mv "$D0" "$D" || die "could not rename the fixture"
printf '#!/bin/sh\nnpx lint-staged\n' > "$D/.ai/hooks/pre-commit"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
CMD=$(grep -E '^[[:space:]]+mv -n ' <<<"$OUT" | sed 's/^[[:space:]]*//')
say "$(printf '%s\n' "$CMD" | grep -c .)" "1" "a linter's pre-commit, in a path holding a quote and \$(…): the rename is a line of its own"
S=$(cd "$(mktemp -d)" && pwd -P)
(cd "$S" && bash -c "$CMD") >/dev/null 2>&1; PRC=$?
say "$PRC" "0" "…which, pasted, exits 0"
say "$(grep -c 'lint-staged' "$D/.ai/hooks/pre-commit.local" 2>/dev/null)" "1" "…moves the project's pre-commit to pre-commit.local"
say "$(ls "$S" | wc -l | tr -d ' ')" "0" "…and runs nothing the path spells out"
rm -rf "$D" "$P" "$S"

echo "Any hook that is not flight-rules' is refused, not only pre-commit (#97):"
# Only pre-commit was checked: a project's own commit-msg or post-merge was replaced
# without a word. Every one is named, with the line that sets it aside, before anything
# is written — the stale hook beside them included.
D=$(mkrepo); P=$(mkplugin); make_stale "$D" reference-transaction
printf '#!/bin/sh\nnpx commitlint --edit "$1"\n' > "$D/.ai/hooks/commit-msg"
printf '#!/bin/sh\nnpm install\n' > "$D/.ai/hooks/post-merge"
BEFORE=$(sums "$D/.ai/hooks")
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "1" "a project's own commit-msg and post-merge: exit 1"
say "$(grep -c "is not flight-rules' commit-msg (no 'pre-merge-check' in it)" <<<"$OUT")" "1" "…commit-msg named, with the marker it lacks"
say "$(grep -c "is not flight-rules' post-merge (no 'post-merge-note' in it)" <<<"$OUT")" "1" "…post-merge named too"
say "$(grep -c 'Nothing was written' <<<"$OUT")" "1" "…said to have written nothing"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…and writing nothing, the stale reference-transaction included"
CMDS=$(grep -E '^[[:space:]]+mv -n ' <<<"$OUT" | sed 's/^[[:space:]]*//')
say "$(printf '%s\n' "$CMDS" | grep -c .)" "2" "…one line each to set it aside"
(cd "$D" && eval "$CMDS") >/dev/null 2>&1
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "0" "…which run, let the install through"
say "$(same "$D/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")$(same "$D/.ai/hooks/reference-transaction" "$P/hooks/git/reference-transaction")" "samesame" "…every hook then the source's"
say "$(grep -c commitlint "$D/.ai/hooks/commit-msg.orig" 2>/dev/null)" "1" "…the project's commit-msg kept beside it"
rm -rf "$D" "$P"
# The project's own install.sh is left alone and said so, as --stale-only leaves it:
# nothing runs it, so it is not worth refusing every full install over.
D=$(mkrepo); P=$(mkplugin); make_stale "$D" commit-msg
printf '#!/bin/sh\n# our setup script\ngit config merge.ff false\n' > "$D/.ai/hooks/install.sh"; OWN=$(cksum < "$D/.ai/hooks/install.sh")
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "0" "a project's own install.sh, full install: exit 0"
say "$(grep -c "install.sh: the project's own, not flight-rules' — left alone" <<<"$OUT")" "1" "…said to be left alone"
say "$(cksum < "$D/.ai/hooks/install.sh")" "$OWN" "…and left as it was"
say "$(same "$D/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")" "same" "…while the stale hook is synced"
rm -rf "$D" "$P"
# A release older than its hook's marker is still flight-rules': 0.1.0's pre-merge-commit
# has no PR_ONLY. A copy identical to a cached release is replaced.
D=$(mkrepo); P=$(mkplugin)
OLD="$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/pre-merge-commit"
printf '#!/usr/bin/env bash\n# pre-merge-commit hook — the merge gate.\nexit 0\n' > "$OLD"; cp "$OLD" "$D/.ai/hooks/pre-merge-commit"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "0" "a cached release's copy with no marker: exit 0"
say "$(same "$D/.ai/hooks/pre-merge-commit" "$P/hooks/git/pre-merge-commit")" "same" "…replaced by the source's"
rm -rf "$D" "$P"
# Unreadable, a hook could not be checked: refused, said so, not called the project's.
D=$(mkrepo); P=$(mkplugin); make_adapted "$D" post-merge; chmod 000 "$D/.ai/hooks/post-merge"
if [ -r "$D/.ai/hooks/post-merge" ]; then
    echo "  ⏭️  an unreadable hook on the full install: skipped — running as root, a mode-000 file is readable"
else
    OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
    say "$(head -1 <<<"$OUT")" "1" "an unreadable hook, full install: exit 1"
    say "$(grep -c 'post-merge could not be read (grep exited 2)' <<<"$OUT")" "1" "…said to be unreadable"
    say "$(grep -c "is not flight-rules' post-merge" <<<"$OUT")" "0" "…not called the project's own"
fi
chmod 644 "$D/.ai/hooks/post-merge"; rm -rf "$D" "$P"

echo "install.sh updates itself when it is the file running:"
# The project's copy is what the CHANGELOG told people to run. bash reads a running
# script incrementally, so overwriting it in place is a hazard; the copy goes via mv.
D=$(mkrepo); P=$(mkplugin); make_stale "$D" install.sh; make_stale "$D" commit-msg
OUT=$(run "$D" .ai/hooks/install.sh --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "exit 0"
say "$(same "$D/.ai/hooks/install.sh" "$P/hooks/git/install.sh")" "same" "install.sh is now the source's copy"
say "$(same "$D/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")" "same" "…and so is commit-msg, from the same run"
say "$([ -x "$D/.ai/hooks/install.sh" ] && echo yes)" "yes" "…executable"
say "$(ls "$D/.ai/hooks" | grep -c '\.sync\.')" "0" "no temporary file left behind"
rm -rf "$D" "$P"

echo "A sync never rewrites core.hooksPath, and a fresh install writes it relative:"
# From a worktree, install.sh resolved a relative core.hooksPath against the worktree
# and wrote it back absolute into the SHARED repo config; `git worktree remove` then
# left every checkout running no hooks (review, 2026-10-12). This repo's own workflow
# is a worktree per change, so the shape is the default one, not a corner.
D=$(mkrepo); P=$(mkplugin); git -C "$D" config core.hooksPath .ai/hooks
echo base > "$D/f"; git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: base" --no-verify || die "could not commit the worktree fixture"
git -C "$D" worktree add -q "$D/.ai/worktrees/wt" -b feature/wt || die "could not add the worktree"
make_stale "$D/.ai/worktrees/wt" commit-msg 2>/dev/null || cp "$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.1/hooks/git/commit-msg" "$D/.ai/worktrees/wt/.ai/hooks/commit-msg"
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "sync from a worktree exits 0"
say "$(git -C "$D" config --local core.hooksPath)" ".ai/hooks" "…and core.hooksPath is still the relative value"
say "$(same "$D/.ai/worktrees/wt/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")" "same" "…the worktree's copy was updated"
say "$(same "$D/.ai/hooks/commit-msg" "$H/commit-msg")" "same" "…the main checkout's copy was not touched"
git -C "$D" worktree remove --force "$D/.ai/worktrees/wt"
say "$(cd "$D" && git config --local core.hooksPath)" ".ai/hooks" "…and after the worktree is removed the path still resolves here"
rm -rf "$D" "$P"
D=$(mkrepo); git -C "$D" config --unset core.hooksPath
say "$(rc "$D" .ai/hooks/install.sh)" "0" "a fresh install exits 0"
say "$(git -C "$D" config --local core.hooksPath)" ".ai/hooks" "…and writes core.hooksPath relative to the repo root"
rm -rf "$D"

echo "Only a LOCAL core.hooksPath inside the repo is synced:"
# A global core.hooksPath (~/.githooks) satisfied `git config core.hooksPath`, so an
# unattended sync wrote seven files into a directory outside every repo and pointed
# this one at it (review, 2026-10-12).
D=$(mkrepo); P=$(mkplugin); git -C "$D" config --unset core.hooksPath
mkdir -p "$D/fakehome/githooks"; printf '[core]\n\thooksPath = %s\n' "$D/fakehome/githooks" > "$D/fakehome/.gitconfig"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "1" "global hooksPath only: --stale-only refuses"
say "$(grep -c 'no local core.hooksPath' <<<"$OUT")" "1" "…saying nothing is installed here"
say "$(ls "$D/fakehome/githooks" | wc -l | tr -d ' ')" "0" "…and writes nothing into the global directory"
say "$(git -C "$D" config --local core.hooksPath 2>/dev/null)" "" "…nor a local core.hooksPath"
rm -rf "$D" "$P"
D=$(mkrepo); P=$(mkplugin); OUT_DIR=$(cd "$(mktemp -d)" && pwd -P); cp "$D"/.ai/hooks/* "$OUT_DIR/"; git -C "$D" config core.hooksPath "$OUT_DIR"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "1" "a local hooksPath outside the repo: --stale-only refuses"
say "$(grep -c 'outside this repository' <<<"$OUT")" "1" "…and says so"
rm -rf "$D" "$P" "$OUT_DIR"
# A local core.hooksPath of ~/… is a path git expands. Read raw, it was joined to the
# repo root: --stale-only said the directory did not exist, and an install created a
# literal "~" directory in the repo and wrote the hooks there. (The fixture's HOME is
# inside the repo, so ~/hk counts as inside it here.)
# commit-msg is removed first, so only an install into the expanded directory puts it back.
D=$(mkrepo); P=$(mkplugin); mkdir -p "$D/fakehome/hk"; cp "$D"/.ai/hooks/* "$D/fakehome/hk/"; git -C "$D" config core.hooksPath '~/hk'
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "a local hooksPath of ~/hk: --stale-only syncs"
say "$(grep -c 'does not exist' <<<"$OUT")" "0" "…without calling the directory missing"
rm "$D/fakehome/hk/commit-msg"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "0" "…an install exits 0"
say "$([ -e "$D/~" ] && echo made || echo none)" "none" "…and makes no literal ~ directory in the repo"
say "$(same "$D/fakehome/hk/commit-msg" "$P/hooks/git/commit-msg")" "same" "…it installs into the expanded directory"
rm -rf "$D" "$P"
# …and with HOME outside the repo, ~/hk is outside it: --stale-only refuses as such.
D=$(mkrepo); P=$(mkplugin); O=$(cd "$(mktemp -d)" && pwd -P); mkdir -p "$O/hk"; cp "$D"/.ai/hooks/* "$O/hk/"; git -C "$D" config core.hooksPath '~/hk'
OUT=$(cd "$D" && HOME="$O" bash "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only 2>&1); RC=$?
say "$RC" "1" "a local hooksPath of ~/hk outside the repo: --stale-only refuses"
say "$(grep -c 'outside this repository' <<<"$OUT")" "1" "…as outside the repository, not as missing"
rm -rf "$D" "$P" "$O"
# `/` is outside every repository. Stripped of its slash it resolved to the current
# directory, inside the repo, and the sync went ahead (round 4, W6). --check-only, so a
# break here compares rather than writes into /.
D=$(mkrepo); P=$(mkplugin); git -C "$D" config core.hooksPath /
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only --check-only)
say "$(head -1 <<<"$OUT")" "1" "a local hooksPath of /: --stale-only refuses"
say "$(grep -c 'outside this repository' <<<"$OUT")" "1" "…as outside the repository"
rm -rf "$D" "$P"
# From a linked worktree, an absolute core.hooksPath into the MAIN checkout — the usual
# install, shared by every worktree — is inside the repository, just not this worktree.
# It is still not synced from here (the write would land in another checkout's working
# tree), but "outside this repository; sync it by hand" was wrong on both counts: a
# downstream project's worktree sessions never synced and were told so (#87, 2026-10-18).
D=$(mkrepo); P=$(mkplugin)
echo base > "$D/f"; git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: base" --no-verify || die "could not commit the worktree fixture"
git -C "$D" worktree add -q "$D/.ai/worktrees/wt" -b feature/wt || die "could not add the worktree"
git -C "$D" config core.hooksPath "$D/.ai/hooks"; make_stale "$D" commit-msg
BEFORE=$(sums "$D/.ai/hooks")
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "1" "a worktree whose hooksPath is in the main checkout: --stale-only still refuses"
say "$(grep -c 'outside this repository' <<<"$OUT")" "0" "…without calling it outside the repository"
say "$(grep -cF "is in the main checkout, $D," <<<"$OUT")" "1" "…naming the main checkout"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…and writes nothing there"
# The command is for THIS worktree's copy, committed on its branch and merged: `cd <main>
# && …` sent a worktree back to a main checkout on a protected branch, where the diff
# could not be committed (#99 review, 2026-10-21).
CMD=$(grep -E '^[[:space:]]+bash ' <<<"$OUT" | sed 's/^[[:space:]]*//')
say "$CMD" "$(printf 'bash %q --from %q --stale-only --this-checkout' "$P/hooks/git/install.sh" "$P/hooks/git")" "…printing the command for this worktree's copy, its paths shell-quoted"
say "$(grep -c 'cd ' <<<"$OUT")" "0" "…not one that sends it to the main checkout"
cp "$D/.ai/hooks/commit-msg" "$D/.ai/worktrees/wt/.ai/hooks/commit-msg"
git -C "$D/.ai/worktrees/wt" commit -qam "chore: the stale copy, committed" --no-verify || die "could not commit the worktree's stale copy"
PASTED=$(cd "$D/.ai/worktrees/wt" && HOME="$D/fakehome" bash -c "$CMD" 2>&1); PRC=$?
say "$PRC" "0" "…which, pasted in the worktree, exits 0"
say "$(same "$D/.ai/worktrees/wt/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")" "same" "…and syncs the worktree's stale copy"
say "$(grep -c '^   synced commit-msg' <<<"$PASTED")" "1" "…saying so"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…leaving the main checkout's copy as it was"
say "$(git -C "$D/.ai/worktrees/wt" status --porcelain -- .ai/hooks)" " M .ai/hooks/commit-msg" "…a diff the worktree's branch can commit"
git -C "$D/.ai/worktrees/wt" checkout -q -- .ai/hooks
# --this-checkout without --stale-only replaces what differs too — doctor's "re-run
# without --stale-only to replace it". Run with no flag, that command wrote into the main
# checkout, on whatever branch it was (group A fix review, F1).
echo "# this project's own change" >> "$D/.ai/worktrees/wt/.ai/hooks/post-merge"
git -C "$D/.ai/worktrees/wt" commit -qam "chore: an adapted copy" --no-verify || die "could not commit the worktree's adapted copy"
MAINST=$(git -C "$D" status --porcelain -- .ai/hooks 2>&1)
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --this-checkout)
say "$(head -1 <<<"$OUT")" "0" "--this-checkout without --stale-only, from the worktree: exits 0"
# The list names whose copy it is: under the core.hooksPath line naming the main
# checkout's, "Active hooks" read as that one (group A fix review round 2, F3; round 3, V4).
say "$(grep -c "This checkout's copy (git runs the main checkout's" <<<"$OUT")" "1" "…listing the hooks as this checkout's copy"
say "$(same "$D/.ai/worktrees/wt/.ai/hooks/post-merge" "$P/hooks/git/post-merge")" "same" "…replaces the worktree's differing copy"
say "$(same "$D/.ai/worktrees/wt/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")" "same" "…and its stale one"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…leaving the main checkout's copy as it was"
say "$(git -C "$D" status --porcelain -- .ai/hooks 2>&1)" "$MAINST" "…and the main checkout's git status there unchanged"
say "$(git -C "$D" config --local core.hooksPath)" "$D/.ai/hooks" "…and core.hooksPath unchanged"
git -C "$D/.ai/worktrees/wt" reset -q --hard HEAD~1
say "$(rc "$D" "$P/hooks/git/install.sh" --this-checkout)" "1" "--this-checkout without --from is refused"
# The plain form, from that worktree, wrote into the main checkout — and README, the
# installer's header and /rules-sync all gave it (group A fix review round 2, D1).
WTBEFORE=$(sums "$D/.ai/worktrees/wt/.ai/hooks")
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "1" "plain --from, from a worktree whose hooks are in the main checkout: refused"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…writing nothing into the main checkout"
say "$(sums "$D/.ai/worktrees/wt/.ai/hooks")" "$WTBEFORE" "…nor into the worktree"
say "$(grep -E '^[[:space:]]+bash ' <<<"$OUT" | sed 's/^[[:space:]]*//')" \
    "$(printf 'bash %q --from %q --this-checkout' "$P/hooks/git/install.sh" "$P/hooks/git")" "…printing the --this-checkout form"
say "$(grep -c "main checkout's copy instead" <<<"$OUT")" "1" "…and the way to update the main checkout's copy"
# …and when that directory does not exist yet: it resolved to nothing, the refusal was
# skipped, and mkdir -p made it in the main checkout with the hooks in it (round 3, V2).
git -C "$D" config core.hooksPath "$D/.ai/hooks-new"
MAINST=$(git -C "$D" status --porcelain 2>&1)
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "1" "plain --from, from the worktree, the main checkout's hooks directory missing: refused"
say "$([ -e "$D/.ai/hooks-new" ] && echo made || echo absent)" "absent" "…not making it there"
say "$(git -C "$D" status --porcelain 2>&1)" "$MAINST" "…and the main checkout's git status unchanged"
# Said as missing, by this refusal and no other exit 1, with the one route that works:
# --this-checkout stopped at "does not exist" too (round 4, W1, W7).
say "$(grep -c "is in the main checkout, .*, and does not exist — git runs no hooks" <<<"$OUT")" "1" "…saying it is missing there and git runs no hooks"
say "$(grep -E '^[[:space:]]+cd ' <<<"$OUT" | sed 's/^[[:space:]]*//')" \
    "$(printf 'cd %q && bash %q --from %q' "$D" "$P/hooks/git/install.sh" "$P/hooks/git")" "…printing the install to run in the main checkout"
say "$(grep -c -- '--this-checkout' <<<"$OUT")" "0" "…and not --this-checkout, which would stop at the same missing directory"
git -C "$D" config core.hooksPath "$D/.ai/hooks"
# A link in the worktree to the main checkout's copy passed the redirect's -d, and the
# write went through it into the main checkout (group A fix review round 2, F0).
mv "$D/.ai/worktrees/wt/.ai/hooks" "$D/.ai/worktrees/wt/.ai/hooks.real"
ln -s "$D/.ai/hooks" "$D/.ai/worktrees/wt/.ai/hooks"
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --this-checkout)
say "$(head -1 <<<"$OUT")" "1" "--this-checkout, the worktree's hooks a link into the main checkout: refused"
say "$(grep -c 'outside it — not touched' <<<"$OUT")" "1" "…saying where it leads"
say "$(grep -c 'Replace the link with the committed directory' <<<"$OUT")" "1" "…and the way on (round 3, V5)"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…and writing nothing through it"
# The way on is a line to paste, %q-quoted, and run as printed it works (round 4, W2).
CMD=$(grep -E '^[[:space:]]+rm ' <<<"$OUT" | sed 's/^[[:space:]]*//')
say "$CMD" "$(printf 'rm %q && git checkout -- %q' "$(cd "$D/.ai/worktrees/wt" && pwd -P)/.ai/hooks" ".ai/hooks")" "…printed as a command of its own, its paths shell-quoted"
(cd "$D/.ai/worktrees/wt" && eval "$CMD") >/dev/null 2>&1; RC=$?
say "$RC" "0" "…which, run as printed, exits 0"
say "$([ -d "$D/.ai/worktrees/wt/.ai/hooks" ] && [ ! -L "$D/.ai/worktrees/wt/.ai/hooks" ] && echo dir)" "dir" "…leaving the committed directory in place of the link"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…and the main checkout's copy as it was"
# A path truly outside the repository, from the same worktree, keeps the old refusal.
O=$(cd "$(mktemp -d)" && pwd -P); cp "$D"/.ai/hooks/* "$O/"; git -C "$D" config core.hooksPath "$O"
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "1" "from a worktree, a hooksPath outside the repository: refused"
say "$(grep -c 'outside this repository' <<<"$OUT")" "1" "…as outside the repository"
say "$(grep -c 'main checkout' <<<"$OUT")" "0" "…not as the main checkout"
rm -rf "$D" "$P" "$O"
# Compared first: when every copy in the main checkout is already current there is
# nothing to send anyone there for, and a worktree session said "could not update the
# git hooks" every day regardless (#93, 2026-10-21). Silent, exit 0; one stale or
# missing copy still gets the main-checkout command.
D=$(mkrepo); P=$(mkplugin)
echo base > "$D/f"; git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: base" --no-verify || die "could not commit the worktree fixture"
git -C "$D" worktree add -q "$D/.ai/worktrees/wt" -b feature/wt || die "could not add the worktree"
git -C "$D" config core.hooksPath "$D/.ai/hooks"
BEFORE=$(sums "$D/.ai/hooks")
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "a worktree whose hooksPath is in the main checkout, every copy current: exit 0"
say "$(tail -n +2 <<<"$OUT" | grep -c .)" "0" "…saying nothing"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…and writing nothing there"
make_adapted "$D" post-merge; BEFORE=$(sums "$D/.ai/hooks")
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "…an adapted copy there is not stale: exit 0"
say "$(grep -c 'main checkout' <<<"$OUT")" "0" "…with no main-checkout command"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…and nothing written"
make_stale "$D" install.sh; BEFORE=$(sums "$D/.ai/hooks")
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "1" "…one stale copy there: exit 1"
say "$(grep -cF "is in the main checkout, $D," <<<"$OUT")" "1" "…with the main-checkout message"
say "$(grep -c 'install.sh: the flight-rules 0.0.1 copy — stale' <<<"$OUT")" "1" "…naming the stale copy, not as being updated"
say "$(grep -c 'updating' <<<"$OUT")" "0" "…and claiming no update"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…and writing nothing there"
cp "$P/hooks/git/install.sh" "$D/.ai/hooks/install.sh"; rm "$D/.ai/hooks/pre-rebase"
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "1" "…one missing copy there: exit 1"
say "$(grep -cF "is in the main checkout, $D," <<<"$OUT")" "1" "…with the main-checkout message"
say "$(grep -c '^   pre-rebase: missing$' <<<"$OUT")" "1" "…naming the missing copy"
say "$([ -f "$D/.ai/hooks/pre-rebase" ] && echo written || echo absent)" "absent" "…and nothing written"
# No install.sh there at all: nothing needs it (doctor does not name it), so it is no
# reason to send anyone to the main checkout — it was, every day (second review, C1).
cp "$P/hooks/git/pre-rebase" "$P/hooks/git/post-merge" "$D/.ai/hooks/"; rm "$D/.ai/hooks/install.sh"; BEFORE=$(sums "$D/.ai/hooks")
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "…no install.sh there, every hook current: exit 0"
say "$(tail -n +2 <<<"$OUT" | grep -c .)" "0" "…saying nothing"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…and writing nothing there"
make_stale "$D" commit-msg
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "1" "…no install.sh and a stale hook: exit 1, the hook still counts"
say "$(grep -c 'install.sh: missing' <<<"$OUT")" "0" "…without naming install.sh as missing"
rm -rf "$D" "$P"
# A project's own install.sh in the hooks directory — one that is not flight-rules' at
# all — is no stale copy: --stale-only said "differs from every release… add
# '# flight-rules: adapted'" about it whenever another hook synced, while doctor names
# no such file (second review, C4). Skipped without a word; flight-rules' own copy,
# edited, is still named.
D=$(mkrepo); P=$(mkplugin)
printf '#!/bin/sh\n# our setup script\ngit config merge.ff false\n' > "$D/.ai/hooks/install.sh"; make_stale "$D" commit-msg
OWN=$(cksum < "$D/.ai/hooks/install.sh")
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "a project's own install.sh beside a stale hook: exit 0"
say "$(grep -c '^   synced commit-msg' <<<"$OUT")" "1" "…the stale hook is synced"
say "$(grep -c 'install.sh' <<<"$OUT")" "0" "…and nothing is said about install.sh"
say "$(cksum < "$D/.ai/hooks/install.sh")" "$OWN" "…which is left as it was"
cp "$P/hooks/git/install.sh" "$D/.ai/hooks/install.sh"; make_adapted "$D" install.sh
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(grep -c 'install.sh: differs from every flight-rules release' <<<"$OUT")" "1" "flight-rules' install.sh, edited: still named as differing"
# Unreadable: a check that could not run, said as such — not "differs… mark it adapted"
# (third review, E3), not the project's own. Root reads a mode-000 file, so the case
# would pass through the marker path without testing this (E7): skipped there.
chmod 000 "$D/.ai/hooks/install.sh"
if [ -r "$D/.ai/hooks/install.sh" ]; then
    chmod 644 "$D/.ai/hooks/install.sh"
    echo "  ⏭️  an unreadable install.sh: skipped — running as root, a mode-000 file is readable"
else
    OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
    chmod 644 "$D/.ai/hooks/install.sh"
    say "$(grep -c 'install.sh: unreadable — could not check it' <<<"$OUT")" "1" "an unreadable install.sh is said to be unreadable"
    say "$(grep -c 'install.sh: differs' <<<"$OUT")" "0" "…not named as differing"
fi
rm -rf "$D" "$P"
# A marker grep that errors on a readable file could not check it: said so, not
# "differs… mark it adapted" (fix review, F14). Reachable only by a race or an I/O
# error, so a grep on PATH fails it here.
D=$(mkrepo); P=$(mkplugin); make_adapted "$D" post-merge
SHIM=$(cd "$(mktemp -d)" && pwd -P); REAL_GREP=$(command -v grep)
printf '#!/bin/sh\ncase "$*" in *"flight-rules: adapted"*) exit 2 ;; esac\nexec %s "$@"\n' "$REAL_GREP" > "$SHIM/grep"
chmod +x "$SHIM/grep"
OUT=$(PATH="$SHIM:$PATH" run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "a marker grep that errors: exit 0"
say "$(grep -c 'post-merge: could not be read (grep exited 2) — could not check it; left alone' <<<"$OUT")" "1" "…said as could not check"
say "$(grep -c 'post-merge: differs' <<<"$OUT")" "0" "…not as differing"
rm -rf "$D" "$P" "$SHIM"
# A missing install.sh in the checkout the sync writes to is not put back unattended,
# here any more than from a worktree (third review, E4; owner, 2026-10-21): doctor names
# it with the command. The full install still copies it.
D=$(mkrepo); P=$(mkplugin); rm -f "$D/.ai/hooks/install.sh"; make_stale "$D" commit-msg
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "--stale-only, no install.sh, a stale hook: exit 0"
say "$(grep -c '^   synced commit-msg' <<<"$OUT")" "1" "…the stale hook is synced"
say "$([ -f "$D/.ai/hooks/install.sh" ] && echo there || echo absent)" "absent" "…install.sh is not put back"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$([ -f "$D/.ai/hooks/install.sh" ] && echo there || echo absent)" "there" "…while the full install restores it"
rm -rf "$D" "$P"
# --check-only (session-start on a protected branch, #99): the comparison, named, and
# nothing written — exit 3 when something is behind, 0 when current.
D=$(mkrepo); P=$(mkplugin); make_stale "$D" commit-msg; BEFORE=$(sums "$D/.ai/hooks")
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only --check-only)
say "$(head -1 <<<"$OUT")" "3" "--check-only, a stale hook: exit 3"
say "$(grep -c 'commit-msg: the flight-rules 0.0.1 copy — stale' <<<"$OUT")" "1" "…naming it"
say "$(sums "$D/.ai/hooks")" "$BEFORE" "…and writing nothing"
rm -f "$D/.ai/hooks/post-merge"
say "$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only --check-only | grep -c 'post-merge: missing')" "1" "…a missing hook is named too"
cp "$P/hooks/git/commit-msg" "$P/hooks/git/post-merge" "$D/.ai/hooks/"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only --check-only)
say "$(head -1 <<<"$OUT")" "0" "…every hook current: exit 0"
say "$(tail -n +2 <<<"$OUT" | grep -c .)" "0" "…saying nothing"
say "$(rc "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --check-only)" "1" "--check-only without --stale-only is refused"
rm -rf "$D" "$P"
# An exported MAIN in the caller's environment is not this script's. Read before it was
# set, it made a plain --from install a silent no-op and an update a false main-checkout
# refusal (#93 batch review, B1, 2026-10-21).
D=$(mkrepo); P=$(mkplugin); git -C "$D" config --unset core.hooksPath; git -C "$D" config --unset merge.ff
OUT=$(export MAIN=/x; run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "0" "MAIN exported: a plain --from install exits 0"
say "$(git -C "$D" config core.hooksPath)" ".ai/hooks" "…and sets core.hooksPath"
say "$(git -C "$D" config merge.ff)" "false" "…and merge.ff=false"
rm -rf "$D"
D=$(mkrepo); make_stale "$D" commit-msg
OUT=$(export MAIN=/x; run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "0" "MAIN exported: --from over a stale copy exits 0"
say "$(grep -c '^   synced commit-msg' <<<"$OUT")" "1" "…and syncs it"
say "$(grep -c 'main checkout' <<<"$OUT")" "0" "…with no main-checkout refusal"
rm -rf "$D" "$P"
# The printed command is pasted, so a path is quoted for the shell. Wrapped in "…", a
# main checkout named with `$(…)` ran that command when pasted, and one with a `"`
# broke it (0.26.0 release review, P2). The command now names only the plugin's paths
# (#99 review), so the hostile name is the plugin directory's.
D=$(mkrepo); P0=$(mkplugin); P="$(dirname "$P0")/p \$(touch pwned) q"; mv "$P0" "$P" || die "could not rename the plugin fixture"
echo base > "$D/f"; git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: base" --no-verify || die "could not commit the hostile-path fixture"
git -C "$D" worktree add -q "$D/.ai/worktrees/wt" -b feature/wt || die "could not add the worktree"
git -C "$D" config core.hooksPath "$D/.ai/hooks"; make_stale "$D" commit-msg
cp "$D/.ai/hooks/commit-msg" "$D/.ai/worktrees/wt/.ai/hooks/commit-msg"
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
CMD=$(grep -E '^[[:space:]]+bash ' <<<"$OUT" | sed 's/^[[:space:]]*//')
PASTED=$(cd "$D/.ai/worktrees/wt" && HOME="$D/fakehome" bash -c "$CMD" 2>&1); PRC=$?
say "$PRC" "0" "a plugin whose path holds \$(…) and spaces: the pasted command exits 0"
say "$(same "$D/.ai/worktrees/wt/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")" "same" "…syncs the stale copy"
say "$([ -e "$D/.ai/worktrees/wt/pwned" ] && echo ran || echo not)" "not" "…and runs nothing the path spells out"
rm -rf "$D" "$P"
D=$(mkrepo); P=$(mkplugin); git -C "$D" config core.hooksPath .ai/gone
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "1" "a hooksPath that does not exist: --stale-only refuses rather than re-pointing"
say "$(git -C "$D" config --local core.hooksPath)" ".ai/gone" "…and leaves the path alone"
rm -rf "$D" "$P"

echo "A copy that fails is an exit, not a 'synced' line:"
# `cp … && mv …` is exempt from set -e: a read-only hooks directory printed "Permission
# denied" and then "synced commit-msg", exit 0, with the file unchanged (review,
# 2026-10-12). session-start would have told the assistant the hooks were updated.
D=$(mkrepo); P=$(mkplugin); make_stale "$D" commit-msg; chmod 555 "$D/.ai/hooks"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only); chmod 755 "$D/.ai/hooks"
say "$(head -1 <<<"$OUT")" "1" "exit 1 when the directory cannot be written"
say "$(grep -c 'could not write commit-msg' <<<"$OUT")" "1" "…naming the hook"
say "$(grep -c 'synced' <<<"$OUT")" "0" "…and claiming no sync"
say "$(ls -a "$D/.ai/hooks" | grep -c '\.sync\.')" "0" "…with no temporary file left behind"
rm -rf "$D" "$P"

echo "A non-numeric cache directory is never named the newest release:"
D=$(mkrepo); P=$(mkplugin); make_stale "$D" commit-msg
mkdir -p "$D/fakehome/.claude/plugins/cache/mp/flight-rules/7406167/hooks/git"
cp "$D/.ai/hooks/commit-msg" "$D/fakehome/.claude/plugins/cache/mp/flight-rules/7406167/hooks/git/"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(grep -c 'commit-msg: the flight-rules 0.0.1 copy' <<<"$OUT")" "1" "0.0.1 is named, not the sha-named directory"
rm -rf "$D" "$P"

echo "A hook marked adapted is left alone and said so:"
D=$(mkrepo); P=$(mkplugin); echo "# flight-rules: adapted — this project's own change" >> "$D/.ai/hooks/post-merge"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "exit 0"
say "$(grep -c 'post-merge: adapted here (marked' <<<"$OUT")" "1" "names it as adapted, not as unknown"
say "$(grep -c 'flight-rules: adapted' "$D/.ai/hooks/post-merge")" "1" "…and it is untouched"
rm -rf "$D" "$P"

echo "The marker is a comment line of its own, not the phrase anywhere:"
# install.sh carries the phrase in its own text, so an edited copy was taken as
# "marked by" nobody and never updated (release review, 2026-10-12).
D=$(mkrepo); P=$(mkplugin); echo "# local tweak" >> "$D/.ai/hooks/install.sh"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "exit 0"
say "$(grep -c 'install.sh: adapted here' <<<"$OUT")" "0" "an edited install.sh is not taken as marked adapted"
say "$(grep -c 'install.sh: differs from every' <<<"$OUT")" "1" "…it is named as matching no release"
rm -rf "$D" "$P"

echo "A rename onto a name already taken is not offered (#97 review, G7):"
# mv -n onto a .orig that mergetool left behind did nothing and exited 0, and the re-run
# refused with the same message.
D=$(mkrepo); P=$(mkplugin)
printf '#!/bin/sh\nnpx commitlint --edit "$1"\n' > "$D/.ai/hooks/commit-msg"; echo old > "$D/.ai/hooks/commit-msg.orig"
printf '#!/bin/sh\nnpx lint-staged\n' > "$D/.ai/hooks/pre-commit"; echo old > "$D/.ai/hooks/pre-commit.local"
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "1" "a project's commit-msg and pre-commit, .orig and .local both taken: exit 1"
say "$(grep -c 'commit-msg.orig already exists' <<<"$OUT")" "1" "…says commit-msg.orig already exists"
say "$(grep -c 'pre-commit.local already exists — merge this one into it by hand' <<<"$OUT")" "1" "…says pre-commit.local already exists, merge by hand"
say "$(grep -cE '^[[:space:]]+mv -n ' <<<"$OUT")" "0" "…and offers no mv that would do nothing"
rm -rf "$D" "$P"

echo "The marker table is one table, and an unknown slot fails safe (#97 review, G8, D12):"
DOC="$H/../flight-rules-doctor.sh"; [ -f "$DOC" ] || die "no flight-rules-doctor.sh beside $H"
for h in $HOOKS install.sh; do
  a=$(eval "$(sed -n '/^hook_marker() {/,/^}/p' "$H/install.sh")"; hook_marker "$h")
  b=$(eval "$(sed -n '/^hook_marker() {/,/^}/p' "$DOC")"; hook_marker "$h")
  say "$a" "$b" "$h: install.sh's marker ('$a') is doctor's"
done
# A slot added to HOOKS with no row: the empty pattern matched any file, and a project's
# own hook there was replaced. Here a copy of install.sh that also syncs post-checkout.
D=$(mkrepo); P=$(mkplugin)
sed 's/^HOOKS=.pre-merge-commit /HOOKS='"'"'post-checkout pre-merge-commit /' "$H/install.sh" > "$P/hooks/git/install.sh"
grep -q "^HOOKS='post-checkout " "$P/hooks/git/install.sh" || die "could not add post-checkout to HOOKS in the copy"
printf '#!/bin/sh\n# flight-rules post-checkout\n' > "$P/hooks/git/post-checkout"
printf '#!/bin/sh\ngit lfs post-checkout "$@"\n' > "$D/.ai/hooks/post-checkout"; chmod +x "$D/.ai/hooks/post-checkout"; OWN=$(cksum < "$D/.ai/hooks/post-checkout")
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "1" "a project's hook in a slot with no marker row: exit 1"
say "$(grep -c "is not flight-rules' post-checkout (no marker known for it)" <<<"$OUT")" "1" "…refused, said to have no marker"
say "$(cksum < "$D/.ai/hooks/post-checkout")" "$OWN" "…and left as it was"
rm -rf "$D" "$P"
# A project's own reference-transaction using `merge-base --is-ancestor`: the old marker
# took it for flight-rules' and replaced it.
D=$(mkrepo); P=$(mkplugin)
printf '#!/bin/sh\n# ours: block rewinding release tags\ngit merge-base --is-ancestor "$1" "$2" || exit 1\n' > "$D/.ai/hooks/reference-transaction"; OWN=$(cksum < "$D/.ai/hooks/reference-transaction")
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "1" "a project's reference-transaction using is-ancestor: exit 1"
say "$(grep -c "is not flight-rules' reference-transaction (no 'PR_ONLY' in it)" <<<"$OUT")" "1" "…refused as not flight-rules'"
say "$(cksum < "$D/.ai/hooks/reference-transaction")" "$OWN" "…and left as it was"
rm -rf "$D" "$P"

echo "--stale-only never replaces a newer release's copy with an older one (#94 review, G1):"
# An older session's sync took 0.28.0's hooks for stale and wrote its own 0.27.0 ones:
# being some release's copy was all it asked. Here the source is 0.0.5, the project
# holds 0.0.9's commit-msg and install.sh, and 0.0.1's pre-rebase.
D=$(mkrepo); P=$(mkplugin); printf '{ "name": "flight-rules", "version": "0.0.5" }\n' > "$P/.claude-plugin/plugin.json"
N="$D/fakehome/.claude/plugins/cache/mp/flight-rules/0.0.9/hooks/git"; mkdir -p "$N"
for h in commit-msg install.sh; do { cat "$H/$h"; echo "# flight-rules 0.0.9"; } > "$N/$h"; cp "$N/$h" "$D/.ai/hooks/$h"; done
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only --check-only)
say "$(head -1 <<<"$OUT")" "0" "--check-only, only newer copies: not behind (exit 0, not 3)"
say "$(grep -c 'newer than 0.0.5 — left alone' <<<"$OUT")" "2" "…both named as left alone"
make_stale "$D" pre-rebase
OUT=$(run "$D" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "exit 0"
say "$(grep -c 'commit-msg: the flight-rules 0.0.9 copy, newer than 0.0.5 — left alone' <<<"$OUT")" "1" "the newer commit-msg is named as left alone"
say "$(same "$D/.ai/hooks/commit-msg" "$N/commit-msg")" "same" "…and is still 0.0.9's"
say "$(grep -c 'install.sh: the flight-rules 0.0.9 copy, newer than 0.0.5 — left alone' <<<"$OUT")" "1" "so is install.sh"
say "$(same "$D/.ai/hooks/install.sh" "$N/install.sh")" "same" "…still 0.0.9's"
say "$(same "$D/.ai/hooks/pre-rebase" "$P/hooks/git/pre-rebase")" "same" "the older pre-rebase IS updated on the same run"
rm -rf "$D" "$P"

echo "A fresh install names the hooks git will stop running, and carries on (#111):"
# Setting core.hooksPath moves git off .git/hooks or a global hooks folder; a project's
# commit-msg there ran before the install and not after, with nothing said (probe,
# 2026-10-24). Config isolated: no system file, a fixture global one.
grun() { local d="$1"; shift; local out rc; out=$(cd "$d" && HOME="$d/fakehome" GIT_CONFIG_GLOBAL="$d/gcfg" GIT_CONFIG_NOSYSTEM=1 bash "$@" 2>&1); rc=$?; printf '%s\n%s' "$rc" "$out"; }
fresh() { local d; d=$(mkrepo); git -C "$d" config --unset core.hooksPath; printf '[user]\n\tname = t\n\temail = t@t.t\n' > "$d/gcfg"; rm -f "$d"/.git/hooks/*; printf '%s' "$d"; }
own() { printf '#!/bin/sh\necho own %s\n' "${1##*/}" > "$1"; chmod +x "$1"; }
D=$(fresh); own "$D/.git/hooks/commit-msg"; own "$D/.git/hooks/pre-push"; own "$D/.git/hooks/pre-commit"; own "$D/.git/hooks/pre-rebase.sample"
own "$D/.git/hooks/post-merge"; chmod -x "$D/.git/hooks/post-merge"   # git skips it: not executable
BEFORE=$(sums "$D/.git/hooks")
OUT=$(grun "$D" .ai/hooks/install.sh)
W=$(grep '^⚠️ git runs these hooks from' <<<"$OUT")
say "$(head -1 <<<"$OUT")" "0" ".git/hooks with a commit-msg, pre-push and pre-commit: exit 0"
say "$(grep -c "from $(cd "$D/.git/hooks" && pwd -P) today" <<<"$W")" "1" "…warned, naming .git/hooks"
say "$(grep -c ' pre-commit' <<<"$W")$(grep -c ' commit-msg' <<<"$W")$(grep -c ' pre-push' <<<"$W")" "111" "…and each of the three"
say "$(grep -c 'sample' <<<"$W")$(grep -c 'post-merge' <<<"$W")" "00" "…not the .sample, nor a post-merge git would not run (not executable)"
say "$(grep -c -- '- pre-push: copy it into' <<<"$OUT")$(grep -c -- '- pre-commit: copy it in as pre-commit.local' <<<"$OUT")$(grep -c -- '- commit-msg: flight-rules. runs no other' <<<"$OUT")" "111" "…with the way to keep each"
say "$(git -C "$D" config core.hooksPath)" ".ai/hooks" "…and installs anyway"
say "$(sums "$D/.git/hooks")" "$BEFORE" "…leaving .git/hooks as it was"
rm -rf "$D"
D=$(fresh); own "$D/.git/hooks/pre-commit.sample"
OUT=$(grun "$D" .ai/hooks/install.sh)
say "$(head -1 <<<"$OUT")" "0" "only *.sample in .git/hooks: exit 0"
say "$(grep -c 'git hooks installed' <<<"$OUT")" "1" "…installed"
say "$(grep -c '^⚠️ git runs these hooks' <<<"$OUT")" "0" "…and no warning"
rm -rf "$D"
D=$(fresh); G=$(cd "$(mktemp -d)" && pwd -P); own "$G/commit-msg"; printf '[core]\n\thooksPath = %s\n' "$G" >> "$D/gcfg"; own "$D/.git/hooks/pre-push"
OUT=$(grun "$D" .ai/hooks/install.sh)
W=$(grep '^⚠️ git runs these hooks from' <<<"$OUT")
say "$(head -1 <<<"$OUT")" "0" "a global core.hooksPath with a commit-msg: exit 0"
say "$(grep -c "from $G today" <<<"$W")" "1" "…warned, naming the global folder"
say "$(grep -c ' commit-msg' <<<"$W")$(grep -c 'pre-push' <<<"$W")" "10" "…its commit-msg, not .git/hooks' pre-push, which git was not reading"
rm -rf "$D" "$G"
D=$(fresh); git -C "$D" config core.hooksPath .ai/hooks; own "$D/.git/hooks/commit-msg"
OUT=$(grun "$D" .ai/hooks/install.sh)
say "$(head -1 <<<"$OUT")" "0" "a local core.hooksPath already set: exit 0"
say "$(grep -c 'git hooks installed' <<<"$OUT")" "1" "…installed"
say "$(grep -c '^⚠️ git runs these hooks' <<<"$OUT")" "0" "…and no warning: git was not reading .git/hooks"
rm -rf "$D"
D=$(fresh); echo base > "$D/f"; git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: base" --no-verify || die "could not commit the worktree fixture"
git -C "$D" worktree add -q -b w "$D/wt" >/dev/null 2>&1 || die "could not add the worktree fixture"; own "$D/.git/hooks/commit-msg"
OUT=$(grun "$D/wt" .ai/hooks/install.sh)
say "$(head -1 <<<"$OUT")" "0" "from a linked worktree: exit 0"
say "$(grep -c "^⚠️ git runs these hooks from $(cd "$D/.git/hooks" && pwd -P) today" <<<"$OUT")" "1" "…warned, naming the shared .git/hooks, not the worktree's .git file"
rm -rf "$D"

echo "Bad arguments fail loudly:"
D=$(mkrepo); P=$(mkplugin)
say "$(rc "$D" .ai/hooks/install.sh --from "$D/nowhere")" "1" "--from a missing directory"
say "$(rc "$D" .ai/hooks/install.sh --stale-only)" "1" "--stale-only without --from"
say "$(rc "$D" .ai/hooks/install.sh --frobnicate)" "1" "an unknown flag"
rm "$P/hooks/git/reference-transaction"
OUT=$(run "$D" .ai/hooks/install.sh --from "$P/hooks/git")
say "$(head -1 <<<"$OUT")" "1" "--from a directory missing a hook"
say "$(grep -c 'reference-transaction is missing' <<<"$OUT")" "1" "…names it"
rm -rf "$D" "$P"

echo "The source itself is not synced onto itself:"
# This repo runs its hooks from hooks/git with HOOK_SYNC unset; if it were set, the
# sync must not rewrite core.hooksPath or copy a file over itself.
D=$(mkrepo); git -C "$D" config core.hooksPath .ai/hooks
OUT=$(run "$D" .ai/hooks/install.sh --from "$D/.ai/hooks" --stale-only)
say "$(head -1 <<<"$OUT")" "0" "exit 0"
say "$(grep -c 'nothing to sync' <<<"$OUT")" "1" "says there is nothing to sync"
say "$(git -C "$D" config core.hooksPath)" ".ai/hooks" "core.hooksPath is left exactly as it was"
rm -rf "$D"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
