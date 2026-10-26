#!/usr/bin/env bash
# Tests for the reference-transaction hook — the ref gate.
#
# Every violation case runs TWICE: once with the hook installed and once without.
# It must be blocked with the hook and SUCCEED without it. A case that fails both
# ways proves nothing — git refuses `branch -f` on a checked-out branch all by
# itself, and an earlier draft of this suite "passed" on exactly that. The findings
# this hook closes were all invisible to string-level reasoning, so the assertions
# are on where the ref actually landed. Run: ./ref-gate.test.sh

set -uo pipefail
HOOK_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/reference-transaction"
PASS=0; FAIL=0
TMPROOT=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMPROOT"' EXIT

# A broken fixture is not a test failure, it is an aborted run — so it stops the suite
# rather than being counted. make_repo runs inside a command substitution, so a FAIL
# increment there would be discarded with the subshell (and seven of these assertions
# pass against a repo that was never built: measured 2026-09-12 by pointing the clone
# at a path that does not exist). `$$` is the parent's pid even inside $( ), so the
# signal reaches the trap below.
MAINPID=$$
trap 'printf "\n%s\n" "ABORTED: the fixture could not be built — no result above is meaningful" >&2; exit 2' TERM
die() { printf '  ❌ harness: %s\n' "$1" >&2; kill -s TERM "$MAINPID"; exit 2; }
say() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✅ $3"; else FAIL=$((FAIL+1)); echo "  ❌ $3 (got '$1', want '$2')"; fi; }

# A clone of a bare upstream: two commits on main, plus feature/x off-upstream.
# $1: conf body, "default", or "none". $2: "armed" (default) or "bare" (no hook).
make_repo() {
    local conf="${1:-default}" armed="${2:-armed}" base up d
    base=$(mktemp -d "$TMPROOT/r.XXXXXX"); up="$base/up.git"; d="$base/repo"
    git init -q --bare -b main "$up" || die "git init --bare failed in $up"
    # 2>/dev/null was hiding git's "you appear to have cloned an empty repository"
    # note — and, with it, an actual clone failure. Silence the note, keep the status.
    git clone -q "$up" "$d" 2>/dev/null || die "git clone of $up failed"
    [ -d "$d/.git" ] || die "clone reported success but $d/.git is not there"
    git -C "$d" config user.email t@t.t
    git -C "$d" config user.name t
    git -C "$d" config merge.ff false
    if [ "$conf" != "none" ]; then
        mkdir -p "$d/.ai"
        if [ "$conf" = "default" ]; then
            printf 'PR_ONLY_BRANCHES=^main$\nPROTECTED_BRANCHES=^main$\n' > "$d/.ai/flight-rules.conf"
        else
            printf '%s\n' "$conf" > "$d/.ai/flight-rules.conf"
        fi
    fi
    echo base > "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -qm "chore: base"
    git -C "$d" push -q origin main
    echo second > "$d/s.txt"; git -C "$d" add -A; git -C "$d" commit -qm "chore: second"
    git -C "$d" push -q origin main
    git -C "$d" checkout -qb feature/x
    echo feat > "$d/g.txt"; git -C "$d" add -A; git -C "$d" commit -qm "feature: x"
    git -C "$d" checkout -q main
    if [ "$armed" = "armed" ]; then
        mkdir -p "$base/hooks"
        cp "$HOOK_SRC" "$base/hooks/reference-transaction"
        chmod +x "$base/hooks/reference-transaction"
        git -C "$d" config core.hooksPath "$base/hooks"
    fi
    git -C "$d" fetch -q origin
    # What every assertion below assumes exists. Checked once here rather than
    # rediscovered as eight confusing failures.
    git -C "$d" rev-parse --verify -q main >/dev/null        || die "no main in the fixture"
    git -C "$d" rev-parse --verify -q origin/main >/dev/null || die "no origin/main in the fixture"
    git -C "$d" rev-parse --verify -q feature/x >/dev/null   || die "no feature/x in the fixture"
    printf '%s' "$d"
}

# Did main end up somewhere that is NOT on origin/main?
escaped() {
    local d="$1" head up
    head=$(git -C "$d" rev-parse main 2>/dev/null) || return 1
    up=$(git -C "$d" rev-parse origin/main 2>/dev/null) || return 1
    git -C "$d" merge-base --is-ancestor "$head" "$up" 2>/dev/null && return 1
    return 0
}

# violation <desc> <setup-fn> <action-fn>
# setup/action take the repo dir. Asserts: escapes WITHOUT the hook, does not WITH it.
violation() {
    local desc="$1" setup="$2" action="$3" d_bare d_armed bare_escaped armed_escaped
    d_bare=$(make_repo default bare);  "$setup" "$d_bare";  "$action" "$d_bare"  >/dev/null 2>&1
    escaped "$d_bare"  && bare_escaped=yes  || bare_escaped=no
    d_armed=$(make_repo default armed); "$setup" "$d_armed"; "$action" "$d_armed" >/dev/null 2>&1
    escaped "$d_armed" && armed_escaped=yes || armed_escaped=no

    if [ "$bare_escaped" = "no" ]; then
        FAIL=$((FAIL+1))
        printf '  ❌ %s\n     INVALID TEST: does not move the ref even without the hook\n' "$desc"
    elif [ "$armed_escaped" = "yes" ]; then
        FAIL=$((FAIL+1))
        printf '  ❌ %s\n     the hook did not stop it\n' "$desc"
    else
        PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
    fi
}

# allowed <desc> <action-fn> — must exit 0 and must not strand main off-upstream.
allowed() {
    local desc="$1" action="$2" d rc
    d=$(make_repo default armed)
    "$action" "$d" >/dev/null 2>&1; rc=$?
    if [ $rc -ne 0 ]; then
        FAIL=$((FAIL+1)); printf '  ❌ %s\n     command failed (exit %s) with the hook installed\n' "$desc" "$rc"
    elif escaped "$d"; then
        FAIL=$((FAIL+1)); printf '  ❌ %s\n     left main off-upstream\n' "$desc"
    else
        PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
    fi
}

nosetup() { :; }
# `branch -f` and `update-ref` need main NOT to be the checked-out branch, or git
# refuses on its own and the case would pass without proving anything.
off_main() { git -C "$1" checkout -q feature/x; }

a_commit()      { cd "$1" && echo a >> f.txt && git add f.txt && git commit -m "chore: direct"; }
a_cherrypick()  { git -C "$1" cherry-pick "$(git -C "$1" rev-parse feature/x)"; }
a_revert()      { git -C "$1" revert --no-edit HEAD; }
a_branchf()     { git -C "$1" branch -f main "$(git -C "$1" rev-parse feature/x)"; }
a_updateref()   { git -C "$1" update-ref refs/heads/main "$(git -C "$1" rev-parse feature/x)"; }
a_merge()       { git -C "$1" merge feature/x; }
a_resethard()   { git -C "$1" reset --hard "$(git -C "$1" rev-parse feature/x)"; }
a_rebase()      { git -C "$1" rebase feature/x; }

echo "Every write path onto a PR-only branch (blocked with the hook, works without):"
violation "F3: plain commit on main"        nosetup  a_commit
violation "F2: cherry-pick onto main"       nosetup  a_cherrypick
violation "F2: revert on main"              nosetup  a_revert
violation "F4: branch -f main"              off_main a_branchf
violation "F4: update-ref main"             off_main a_updateref
violation "F1: clean local merge into main" nosetup  a_merge
violation "reset --hard onto a feature sha" nosetup  a_resethard
violation "rebase main onto a feature"      nosetup  a_rebase

echo "F1 again — the path that skips every commit-time merge hook:"
# A CONFLICTED merge: git stops before creating the merge commit, so pre-merge-commit
# never fires and the finishing commit is an ordinary one. Open in every layer until now.
s_conflict() {
    local d="$1"
    git -C "$d" checkout -qb feature/conf
    echo theirs > "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -qm "feature: conflicting"
    git -C "$d" checkout -q main
    echo ours > "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -qm "chore: ours" >/dev/null 2>&1
    git -C "$d" merge feature/conf >/dev/null 2>&1
    echo resolved > "$d/f.txt"; git -C "$d" add f.txt
}
a_finish() { git -C "$1" commit -m "Merge branch 'feature/conf'"; }
violation "conflicted merge, finishing commit" s_conflict a_finish

echo "The sanctioned operations must still work:"
x_pull()      { git -C "$1" reset -q --hard HEAD~1 && git -C "$1" pull --ff-only origin main; }
x_fetch()     { git -C "$1" fetch origin; }
x_featwork()  { cd "$1" && git checkout -q feature/x && echo q > q.txt && git add q.txt && git commit -m "feature: q"; }
x_worktree()  { git -C "$1" worktree add "$1/../wt" -b feature/wt; }
x_branchnew() { git -C "$1" branch feature/new; }
x_branchdel() { git -C "$1" branch feature/new 2>/dev/null; git -C "$1" branch -D feature/new; }
x_checkout()  { git -C "$1" checkout main; }
x_status()    { git -C "$1" status --short; }
allowed "pull --ff-only onto the reviewed head" x_pull
allowed "fetch"                                 x_fetch
allowed "commit on a feature branch"            x_featwork
allowed "worktree add -b"                       x_worktree
allowed "create a branch"                       x_branchnew
allowed "delete a local branch"                 x_branchdel
allowed "checkout main"                         x_checkout
allowed "status"                                x_status

echo "Scope — only PR-only branches are gated:"
D=$(make_repo "PR_ONLY_BRANCHES=^main\$" armed)
git -C "$D" checkout -qb dev 2>/dev/null
git -C "$D" push -q origin dev 2>/dev/null; git -C "$D" fetch -q origin
BEFORE=$(git -C "$D" rev-parse dev)
git -C "$D" merge feature/x >/dev/null 2>&1
if [ "$(git -C "$D" rev-parse dev)" != "$BEFORE" ]; then
    PASS=$((PASS+1)); printf '  ✅ a non-PR-only branch still takes a local merge\n'
else
    FAIL=$((FAIL+1)); printf '  ❌ a non-PR-only branch was gated\n'
fi

echo "Configuration:"
conf_case() { # <desc> <conf|env:VAL> <expect: blocked|allowed>
    local desc="$1" conf="$2" expect="$3" d got
    if [ "${conf#env:}" != "$conf" ]; then
        d=$(make_repo default armed); off_main "$d"
        env FLIGHT_RULES_PR_ONLY_BRANCHES="${conf#env:}" \
            git -C "$d" branch -f main "$(git -C "$d" rev-parse feature/x)" >/dev/null 2>&1
    else
        d=$(make_repo "$conf" armed); off_main "$d"
        git -C "$d" branch -f main "$(git -C "$d" rev-parse feature/x)" >/dev/null 2>&1
    fi
    escaped "$d" && got=allowed || got=blocked
    if [ "$got" = "$expect" ]; then
        PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
    else
        FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"
    fi
}
# Same defect, other layer: a commented value stopped gating.
conf_case "trailing comment still gates"  "PR_ONLY_BRANCHES=^main\$   # via PR only"  blocked
conf_case "comment, single space"         "PR_ONLY_BRANCHES=^main\$ # x"              blocked
# PROTECTED_BRANCHES=off is the opt-out the docs and the guard's own block message name.
# It disabled only the agent guard, so a project that took the documented opt-out still
# had git refusing every move — citing a key the owner never set.
conf_case "PROTECTED_BRANCHES=off opts out here too" "PROTECTED_BRANCHES=off"  allowed
conf_case "…even with PR_ONLY left at its default"   "PROTECTED_BRANCHES=off
PR_ONLY_BRANCHES=^main\$"                                                      allowed

conf_case "PR_ONLY_BRANCHES=off disables the gate" "PR_ONLY_BRANCHES=off"      allowed
conf_case "a conf naming another branch"           "PR_ONLY_BRANCHES=^nope\$"  allowed
conf_case "env override wins"                      "env:^nothing\$"            allowed
# A pattern that does not compile matches every branch, not none: grep exits 2 for it,
# which read as "no match" and let main move off its upstream (#103).
conf_case "a PR_ONLY_BRANCHES that does not compile gates main" "PR_ONLY_BRANCHES=^(main" blocked
conf_case "…from the environment too"                "env:^(main"                blocked
# Case-insensitively, as the agent guard matches (#103 review).
conf_case "PR_ONLY_BRANCHES=^MAIN\$ gates main"        "PR_ONLY_BRANCHES=^MAIN\$"  blocked
# grep read a pattern starting with `-` as an option, exited 2, and gated every branch.
conf_case "a pattern starting with - is a pattern"   "PR_ONLY_BRANCHES=-x|^nope\$" allowed
D=$(make_repo "PR_ONLY_BRANCHES=^(main" armed); off_main "$D"
OUT=$(git -C "$D" branch -f main "$(git -C "$D" rev-parse feature/x)" 2>&1); RC=$?
if [ "$RC" -ne 0 ] && grep -qF 'PR_ONLY_BRANCHES DOES NOT COMPILE' <<<"$OUT" && grep -qF '^(main' <<<"$OUT" \
   && grep -A1 -F "FLIGHT_RULES_PR_ONLY_BRANCHES='<pattern>' \\" <<<"$OUT" | grep -qF '<the same command>' \
   && grep -qF 'if main is not a branch it means' <<<"$OUT"; then
    PASS=$((PASS+1)); printf '  ✅ …refused naming the pattern, with the command that lands its fix\n'
else
    FAIL=$((FAIL+1)); printf '  ❌ …refused naming the pattern (rc=%s)\n%s\n' "$RC" "$OUT"
fi
# Every branch with an upstream, not only the one the pattern meant: feature/x, pushed.
git -C "$D" checkout -q feature/x; git -C "$D" push -q origin feature/x 2>/dev/null || die "could not push feature/x"
git -C "$D" fetch -q origin
echo more >> "$D/g.txt"; git -C "$D" add -A
git -C "$D" commit -qm "feature: more" >/dev/null 2>&1; RC=$?
if [ "$RC" -ne 0 ] && [ "$(git -C "$D" rev-parse feature/x)" = "$(git -C "$D" rev-parse origin/feature/x)" ]; then
    PASS=$((PASS+1)); printf '  ✅ …and a pushed feature branch is gated as well\n'
else
    FAIL=$((FAIL+1)); printf '  ❌ …a pushed feature branch moved off its upstream (rc=%s)\n' "$RC"
fi
# The way out the refusal prints: the pattern meant, in the environment, for that one
# command. It lifts the gate where that pattern does not reach — here feature/x.
FLIGHT_RULES_PR_ONLY_BRANCHES='^main$' git -C "$D" commit -qm "feature: more" >/dev/null 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ "$(git -C "$D" rev-parse feature/x)" != "$(git -C "$D" rev-parse origin/feature/x)" ]; then
    PASS=$((PASS+1)); printf '  ✅ …and the pattern meant, in the environment, lifts it for that command\n'
else
    FAIL=$((FAIL+1)); printf '  ❌ …the pattern meant, in the environment, did not lift it (rc=%s)\n' "$RC"
fi
# An update that moves nothing is no move. With feature/x now ahead of its upstream,
# `reset --hard HEAD` and `merge --abort` write it to the value it has, and were refused
# as moves off origin/feature/x, leaving no undo (#103 review).
AHEAD=$(git -C "$D" rev-parse feature/x)
git -C "$D" reset -q --hard HEAD >/dev/null 2>&1
say "$?" "0" "…but git reset --hard HEAD on it, ahead of its upstream, is not refused"
git -C "$D" branch side origin/feature/x
git -C "$D" checkout -q side; echo theirs > "$D/g.txt"; git -C "$D" commit -qam "feature: side" >/dev/null 2>&1 \
  || die "could not commit on side"
git -C "$D" checkout -q feature/x
git -C "$D" merge side >/dev/null 2>&1 && die "the merge of side was meant to conflict"
git -C "$D" merge --abort >/dev/null 2>&1
say "$?" "0" "…nor is git merge --abort"
say "$(git -C "$D" rev-parse feature/x)" "$AHEAD" "…and feature/x stays where it was"
echo again >> "$D/g.txt"; git -C "$D" add -A
git -C "$D" commit -qm "feature: again" >/dev/null 2>&1; RC=$?
say "$([ "$RC" -ne 0 ] && git -C "$D" rev-parse feature/x)" "$AHEAD" "…while a commit that does move it is still refused"
# A refused cherry-pick stays in progress, so "the same command" again fails there; the
# refusal names --continue, and that, with the pattern meant, lands it (#103 review).
git -C "$D" reset -q --hard HEAD >/dev/null 2>&1 || die "could not clear feature/x"
git -C "$D" checkout -q -b pick feature/x; echo p > "$D/p.txt"; git -C "$D" add -A
git -C "$D" commit -qm "feature: p" >/dev/null 2>&1 || die "could not commit on pick"
git -C "$D" checkout -q feature/x
OUT=$(git -C "$D" cherry-pick pick 2>&1); RC=$?
say "$([ "$RC" -ne 0 ] && git -C "$D" rev-parse feature/x)" "$AHEAD" "…a cherry-pick onto it is refused"
say "$(grep -c 'git cherry-pick --continue' <<<"$OUT")" "1" "…naming its --continue"
FLIGHT_RULES_PR_ONLY_BRANCHES='^main$' GIT_EDITOR=true git -C "$D" cherry-pick --continue >/dev/null 2>&1
say "$?" "0" "…which, with the pattern meant, lands it"
say "$(git -C "$D" rev-parse feature/x^)" "$AHEAD" "…on feature/x"
# A refused merge stays in progress too, and "the same command" again fails with "You
# have not concluded your merge"; git commit --no-edit concludes it (0.27.0 release review).
AHEAD=$(git -C "$D" rev-parse feature/x)
git -C "$D" checkout -q -b mrg feature/x; echo m > "$D/m.txt"; git -C "$D" add -A
git -C "$D" commit -qm "feature: m" >/dev/null 2>&1 || die "could not commit on mrg"
git -C "$D" checkout -q feature/x
OUT=$(git -C "$D" merge --no-ff mrg -m "merge mrg" 2>&1); RC=$?
say "$([ "$RC" -ne 0 ] && git -C "$D" rev-parse feature/x)" "$AHEAD" "…a merge into it is refused"
[ -f "$(git -C "$D" rev-parse --absolute-git-dir)/MERGE_HEAD" ] || die "the refused merge left no MERGE_HEAD: the case below tests nothing"
say "$(grep -c 'So is a merge it stopped: give the pattern to git commit --no-edit' <<<"$OUT")" "1" "…naming the commit that concludes it"
FLIGHT_RULES_PR_ONLY_BRANCHES='^main$' git -C "$D" merge --no-ff mrg -m "merge mrg" >/dev/null 2>&1
say "$?" "128" "…as the same command again fails"
FLIGHT_RULES_PR_ONLY_BRANCHES='^main$' git -C "$D" commit --no-edit >/dev/null 2>&1
say "$?" "0" "…while git commit --no-edit, with the pattern meant, lands it"
say "$(git -C "$D" rev-parse feature/x^1)" "$AHEAD" "…as a merge on feature/x"
conf_case "no conf at all falls back to ^main\$"   "none"                      blocked

# The working-tree conf must NOT lift the gate: editing it is the bypass the agent
# guard's own block message advertises, and this hook is the backstop for that.
D=$(make_repo default armed); off_main "$D"
printf 'PR_ONLY_BRANCHES=^nothing$\n' > "$D/.ai/flight-rules.conf"
git -C "$D" branch -f main "$(git -C "$D" rev-parse feature/x)" >/dev/null 2>&1
if escaped "$D"; then
    FAIL=$((FAIL+1)); printf '  ❌ a working-tree conf edit lifted the gate\n'
else
    PASS=$((PASS+1)); printf '  ✅ a working-tree conf edit does NOT lift the gate\n'
fi

echo "Degrade safely where there is nothing to enforce:"
BASE=$(mktemp -d "$TMPROOT/n.XXXXXX"); D="$BASE/repo"; mkdir -p "$D" "$BASE/hooks"
git init -q -b main "$D" || die "git init failed in $D"
git -C "$D" config user.email t@t.t; git -C "$D" config user.name t
echo x > "$D/f.txt"; git -C "$D" add -A; git -C "$D" commit -qm "chore: base"
cp "$HOOK_SRC" "$BASE/hooks/reference-transaction"; chmod +x "$BASE/hooks/reference-transaction"
git -C "$D" config core.hooksPath "$BASE/hooks"
BEFORE=$(git -C "$D" rev-parse main)
echo y >> "$D/f.txt"; git -C "$D" add -A; git -C "$D" commit -qm "chore: second" >/dev/null 2>&1
if [ "$(git -C "$D" rev-parse main)" != "$BEFORE" ]; then
    PASS=$((PASS+1)); printf '  ✅ a repo with no upstream is not bricked\n'
else
    FAIL=$((FAIL+1)); printf '  ❌ a repo with no upstream was blocked from committing\n'
fi

echo "Only the refusable phase acts:"
for phase in committed aborted; do
    RC=$(printf 'aaa bbb refs/heads/main\n' | bash "$HOOK_SRC" "$phase" >/dev/null 2>&1; echo $?)
    if [ "$RC" = "0" ]; then
        PASS=$((PASS+1)); printf '  ✅ state=%s is a no-op\n' "$phase"
    else
        FAIL=$((FAIL+1)); printf '  ❌ state=%s returned %s\n' "$phase" "$RC"
    fi
done

# route <output>: the two rows after "Do this instead:", frame and padding stripped, joined.
route() { grep -A2 'Do this instead:' <<<"$1" | tail -2 | sed -e 's/^║ *//' -e 's/ *║$//' | tr '\n' ' ' | sed 's/ *$//'; }
echo "The refusal's route starts where the guard and /feature-start start (full release review, S3):"
# With no start point the suggested worktree branch was cut from HEAD, the PR-only
# branch itself, into a fixed .ai/worktrees whatever WORKTREE_DIR said.
d=$(make_repo "$(printf 'PR_ONLY_BRANCHES=^main$\nPROTECTED_BRANCHES=^(main|dev)$\nINTEGRATION_BRANCH=dev\nWORKTREE_DIR=wt')" armed)
OUT=$(cd "$d" && git commit -q --allow-empty -m "chore: direct" 2>&1); RC=$?
say "$([ "$RC" -ne 0 ] && ! escaped "$d" && echo refused)" "refused" "a commit on main is refused, and main stays on origin/main"
say "$(route "$OUT")" "git worktree add wt/<name> \\ -b <prefix>/<name> origin/dev" "…routing to a branch off origin/dev in WORKTREE_DIR"
OUT=$(cd "$d" && FLIGHT_RULES_WORKTREE_DIR=elsewhere/ git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT")" "git worktree add elsewhere/<name> \\ -b <prefix>/<name> origin/dev" "…and FLIGHT_RULES_WORKTREE_DIR first, as the guard reads it"
OUT=$(cd "$d" && FLIGHT_RULES_WORKTREE_DIR="my wt" git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT")" "git worktree add 'my wt'/<name> \\ -b <prefix>/<name> origin/dev" "…a directory with a space, quoted to paste (fix review, 2026-10-26)"
d=$(make_repo default armed)
OUT=$(cd "$d" && git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT")" "git worktree add .ai/worktrees/<name> \\ -b <prefix>/<name> origin/main" "…with neither set: .ai/worktrees, off origin/main"
# Width in bytes, of rows that are ASCII between the frames: the route rows against the
# row above them. On one row the default route ran 4 columns past the frame.
say "$(grep -A2 'Do this instead:' <<<"$OUT" | awk '{ print length($0) }' | sort -u | wc -l | tr -d ' ')" "1" "…and its rows stay inside the box"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
