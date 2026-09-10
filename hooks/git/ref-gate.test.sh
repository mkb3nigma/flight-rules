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

# A clone of a bare upstream: two commits on main, plus feature/x off-upstream.
# $1: conf body, "default", or "none". $2: "armed" (default) or "bare" (no hook).
make_repo() {
    local conf="${1:-default}" armed="${2:-armed}" base up d
    base=$(mktemp -d "$TMPROOT/r.XXXXXX"); up="$base/up.git"; d="$base/repo"
    git init -q --bare -b main "$up"
    git clone -q "$up" "$d" 2>/dev/null
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
conf_case "PR_ONLY_BRANCHES=off disables the gate" "PR_ONLY_BRANCHES=off"      allowed
conf_case "a conf naming another branch"           "PR_ONLY_BRANCHES=^nope\$"  allowed
conf_case "env override wins"                      "env:^nothing\$"            allowed
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
git init -q -b main "$D"
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

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
