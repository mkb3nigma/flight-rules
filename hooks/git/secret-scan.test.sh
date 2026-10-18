#!/usr/bin/env bash
# Tests for the pre-commit hook — the secret scan git runs on what is being committed.
#
# Every block case runs TWICE, as ref-gate.test.sh does: armed (hook installed) it must
# be refused and leave HEAD where it was; bare (no hook) the same commit must land. A
# case that fails both ways proves nothing. Assertions are on where HEAD landed, not
# on output, so a hook that dies before deciding cannot pass a case by being silent.
#
# The secrets are assembled at run time so that this file never carries one — the
# hook under test would refuse to commit it. Run: ./secret-scan.test.sh

set -uo pipefail
HOOK_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pre-commit"
PASS=0; FAIL=0
TMPROOT=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMPROOT"' EXIT

MAINPID=$$
trap 'printf "\n%s\n" "ABORTED: the fixture could not be built — no result above is meaningful" >&2; exit 2' TERM
die() { printf '  ❌ harness: %s\n' "$1" >&2; kill -s TERM "$MAINPID"; exit 2; }
say() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✅ $3"; else FAIL=$((FAIL+1)); echo "  ❌ $3 (got '$1', want '$2')"; fi; }

AWS=$(printf 'AKIA%s' IOSFODNN7EXAMPLE)
SK=$(printf 'sk-%s' ant-api03-abcdefghijklmnopqrstuvwx)
GHP=$(printf 'ghp_%s' abcdefghijklmnopqrstuvwxyz0123456789)
SLACK=$(printf 'xox%s' b-1234567890-abcdefghij)
GOOG=$(printf 'AIza%s' SyA-abcdefghijklmnopqrstuvwxyz01234)
PEM=$(printf -- '-----BEGIN %s PRIVATE KEY-----' RSA)

# A repo with one commit holding a tracked file `t`. $1: "armed" or "bare".
make_repo() {
  local d; d=$(mktemp -d "$TMPROOT/r.XXXXXX")
  git -C "$d" init -q -b feature || die "git init failed in $d"
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  mkdir -p "$d/.hooks"
  if [ "$1" = armed ]; then
    cp "$HOOK_SRC" "$d/.hooks/pre-commit" || die "could not copy $HOOK_SRC"
    chmod +x "$d/.hooks/pre-commit"
  fi
  git -C "$d" config core.hooksPath "$d/.hooks"
  echo base > "$d/t"; git -C "$d" add t
  git -C "$d" commit -qm base --no-verify || die "base commit failed in $d"
  printf '%s' "$d"
}

# landed <repo> <head-before>: "yes" if a commit was made.
landed() { [ "$(git -C "$1" rev-parse HEAD)" != "$2" ] && echo yes || echo no; }

# blocks <label> [<setup>] <script>: in a fresh repo ($R), setup runs first (its
# commits use --no-verify), then the script commits. Armed, the script's commit must
# not land and must say why; bare, it must land.
blocks() {
  local label="$1" setup="" body R h out
  if [ $# -eq 3 ]; then setup="$2"; body="$3"; else body="$2"; fi
  R=$(make_repo armed)
  [ -z "$setup" ] || (cd "$R" && R="$R" bash -c "$setup" >/dev/null 2>&1) || die "setup failed: $label"
  h=$(git -C "$R" rev-parse HEAD)
  out=$(cd "$R" && R="$R" bash -c "$body" 2>&1)
  say "$(landed "$R" "$h")" no "$label — refused"
  case "$out" in *"commit refused"*) say yes yes "$label — says why" ;;
                 *) say no yes "$label — says why" ;; esac
  R=$(make_repo bare)
  [ -z "$setup" ] || (cd "$R" && R="$R" bash -c "$setup" >/dev/null 2>&1) || die "setup failed: $label"
  h=$(git -C "$R" rev-parse HEAD)
  (cd "$R" && R="$R" bash -c "$body" >/dev/null 2>&1)
  say "$(landed "$R" "$h")" yes "$label — lands without the hook (the case is real)"
}
# allows <label> [<setup>] <script>: setup runs first, unhooked, so a fixture commit
# it makes cannot be mistaken for the commit under test landing.
allows() {
  local label="$1" setup="" body R h
  if [ $# -eq 3 ]; then setup="$2"; body="$3"; else body="$2"; fi
  R=$(make_repo armed)
  [ -z "$setup" ] || (cd "$R" && R="$R" bash -c "$setup" >/dev/null 2>&1) || die "setup failed: $label"
  h=$(git -C "$R" rev-parse HEAD)
  (cd "$R" && R="$R" bash -c "$body" >/dev/null 2>&1)
  say "$(landed "$R" "$h")" yes "$label — allowed"
}
# Large fixtures for the key-position cases: 1.2 MB of text, 2 MB of random binary.
FT="$TMPROOT/fill.txt"; FB="$TMPROOT/fill.bin"
awk 'BEGIN { for (i = 0; i < 30000; i++) print "line of a large generated lockfile entry" }' > "$FT" \
  && head -c 2097152 /dev/urandom > "$FB" || die "could not build the large fixtures"
export AWS SK GHP SLACK GOOG PEM FT FB

echo "The shapes the agent guard cannot see (#71, #72):"
blocks "git add f && git commit"        'echo "k=$AWS" > f && git add f && git commit -qm x'
blocks "git commit -a"                  'echo "k=$AWS" >> t && git commit -qam x'
blocks "git commit <path>"              'echo "k=$AWS" >> t && git commit -qm x -- t'
blocks "git commit --include <path>"    'echo y > g && git add g && echo "k=$AWS" >> t && git commit -qm x --include t'
blocks "GIT_INDEX_FILE= prefix"         'cp .git/index "$R/alt" && echo "k=$AWS" > f && GIT_INDEX_FILE="$R/alt" git add f && GIT_INDEX_FILE="$R/alt" git commit -qm x'
blocks "git -C <repo> from elsewhere"   'echo "k=$AWS" > f && git add f && cd / && git -C "$R" commit -qm x'
blocks "secret at column zero"          'printf "%s\n" "$AWS" > f && git add f && git commit -qm x'

# The refusal is read by agents as well as people. It printed the bypass, so an agent
# retrying a refused `commit -a` was handed the way past the one check that sees it
# (/dg, 2026-10-08). It says who decides instead.
R=$(make_repo armed)
out=$(cd "$R" && echo "k=$AWS" > f && git add f && git commit -qm x 2>&1)
case "$out" in *"commit refused"*) ;; *) die "the refusal case was not refused" ;; esac
case "$out" in *no-verify*) say printed absent "the refusal does not print the bypass" ;;
               *) say absent absent "the refusal does not print the bypass" ;; esac

echo "Every pattern:"
blocks "sk- key"           'echo "k=$SK" > f && git add f && git commit -qm x'
blocks "GitHub token"      'echo "k=$GHP" > f && git add f && git commit -qm x'
blocks "Slack token"       'echo "k=$SLACK" > f && git add f && git commit -qm x'
blocks "Google key"        'echo "k=$GOOG" > f && git add f && git commit -qm x'
blocks "PEM private key"   'echo "$PEM" > f && git add f && git commit -qm x'
blocks ".env staged"       'echo X=1 > .env && git add .env && git commit -qm x'
blocks "nested .env.local" 'mkdir -p a && echo X=1 > a/.env.local && git add a && git commit -qm x'
blocks "key in a test file" 'mkdir tests && echo "k=$AWS" > tests/x_test.py && git add tests && git commit -qm x'
blocks "key in a non-ASCII-named file" 'echo "k=$AWS" > cönfig.py && git add . && git commit -qm x'

echo "Config that changes what git diff prints:"
blocks "color.diff=always"  'git config color.diff always && git config color.ui always && echo "k=$AWS" > f && git add f && git commit -qm x'
blocks "diff.external set"  'git config diff.external /usr/bin/true && echo "k=$AWS" > f && git add f && git commit -qm x'
blocks "a -diff attribute"  'printf "*.pem -diff\n" > .gitattributes && echo "$PEM" > k.pem && git add . && git commit -qm x'
blocks "a redacting textconv" 'printf "*.cfg diff=redact\n" > .gitattributes && git config diff.redact.textconv "sed s/AKIA/XXXX/" && echo "k=$AWS" > a.cfg && git add . && git commit -qm x'
blocks "diff.noprefix"      'git config diff.noprefix true && echo "k=$AWS" > f && git add f && git commit -qm x'

echo "What it leaves alone:"
allows "an ordinary commit"                  'echo hello > f && git add f && git commit -qm x'
allows "removing a line that held a key"     'echo "k=$AWS" > f && git add f && git commit -qm x --no-verify' ': > f && git commit -qam y'
# Only removing a .env is let through: editing one already tracked is refused like adding
# it, so a password typed into committed defaults never lands quietly (owner's call,
# 2026-10-05). Wanting it is a --no-verify, deliberately.
blocks "editing an already-tracked .env"     'echo X=1 > .env.development && git add . && git commit -qm x --no-verify' 'echo Y=2 >> .env.development && git commit -qam y'
blocks "a key written into a tracked .env"  'echo X=1 > .env.development && git add . && git commit -qm x --no-verify' 'echo "K=$AWS" >> .env.development && git commit -qam y'
blocks "a .env symlink turned into a file" 'ln -s /dev/null .env && git add .env && git commit -qm x --no-verify' 'rm .env && echo X=1 > .env && git add .env && git commit -qm y'
# Each of the six key patterns, on a line whose own text begins "++ " — in the diff that
# is "+++ …", the shape of a file header (#77).
for v in AWS SK GHP SLACK GOOG PEM; do
  blocks "an added line that starts with ++ ($v)" "printf '++ %s\\n' \"\$$v\" > f && git add f && git commit -qm x"
done
blocks "a key inside a small binary"    'printf "\000\001%s\000\n" "$AWS" > k.dat && git add k.dat && git commit -qm x'
# The git hook has no timeout to outrun, so it reads every binary whole: it is the
# backstop for what the agent guard's 1 MB limit skips. The key's position is crossed
# with the payload: a key with more than 64 KB of added text after it was committed,
# because the match was piped to grep -q, which stops at the first hit, and pipefail
# counted the writer's SIGPIPE as no match (/dg, 2026-10-08). Every large case then put
# the key last.
blocks "a key first in 1.2 MB of text"  '{ printf "%s\n" "$AWS"; cat "$FT"; } > big.txt && git add big.txt && git commit -qm x'
blocks "a key mid-way in 1.2 MB of text" '{ cat "$FT"; printf "%s\n" "$AWS"; cat "$FT"; } > big.txt && git add big.txt && git commit -qm x'
blocks "a key last in 1.2 MB of text"   '{ cat "$FT"; printf "%s\n" "$AWS"; } > big.txt && git add big.txt && git commit -qm x'
blocks "a key first in a 2 MB binary"   '{ printf "%s\n" "$AWS"; cat "$FB"; } > big.dat && git add big.dat && git commit -qm x'
blocks "a key mid-way in a 2 MB binary" '{ cat "$FB"; printf "\n%s\n" "$AWS"; cat "$FB"; } > big.dat && git add big.dat && git commit -qm x'
blocks "a key last in a 2 MB binary"    '{ cat "$FB"; printf "\n%s\n" "$AWS"; } > big.dat && git add big.dat && git commit -qm x'
# A here-string that large is backed by a temp file; when it cannot be written (a full
# /tmp, here a file-size limit) the match failed and the key was committed (/dg, 2026-10-08).
blocks "a key first in 1.2 MB, temp files unwritable" '{ printf "%s\n" "$AWS"; cat "$FT"; } > big.txt && git add big.txt && (trap "" XFSZ; ulimit -f 64; git commit -qm x)'
blocks "a key in one file, 1.2 MB in the next" '{ printf "%s\n" "$AWS"; } > a.txt && cp "$FT" b.txt && git add . && git commit -qm x'
blocks "renaming a .env away"           'echo X=1 > .env && git add .env && git commit -qm x --no-verify' 'git mv .env config.txt && git commit -qm y'
# With diff.renames=false a rename is listed as a delete and an add, so the source was
# never seen and the .env left under a new name (/dg, 2026-10-08).
blocks "renaming a .env away, renames off" 'echo X=1 > .env && git add .env && git commit -qm x --no-verify && git config diff.renames false' 'git mv .env config.txt && git commit -qm y'
blocks "renaming a .env to a template"  'echo X=1 > .env && git add .env && git commit -qm x --no-verify' 'git mv .env .env.example && git commit -qm y'
blocks "a key after a binary file"     'printf "\000\001\002\377" > a.bin && printf "caf\351 %s\n" "$AWS" > z.txt && git add . && git commit -qm x'
allows "deleting a committed .env"           'echo X=1 > .env && git add .env && git commit -qm x --no-verify' 'git rm -q .env && git commit -qm y'
allows "untracking a committed .env"         'echo X=1 > .env && git add .env && git commit -qm x --no-verify' 'git rm -q --cached .env && git commit -qm y'
allows ".env templates"                      'for s in example sample template dist md; do echo X= > .env.$s; done && git add . && git commit -qm x'
allows "a credential literal (agent-only heuristic)" 'echo "password = \"hunter2hunter2\"" > app.py && git add . && git commit -qm x'
allows "the key text in the message only"    'echo y > f && git add f && git commit -qm "rotated $AWS"'
allows "--no-verify, the owner's override"   'echo "k=$AWS" > f && git add f && git commit -qm x --no-verify'
allows "an empty commit"                     'git commit -q --allow-empty -m x'

echo "A project's own pre-commit, renamed pre-commit.local, still runs:"
R=$(make_repo armed)
printf '#!/bin/sh\necho local-ran > "%s/ran"\nexit 3\n' "$R" > "$R/.hooks/pre-commit.local"; chmod +x "$R/.hooks/pre-commit.local"
h=$(git -C "$R" rev-parse HEAD)
(cd "$R" && echo y > f && git add f && git commit -qm x) >/dev/null 2>&1
say "$(cat "$R/ran" 2>/dev/null)" local-ran "after a clean scan, pre-commit.local runs"
say "$(landed "$R" "$h")" no "…and its exit status decides the commit"
rm -f "$R/ran"
(cd "$R" && echo "k=$AWS" > g && git add g && git commit -qm x) >/dev/null 2>&1
say "$(cat "$R/ran" 2>/dev/null || echo not-run)" not-run "…and does not run when the scan refused"

echo "Concluding a merge (MERGE_HEAD present) is not re-scanned:"
R=$(make_repo armed)
( cd "$R" && git checkout -qb other && echo "k=$AWS" > f && echo other > t && git add . \
  && git commit -qm "other" --no-verify && git checkout -q feature && echo mine > t \
  && git commit -qam mine && git merge other >/dev/null 2>&1; echo resolved > t && git add t ) \
  || die "could not build the conflicted merge"
git -C "$R" rev-parse -q --verify MERGE_HEAD >/dev/null || die "the merge did not stop on a conflict"
h=$(git -C "$R" rev-parse HEAD)
OUT=$(git -C "$R" commit -qm merge 2>&1)
say "$(landed "$R" "$h")" yes "a conflicted merge whose incoming side holds a key concludes"
say "$(grep -c 'secret scan skipped' <<<"$OUT")" 1 "…and says the scan was skipped, so a leftover MERGE_HEAD is never silent"
say "$(git -C "$R" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" 3 "…and it is a merge commit"

echo "The skip names the commit coming in and prescribes no command (final release /dg, 2026-10-17/18):"
# It cannot tell a real merge from a leftover, and each command it offered was wrong in
# one: `git merge --abort` discarded staged work beside a leftover; `rm` of the marker,
# after a real merge a gate refused, landed the branch past that gate. Through a real
# `git commit`: a leftover, which goes through as a merge; and a real merge and a
# leftover on a note-gated branch, which the REAL commit-msg refuses — its box offers
# --abort, so it must say what that costs (fix /dg, 2026-10-18).
CM_SRC="$(dirname "$HOOK_SRC")/commit-msg"
gated() {   # gated <repo>: the real commit-msg, and the branch note-gated in the committed conf
  cp "$CM_SRC" "$1/.hooks/commit-msg" && chmod +x "$1/.hooks/commit-msg" || die "could not install commit-msg"
  mkdir -p "$1/.ai" && printf 'PROTECTED_BRANCHES=^feature$\nNOTE_GATED_BRANCHES=^feature$\n' > "$1/.ai/flight-rules.conf"
  git -C "$1" add .ai && git -C "$1" commit -qm conf --no-verify || die "could not commit the conf"
}
for how in leftover refused leftover-gated; do
  R=$(make_repo armed)
  case "$how" in refused|leftover-gated) gated "$R" ;; esac
  if [ "$how" = refused ]; then
    ( cd "$R" && git checkout -qb other && echo other > t && git commit -qam other --no-verify \
      && git checkout -q feature && echo mine > t && git commit -qam mine --no-verify ) >/dev/null 2>&1 \
      || die "could not build the branches"
    git -C "$R" merge other >/dev/null 2>&1
    [ -f "$(git -C "$R" rev-parse --absolute-git-dir)/MERGE_HEAD" ] || die "the merge did not stop on a conflict"
    echo resolved > "$R/t"; git -C "$R" add t || die "could not resolve"
  else
    ( cd "$R" && git checkout -qb other && echo o > o && git add o && git commit -qm o --no-verify \
      && git checkout -q feature ) >/dev/null 2>&1 || die "could not build a side branch"
    git -C "$R" rev-parse other > "$(git -C "$R" rev-parse --absolute-git-dir)/MERGE_HEAD"
    echo new > "$R/n"; git -C "$R" add n >/dev/null 2>&1 || die "could not stage"
  fi
  in=$(git -C "$R" rev-parse other); h=$(git -C "$R" rev-parse HEAD)
  OUT=$(cd "$R" && git commit -qm x 2>&1)
  if [ "$how" = leftover ]; then
    # git may reduce the parents to that commit alone (HEAD is its ancestor here).
    say "$(git -C "$R" rev-list --parents -n1 HEAD | tr ' ' '\n' | sed 1d | grep -cx "$in")" 1 "leftover: the commit lands with the named commit as a parent"
  else
    say "$(git -C "$R" rev-parse HEAD)" "$h" "$how: the real commit-msg refuses it"
    say "$(grep -c 'it also drops what you staged' <<<"$OUT")" 1 "…and its box says what git merge --abort costs"
    say "$(grep -c 'started is a leftover: check git status first' <<<"$OUT")" 1 "…and names the leftover case"
  fi
  say "$(grep -c "concluding a merge of ${in:0:12} — secret scan skipped" <<<"$OUT")" 1 "$how: the skip names the commit coming in"
  say "$(grep -c "This commit records ${in:0:12} as a parent" <<<"$OUT")" 1 "…says the commit records it as a parent"
  say "$(grep -c 'Check `git log -1` and `git status` before anything else' <<<"$OUT")" 1 "…and what to check"
  say "$(grep -cE '`(rm |git merge --abort|git reset)' <<<"$(grep 'pre-commit:' <<<"$OUT")")" 0 "…prescribing no rm, --abort or reset"
done

echo "A branch or tag named MERGE_HEAD is not a merge in progress (AppliHawk review, 2026-10-17):"
# `rev-parse --verify MERGE_HEAD` resolves refs/heads/MERGE_HEAD too, so one such branch
# switched the scan off for every commit with nothing said. The marker is a file.
for kind in branch tag; do
  R=$(make_repo armed)
  git -C "$R" "$kind" MERGE_HEAD >/dev/null 2>&1 || die "could not create a $kind named MERGE_HEAD"
  git -C "$R" rev-parse -q --verify MERGE_HEAD >/dev/null || die "the $kind does not resolve as MERGE_HEAD"
  h=$(git -C "$R" rev-parse HEAD)
  (cd "$R" && echo "k=$AWS" > g && git add g && git commit -qm x) >/dev/null 2>&1
  say "$(landed "$R" "$h")" no "a $kind named MERGE_HEAD: a staged key is still refused"
done

echo "A leftover MERGE_HEAD naming HEAD or an ancestor makes no merge, so it is scanned (release /dg, 2026-10-17):"
# git drops a parent HEAD already contains and records an ordinary commit — the skip
# would let a key through on a commit that merged nothing.
# A sha naming no object cannot be merged either: an error is not "not an ancestor".
for at in HEAD HEAD~1 missing; do
  R=$(make_repo armed)
  (cd "$R" && echo y > p && git add p && git commit -qm p) >/dev/null 2>&1 || die "could not add a second commit"
  if [ "$at" = missing ]; then echo 0123456789abcdef0123456789abcdef01234567
  else git -C "$R" rev-parse "$at"; fi > "$(git -C "$R" rev-parse --absolute-git-dir)/MERGE_HEAD"
  h=$(git -C "$R" rev-parse HEAD)
  OUT=$(cd "$R" && echo "k=$AWS" > g && git add g && git commit -qm x 2>&1)
  say "$(landed "$R" "$h")" no "MERGE_HEAD file = $at: a staged key is refused"
  say "$(grep -c 'commit refused' <<<"$OUT")" 1 "…and the hook said why"
done

# A branch with no commits yet: --is-ancestor errors, and git ignores MERGE_HEAD and
# makes a root commit — the case where an error read as "a merge" landed a key.
R=$(make_repo armed)
m=$(git -C "$R" rev-parse HEAD)
(cd "$R" && git checkout -q --orphan unborn && git rm -rqf --cached . ) >/dev/null 2>&1 || die "could not start an unborn branch"
echo "$m" > "$(git -C "$R" rev-parse --absolute-git-dir)/MERGE_HEAD"
OUT=$(cd "$R" && echo "k=$AWS" > g && git add g && git commit -qm x 2>&1)
say "$(git -C "$R" rev-parse -q --verify unborn >/dev/null && echo yes || echo no)" no "unborn branch, MERGE_HEAD file present: a staged key is refused"
say "$(grep -c 'commit refused' <<<"$OUT")" 1 "…and the hook said why"

echo "A step that fails is a refusal, not a clean scan (/dg G2-4, 2026-10-08):"
# Their output was taken without their status, so a failed git diff was an empty one
# and the commit went through unscanned. git runs a hook with its own directory first
# on PATH, so a failing `git` cannot be slipped in under `git commit`: the hook is run
# directly, from the repo, as git would run it, with a `git` (or `awk`) that fails on
# one call — git when an argument equals $FAIL_ON, awk when its program holds it.
R=$(make_repo armed); REAL_GIT=$(command -v git); REAL_AWK=$(command -v awk)
mkdir -p "$R/shim" \
  && printf '#!/bin/sh\nfor a; do [ "$a" = "$FAIL_ON" ] && { echo "git-said-$FAIL_ON" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$REAL_GIT" > "$R/shim/git" \
  && printf '#!/bin/sh\nfor a; do case "$a" in *"$FAIL_ON"*) exit 2 ;; esac; done\nexec "%s" "$@"\n' "$REAL_AWK" > "$R/shim/awk" \
  && chmod +x "$R/shim/git" "$R/shim/awk" && echo clean > "$R/f" && git -C "$R" add f || die "could not build the failing-git fixture"
scan_with() { (cd "$R" && FAIL_ON="$1" PATH="$R/shim:$PATH" ./.hooks/pre-commit 2>&1); echo "rc=$?"; }
out=$(scan_with --none-of-these)
say "${out##*rc=}" 0 "the stand-in git and awk, failing nothing, let a clean commit through"
for arg in --text --name-only --name-status 'diff --git' '.env'; do
  out=$(scan_with "$arg")
  say "${out##*rc=}" 1 "$arg fails — refused"
  case "$out" in *"could not read what is staged"*) say yes yes "…and says the scan did not run" ;;
                 *) say no yes "…and says the scan did not run (got: $out)" ;; esac
done
for arg in --text --name-only --name-status; do
  out=$(scan_with "$arg")
  case "$out" in *"git-said-$arg"*) say yes yes "git diff $arg fails — git's own error is shown" ;;
                 *) say no yes "git diff $arg fails — git's own error is shown (got: $out)" ;; esac
done
rm -rf "$R"
# The same, end to end through `git commit`: a blobless partial clone whose remote has
# gone, changing a file whose old blob was never fetched. git diff cannot fetch it and
# fails; git can still commit. The accepted cost named in the hook (/dg, 2026-10-12).
for mode in armed bare; do
  P="$TMPROOT/pc-$mode"; mkdir -p "$P"
  ( git init -q -b main "$P/src" && cd "$P/src" && echo old > f && git add f \
    && git -c user.email=t@t.t -c user.name=t commit -qm base && git config uploadpack.allowFilter true \
    && git clone -q --filter=blob:none --no-checkout "file://$P/src" "$P/cl" && cd "$P/cl" && git read-tree HEAD \
    && git config user.email t@t.t && git config user.name t && mkdir -p .hooks && git config core.hooksPath "$P/cl/.hooks" ) \
    >/dev/null 2>&1 || die "could not build the partial clone"
  [ "$mode" = bare ] || { cp "$HOOK_SRC" "$P/cl/.hooks/pre-commit" && chmod +x "$P/cl/.hooks/pre-commit"; } || die "could not arm the partial clone"
  mv "$P/src" "$P/src.gone" && echo new > "$P/cl/f" && git -C "$P/cl" add f || die "could not stage in the partial clone"
  h=$(git -C "$P/cl" rev-parse HEAD)
  out=$(git -C "$P/cl" commit -qm x 2>&1)
  if [ "$mode" = armed ]; then
    say "$(landed "$P/cl" "$h")" no "partial clone, remote gone, an unfetched file changed — refused"
    case "$out" in *"promisor remote"*) say yes yes "…and shows git's reason" ;; *) say no yes "…and shows git's reason (got: $out)" ;; esac
  else
    say "$(landed "$P/cl" "$h")" yes "…while git alone commits it"
  fi
done

echo "A large binary is read whole, and quickly enough (/dg, 2026-10-05):"
# Sized to what projects commit: the largest file kept in flight-rules or AppliHawk is
# ~300 KB. This was 40 MB, a size nobody has committed, and at 6–8s it flaked against
# its bound (2026-10-11). The bound is loose: it catches a scan that slowed by a
# multiple, not a slow runner. Raise the size if a project commits larger files.
R=$(make_repo armed)
head -c 1048576 /dev/urandom > "$R/big.bin" && git -C "$R" add big.bin || die "could not stage the large binary"
h=$(git -C "$R" rev-parse HEAD); START=$SECONDS
git -C "$R" commit -qm big >/dev/null 2>&1
TOOK=$((SECONDS - START))
say "$(landed "$R" "$h")" yes "a 1 MB binary commits"
[ "$TOOK" -le 8 ] && say yes yes "…in ${TOOK}s (bound 8s)" || say no yes "…took ${TOOK}s (bound 8s)"
rm -rf "$R"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
