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
CMD=$(grep -E '^[[:space:]]+cd ' <<<"$OUT" | sed 's/^[[:space:]]*//')
say "$CMD" "$(printf 'cd %q && bash %q --from %q --stale-only' "$D" "$P/hooks/git/install.sh" "$P/hooks/git")" "…printing the command to run there, its paths shell-quoted"
# The command works when pasted, from anywhere: it syncs the main checkout's stale copy.
PASTED=$(cd / && HOME="$D/fakehome" bash -c "$CMD" 2>&1); PRC=$?
say "$PRC" "0" "…which, pasted, exits 0"
say "$(same "$D/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")" "same" "…and syncs the main checkout's stale copy"
say "$(grep -c '^   synced commit-msg' <<<"$PASTED")" "1" "…saying so"
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
# broke it (0.26.0 release review, P2): the path is the user's own directory, but the
# command has to work for any name it can have.
D0=$(mkrepo); P=$(mkplugin); D="$(dirname "$D0")/r \$(touch pwned) q"; mv "$D0" "$D" || die "could not rename the fixture"
echo base > "$D/f"; git -C "$D" add -A >/dev/null; git -C "$D" commit -qm "chore: base" --no-verify || die "could not commit the hostile-path fixture"
git -C "$D" worktree add -q "$D/.ai/worktrees/wt" -b feature/wt || die "could not add the worktree"
git -C "$D" config core.hooksPath "$D/.ai/hooks"; make_stale "$D" commit-msg
OUT=$(run "$D/.ai/worktrees/wt" "$P/hooks/git/install.sh" --from "$P/hooks/git" --stale-only)
CMD=$(grep -E '^[[:space:]]+cd ' <<<"$OUT" | sed 's/^[[:space:]]*//')
S=$(cd "$(mktemp -d)" && pwd -P)
PASTED=$(cd "$S" && HOME="$D/fakehome" bash -c "$CMD" 2>&1); PRC=$?
say "$PRC" "0" "a main checkout whose path holds \$(…) and spaces: the pasted command exits 0"
say "$(same "$D/.ai/hooks/commit-msg" "$P/hooks/git/commit-msg")" "same" "…syncs the stale copy"
say "$(ls "$S" | wc -l | tr -d ' ')" "0" "…and runs nothing the path spells out"
rm -rf "$D" "$P" "$S"
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
