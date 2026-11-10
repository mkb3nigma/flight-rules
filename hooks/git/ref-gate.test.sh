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
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../test-lib.sh" || exit 2
TMPROOT=$(tmpd)
trap 'rm -rf "$TMPROOT"' EXIT


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
# Deleting the PR-only branch itself: a branch that is not PR-only never reaches the
# deletion exemption, so deleting one tested nothing it does not test above.
x_branchdel() { git -C "$1" checkout -q feature/x && git -C "$1" branch -D main; }
x_checkout()  { git -C "$1" checkout main; }
allowed "pull --ff-only onto the reviewed head" x_pull
allowed "fetch"                                 x_fetch
allowed "commit on a feature branch"            x_featwork
allowed "worktree add -b"                       x_worktree
allowed "create a branch"                       x_branchnew
allowed "delete the PR-only branch locally"     x_branchdel
allowed "checkout main"                         x_checkout

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
# PROTECTED_BRANCHES=off is the opt-out the docs and the guard's own block message name.
# It disabled only the agent guard, so a project that took the documented opt-out still
# had git refusing every move — citing a key the owner never set.
conf_case "PROTECTED_BRANCHES=off opts out here too" "PROTECTED_BRANCHES=off"  allowed
# `none` is `off` to the guard, session-start, post-merge and the doctor; here too (0.28.0
# release review).
conf_case "PROTECTED_BRANCHES=none is off here too"  "PROTECTED_BRANCHES=none" allowed
# …and from the environment, which comes first for every key.
d=$(make_repo default armed); off_main "$d"
FLIGHT_RULES_PROTECTED_BRANCHES=off git -C "$d" branch -f main feature/x >/dev/null 2>&1
say "$(escaped "$d" && echo moved)" "moved" "FLIGHT_RULES_PROTECTED_BRANCHES=off in the environment opts out too"

# …and PR_ONLY_BRANCHES=none is off, not a pattern: read as one it matches none-x
# (0.28.0 fix review).
d=$(make_repo "$(printf 'PR_ONLY_BRANCHES=none\nPROTECTED_BRANCHES=^(main|none-x)$')" armed)
git -C "$d" branch none-x main && git -C "$d" push -q origin none-x 2>/dev/null || die "could not push none-x"
git -C "$d" branch -f none-x feature/x >/dev/null 2>&1
say "$(git -C "$d" rev-parse none-x)" "$(git -C "$d" rev-parse feature/x)" "PR_ONLY_BRANCHES=none: none-x moves off its upstream"

conf_case "PR_ONLY_BRANCHES=off disables the gate" "PR_ONLY_BRANCHES=off"      allowed
# …and is no pattern: read as one it matched every branch with "off" in its name, which
# main is not, so this case pushes one and commits on it.
d=$(make_repo "PR_ONLY_BRANCHES=off" armed); git -C "$d" checkout -q -b feature/offline
git -C "$d" push -q origin feature/offline 2>/dev/null && git -C "$d" fetch -q origin || die "could not push feature/offline"
git -C "$d" commit -q --allow-empty -m "feature: more" >/dev/null 2>&1; RC=$?
say "$RC$([ "$(git -C "$d" rev-parse feature/offline)" != "$(git -C "$d" rev-parse origin/feature/offline)" ] && echo moved)" "0moved" "…a pushed feature/offline takes a commit"
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
git -C "$D" branch side origin/feature/x
git -C "$D" checkout -q side; echo theirs > "$D/g.txt"; git -C "$D" commit -qam "feature: side" >/dev/null 2>&1 \
  || die "could not commit on side"
git -C "$D" checkout -q feature/x
git -C "$D" merge side >/dev/null 2>&1 && die "the merge of side was meant to conflict"
git -C "$D" merge --abort >/dev/null 2>&1
say "$?" "0" "…but git merge --abort on it, ahead of its upstream, is not refused"
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

# route <output>: the route's rows, between "Do this instead" and "# commit there", frames
# and the `cd` row taken off, joined. cd_row <output>: the `cd` row, frame taken off.
route() { sed -n '/Do this instead/,/# commit there/p' <<<"$1" | sed -e '1d' -e '$d' -e 's/^║ *//' -e 's/ *║$//' -e '/^cd /d' | tr '\n' ' ' | sed 's/ *$//'; }
# offline <dir> <output>: the route's rows, its `cd` included, run in <dir> with origin
# unreachable — "ran" or "refused", and whether a branch was cut. In every layout the rows
# are one chain from the `cd` to the add; where the pull or fetch stood alone, the add ran
# off a stale base, exit 0 (U-1), and where the `cd` did, in another repo (T-1).
offline() {
    local d="$1" url rows rc wt
    url=$(git -C "$d" remote get-url origin)
    rows=$(sed -n '/Do this instead/,/# commit there/p' <<<"$2" | sed -e '1d' -e '$d' -e 's/^║ //' -e 's/ *║$//' -e 's|<prefix>/<name>|feature/off|; s|<name>|off|')
    git -C "$d" remote set-url origin "$d/gone.git"
    if (cd "$d" && bash -c "$rows") >/dev/null 2>&1; then rc=ran; else rc=refused; fi
    git -C "$d" remote set-url origin "$url"
    if git -C "$d" rev-parse -q --verify feature/off >/dev/null; then
        echo "$rc branch"   # cut anyway: removed, so the next case starts clean
        wt=$(git -C "$d" worktree list --porcelain | awk '/^worktree /{w=substr($0,10)} $0=="branch refs/heads/feature/off"{print w}')
        { [ -z "$wt" ] || git -C "$d" worktree remove --force "$wt"; } && git -C "$d" branch -q -D feature/off || die "could not remove feature/off in $d"
    else
        echo "$rc none"
    fi
}
cd_row() { grep -A1 'Do this instead' <<<"$1" | sed -n '2s/^║ *//p' | sed 's/ *║$//'; }
echo "The refusal's route starts where the guard and /feature-start start (full release review, S3; 0.29.0 R-1):"
# With no start point the suggested worktree branch was cut from HEAD, the PR-only
# branch itself, into a fixed .ai/worktrees whatever WORKTREE_DIR said.
d=$(make_repo "$(printf 'PR_ONLY_BRANCHES=^main$\nPROTECTED_BRANCHES=^(main|dev)$\nINTEGRATION_BRANCH=dev\nWORKTREE_DIR=wt')" armed)
OUT=$(cd "$d" && git commit -q --allow-empty -m "chore: direct" 2>&1); RC=$?
say "$([ "$RC" -ne 0 ] && ! escaped "$d" && echo refused)" "refused" "a commit on main is refused, and main stays on origin/main"
# A clone has only main locally, so dev is made from origin's, tracking it, as
# /feature-start 4 does — a pull printed for "where dev is checked out" had nowhere to
# run, and run on main it moved main (0.29.0 release-fix review, X-1, Z-1).
say "$(route "$OUT")" "git fetch origin && \\ git branch --track dev origin/dev && \\ git worktree add wt/<name> \\ -b <prefix>/<name> dev" "…routing to a branch off a local dev, made from origin's where there is none, in WORKTREE_DIR"
say "$(offline "$d" "$OUT")" "refused none" "…offline, nothing past the fetch runs"
say "$(cd_row "$OUT" | sed "s|'$(cd "$d" && pwd -P)'|<root>|; s|$(cd "$d" && pwd -P)|<root>|")" "cd <root> && \\" "…from the repo root, which it names, chained to the rest (Z-4, T-1)"
OUT=$(cd "$d" && FLIGHT_RULES_WORKTREE_DIR=elsewhere/ git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT")" "git fetch origin && \\ git branch --track dev origin/dev && \\ git worktree add elsewhere/<name> \\ -b <prefix>/<name> dev" "…and FLIGHT_RULES_WORKTREE_DIR first, as the guard reads it"
OUT=$(cd "$d" && FLIGHT_RULES_WORKTREE_DIR="my wt" git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT")" "git fetch origin && \\ git branch --track dev origin/dev && \\ git worktree add 'my wt'/<name> \\ -b <prefix>/<name> dev" "…a directory with a space, quoted to paste (fix review, 2026-10-26)"
# A local dev no live worktree holds gets origin's commits only if there are any, chained
# so a refusal (the two diverged) stops the add (W-1; owner, 2026-11-08); a worktree that
# held it and is gone is named, never pruned: git cannot tell one moved from one
# deleted, and a prune clears every worktree it cannot find (W-2, W-3, B-1, C-1..C-4).
CHAIN="git fetch origin && \\ { git merge-base --is-ancestor origin/dev dev || git fetch origin dev:dev; } && \\ git worktree add wt/<name> \\ -b <prefix>/<name> dev"
git -C "$d" branch dev 2>/dev/null
OUT=$(cd "$d" && git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT")" "$CHAIN" "…a local dev no worktree holds: origin's commits brought in if any, the fetch and the add chained"
say "$(offline "$d" "$OUT")" "refused none" "…offline, nothing past the fetch runs"
say "$(grep -c 'dev is checked out in no live worktree\.' <<<"$OUT") $(grep -c 'stop and ask\.' <<<"$OUT")" "1 1" "…said in prose above the commands, which carry no # or apostrophe (V-1)"
# The rows pasted into interactive zsh, the macOS default, where a `#` is an argument and
# an apostrophe opens a quote (V-1): with origin's dev a commit ahead, it is brought in
# and the branch cut from it. No hooks in this paste: the gate's own run is above.
if command -v zsh >/dev/null 2>&1; then
    git -C "$d" -c core.hooksPath=/dev/null push -q origin dev || die "could not push dev from $d"
    o=$(dirname "$d")/o; git clone -q "$(dirname "$d")/up.git" "$o" 2>/dev/null || die "could not clone into $o"
    git -C "$o" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m "chore: o" && git -C "$o" push -q origin HEAD:dev || die "could not move origin's dev"
    rows=$(sed -n '/Do this instead/,/# commit there/p' <<<"$OUT" | sed -e '1d' -e '$d' -e 's/^║ //' -e 's/ *║$//' -e 's|<prefix>/<name>|feature/z|; s|<name>|z|')
    (cd "$d" && zsh -f -i <<<"$rows") >/dev/null 2>&1
    say "$(git -C "$d" rev-parse -q --verify feature/z) $(git -C "$d" rev-parse dev)" "$(git -C "$o" rev-parse HEAD) $(git -C "$o" rev-parse HEAD)" "…pasted into interactive zsh: origin's commit brought in, the branch cut from it"
    if git -C "$d" rev-parse -q --verify feature/z >/dev/null; then
        git -C "$d" worktree remove "$d/wt/z" && git -C "$d" branch -q -D feature/z || die "could not remove the zsh case's worktree"
    fi
else
    echo "  ⚠️  no zsh here: the interactive-zsh paste case did not run"
fi
# dev held by a linked worktree: the pull runs there, by path, quoted to paste.
git -C "$d" worktree add -q "$d/../dev wt" dev || die "could not add a worktree for dev in $d"
OUT=$(cd "$d" && git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT" | sed "s|'$(cd "$d/.." && pwd -P)/dev wt'|<devwt>|; s|'$(cd "$d/.." && pwd)/dev wt'|<devwt>|")" "git -C <devwt> \\ pull --ff --no-rebase origin dev && \\ git worktree add wt/<name> \\ -b <prefix>/<name> dev" "…dev held by a linked worktree: the pull runs there"
say "$(offline "$d" "$OUT")" "refused none" "…offline, nothing past the pull runs"
# A pull in a checkout merges a diverged dev, and a conflict leaves the merge in progress,
# where git says to fix and commit: the prose says to stop and ask (T-2), and to abort
# nothing, since a merge there may be the person's (S-1, Q-1, P-1, O-1). Pinned whole:
# pinned in fragments, a rewording to "abort on any failure" passed (Q-3).
prose() { sed -n "/$1/,/^║ *║\$/p" <<<"$2" | sed -e 's/^║ *//' -e 's/ *║$//' | tr '\n' ' ' | sed 's/ *$//'; }
say "$(prose 'is checked out, so the pull' "$OUT")" "dev is checked out, so the pull runs in that checkout. It brings in the commits origin/dev has that it lacks, if any, merging them if the two diverged. If it fails, stop and ask, and leave whatever it left there to the person." "…said in prose above the commands: on a failure, stop and ask, aborting nothing"
# The person part-way through a merge in the dev worktree, f resolved and g not, which
# git refuses with "an unresolved conflict": the rows, run whole, refuse at the pull, and
# the merge and the resolution are left (Q-1).
w="$d/../dev wt"; nh=(-c core.hooksPath=/dev/null)
{ git -C "$w" "${nh[@]}" checkout -q -b side && echo s > "$w/f" && echo s > "$w/g" && git -C "$w" add f g && git -C "$w" "${nh[@]}" commit -q -m s \
  && git -C "$w" checkout -q dev && echo d > "$w/f" && echo d > "$w/g" && git -C "$w" add f g && git -C "$w" "${nh[@]}" commit -q -m d; } || die "could not make the merge in $w"
git -C "$w" "${nh[@]}" merge -q side >/dev/null 2>&1; git -C "$w" rev-parse -q --verify MERGE_HEAD >/dev/null || die "no merge in progress in $w"
echo resolved > "$w/f" && git -C "$w" add f || die "could not resolve f in $w"
OUT=$(cd "$d" && git commit -q --allow-empty -m "chore: direct" 2>&1)
rows=$(sed -n '/Do this instead/,/# commit there/p' <<<"$OUT" | sed -e '1d' -e '$d' -e 's/^║ //' -e 's/ *║$//' -e 's|<prefix>/<name>|feature/m|; s|<name>|m|')
say "$( (cd "$d" && bash -c "$rows") >/dev/null 2>&1 && echo ran || echo refused) $(git -C "$d" rev-parse -q --verify feature/m || echo none) $(git -C "$w" rev-parse -q --verify MERGE_HEAD >/dev/null && echo merging) $(cat "$w/f")" "refused none merging resolved" "…and the rows, run anyway, refuse at the pull, the merge and the resolution left"
git -C "$w" merge --abort || die "could not end the merge in $w"
# Moved, with work staged in it, and origin's dev strictly ahead: the rows, run whole,
# stop at git's refusal to fetch into a branch it still counts as checked out, and leave
# the worktree for git worktree repair, which a prune they once ran first had put past
# (B-1, C-4). After the repair, the pull the prose names brings origin's commit in:
# "run it again" was a dead end after a refused merge (C-1).
nh=(-c core.hooksPath=/dev/null)
git -C "$d" "${nh[@]}" push -q -f origin dev || die "could not push dev from $d"
c=$(dirname "$d")/c; git clone -q -b dev "$(dirname "$d")/up.git" "$c" 2>/dev/null \
  && git -C "$c" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m "chore: c" && git -C "$c" "${nh[@]}" push -q origin dev || die "could not move origin's dev ahead"
m="$d/../moved"; echo s > "$w/s" && git -C "$w" add s && mv "$w" "$m" || die "could not move the dev worktree from $w"
OUT=$(cd "$d" && git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT")" "$CHAIN" "…that worktree moved: git marks it prunable, so it is not pulled in, and not pruned"
gone() { prose 'was checked out at' "$1" | sed "s|'$(cd "$d/.." && pwd -P)/dev wt'|<devwt>|; s|'$(cd "$d/.." && pwd)/dev wt'|<devwt>|"; }
say "$(gone "$OUT")" "dev was checked out at <devwt>, which is gone: moved, on a disk not mounted, or deleted, which git cannot tell apart, so stop and ask. If it was moved, repair it, then pull in it, and run the add below: git worktree repair <new path> git -C <new path> pull --ff --no-rebase origin dev If it was deleted, prune, which clears every worktree git cannot find, then run the commands below: git worktree prune" "…said in prose naming the path: stop and ask; repair and pull if moved, prune if deleted"
rows=$(sed -n '/Do this instead/,/# commit there/p' <<<"$OUT" | sed -e '1d' -e '$d' -e 's/^║ //' -e 's/ *║$//' -e 's|<prefix>/<name>|feature/m|; s|<name>|m|')
dv=$(git -C "$d" rev-parse dev)
err=$( (cd "$d" && bash -c "$rows") 2>&1 >/dev/null) && rc=ran || rc=refused
say "$rc $(grep -c "refusing to fetch into branch 'refs/heads/dev' checked out at" <<<"$err") $(git -C "$d" rev-parse -q --verify feature/m || echo none) $([ "$(git -C "$d" rev-parse dev)" = "$dv" ] && echo kept)" "refused 1 none kept" "…origin's dev ahead: the rows, run whole, refuse at the fetch, as git refuses a branch it counts as checked out, dev and the branch untouched"
say "$(git -C "$d" worktree repair "$m" >/dev/null 2>&1 && git -C "$m" diff --cached --name-only)" "s" "…and leave it to repair, its staged work there"
say "$(git -C "$m" pull -q --ff --no-rebase origin dev >/dev/null 2>&1; git -C "$d" rev-parse dev)" "$(git -C "$c" rev-parse HEAD)" "…then the pull the prose names brings origin's commit in"
# Its .git file gone, the folder left: repair restores it, staged work included, which a
# prune would drop, so the prose says repair (C-2).
M=$(cd "$m" && pwd -P); rm -f "$m/.git"
OUT=$(cd "$d" && git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT") $(prose 'was checked out at' "$OUT" | sed -E "s#'?$M'?#<m>#g")" "$CHAIN dev was checked out at <m>, whose .git file is missing or broken, so stop and ask. This restores it, staged work included, though git prints an error as it does: git worktree repair <m> Then pull in it, and run the add below: git -C <m> pull --ff --no-rebase origin dev" "…its .git file gone, its folder left: not pulled in, and the prose says repair restores it"
say "$(git -C "$d" worktree repair "$m" >/dev/null 2>&1; git -C "$m" diff --cached --name-only)" "s" "…and repair restores it, its staged work there, though git exits 1"
rm -rf "$m" "$c"
OUT=$(cd "$d" && git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT") $(grep -c 'which is gone: moved' <<<"$OUT")" "$CHAIN 1" "…and the whole worktree deleted by hand: named as gone, not pulled in, not pruned"
say "$(offline "$d" "$OUT")" "refused none" "…offline, nothing past the fetch runs"
d=$(make_repo default armed)
OUT=$(cd "$d" && git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(route "$OUT")" "git pull --ff --no-rebase origin main && \\ git worktree add .ai/worktrees/<name> \\ -b <prefix>/<name> main" "…with neither set: .ai/worktrees, off the local main, pulled where the root holds it"
say "$(offline "$d" "$OUT")" "refused none" "…offline, nothing past the pull runs"
# The `cd` failing — the repo moved, a slip — stops the rows too: unchained, the pull and
# the add ran in whatever repo the shell was in, and cut a branch there (T-1).
c=$(dirname "$d")/c; git clone -q "$(dirname "$d")/up.git" "$c" 2>/dev/null || die "could not clone into $c"
rows=$(sed -n '/Do this instead/,/# commit there/p' <<<"$OUT" | sed -e '1d' -e '$d' -e 's/^║ //' -e 's/ *║$//' -e 's|<prefix>/<name>|feature/c|; s|<name>|c|')
mv "$d" "$d.moved" || die "could not move $d"
say "$( (cd "$c" && bash -c "$rows") >/dev/null 2>&1; echo $?) $(git -C "$c" rev-parse -q --verify feature/c || echo none)" "1 none" "…the cd failing: nothing runs in the repo the shell is in"
mv "$d.moved" "$d" || die "could not move $d back"
# The prose rows above the route, the longest the box holds, stay inside it.
say "$(sed -n '/is checked out, so the pull/,/Do this instead/p' <<<"$OUT" | awk '{ print length($0) }' | sort -u | wc -l | tr -d ' ')" "1" "…and its prose rows stay inside the box"
# Width in bytes, of the framed rows between the frames: the route rows against the row
# above them. On one row the default route ran 4 columns past the frame. The `cd` row
# names a temporary path, so it is left out here and has the case below.
say "$(grep -A4 'Do this instead' <<<"$OUT" | grep -v '^║   cd ' | awk '{ print length($0) }' | sort -u | wc -l | tr -d ' ')" "1" "…and its rows stay inside the box"
# A row longer than the box runs on past it unframed; the frame stays where it is (Z-4:
# a long linked-worktree path ran to 161 columns, pushing that row's edge out).
LONG=$(printf 'w%.0s' $(seq 1 80))
OUT=$(cd "$d" && FLIGHT_RULES_WORKTREE_DIR="$LONG" git commit -q --allow-empty -m "chore: direct" 2>&1)
say "$(grep -c "worktree add $LONG" <<<"$OUT") $(grep "worktree add $LONG" <<<"$OUT" | grep -c '║$')" "1 0" "…a row too long for the box is printed, and carries no right edge"
say "$(grep -A4 'Do this instead' <<<"$OUT" | grep -v "^║   cd \|$LONG" | awk '{ print length($0) }' | sort -u | wc -l | tr -d ' ')" "1" "…and the rows around it keep the frame"

finish
