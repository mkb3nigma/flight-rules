#!/usr/bin/env bash
# Mutation run: break one line of a hook (mutants.py), run the suites that should
# notice, and record whether one did. Usage: mutation/run.sh [-j N] [id …]
#
# Every mutant runs in its own copy of the tree, taken once at the start (no .git, no
# .ai/worktrees; a fresh index, so docs-consistency.test.sh's `git ls-files` reads it).
# The checkout this runs from is only read. Exit 0: every mutant expected killed was
# killed and every mutant applied. Exit 1: one survived that should not have, or one
# did not apply. Exit 2: usage, or a suite failing with no mutant applied — then no
# result would mean anything.
set -u
HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || exit 2
ROOT=$(cd -P "$HERE/.." && pwd -P) || exit 2
TIMEOUT=${MUTATION_TIMEOUT:-1200}   # seconds per suite run; a hang counts as killed

# Run one command under the timeout; its exit status, or 124 when the timeout fired.
# set -m gives the job its own process group, so the kill reaches git and the rest. Where
# the job has gone before bash can move it, bash says so on stderr: the callers log that.
# TERM first, so the suites' harness can say it was stopped; KILL ten seconds on, for a
# process that ignores TERM — a mutant can make one, and the timeout must still end it.
bounded() {   # <log> <dir> <cmd…>
    local log=$1 dir=$2 pid wd rc; shift 2
    set -m
    ( cd "$dir" && exec "$@" ) >"$log" 2>&1 &
    pid=$!
    ( sleep "$TIMEOUT"; echo timeout >"$log.timeout"; kill -TERM -- "-$pid" 2>/dev/null
      sleep 10; kill -KILL -- "-$pid" 2>/dev/null ) >/dev/null 2>&1 &
    wd=$!
    wait "$pid"; rc=$?
    kill -TERM -- "-$wd" 2>/dev/null; wait "$wd" 2>/dev/null
    set +m
    [ -e "$log.timeout" ] && rc=124
    return "$rc"
}

# --- one mutant (xargs calls this): run.sh --mutant <work> <id> ------------------------
if [ "${1:-}" = --mutant ]; then
    W=$2; id=$3
    line=$(awk -F '\t' -v id="$id" '$1 == id' "$W/list" | head -1)
    IFS=$'\t' read -r _ file suites expect <<<"$line"
    D="$W/m/$id"; L="$W/logs/$id"; R="$W/res/$id"
    mkdir -p "$D" "$L"
    cp -R "$W/base" "$D/tree" || { printf '%s\tfailed\t-\tcould not copy the tree\n' "$id" >"$R"; exit 0; }
    if ! python3 -I "$HERE/mutants.py" apply "$id" "$D/tree" >"$L/apply" 2>&1; then
        printf '%s\tapply-failed\t-\t%s\n' "$id" "$(tr '\n' ' ' <"$L/apply")" >"$R"
        rm -rf "${D:?}"; exit 0
    fi
    # A kill records the first line its suite failed on, so the summary can show why.
    verdict=survived; by=""; why=-
    for s in $suites; do
        mkdir -p "$D/tmp"
        b=$(basename "$s" .test.sh)
        TMPDIR="$D/tmp" bounded "$L/$b.log" "$D/tree" bash "$s" 2>>"$L/runner.err"; rc=$?
        if [ "$rc" -ne 0 ]; then
            case "$rc" in 2) verdict=killed-abort ;; 124) verdict=killed-timeout ;; *) verdict=killed ;; esac
            why=$(grep -m1 -E '❌|ABORTED' "$L/$b.log" | tr '\t' ' ' | cut -c1-200)
            [ "$rc" -eq 124 ] && why="timed out after ${TIMEOUT}s"
            by=$b; break
        fi
        by="$by${by:+,}$b"
    done
    printf '%s\t%s\t%s\t%s\n' "$id" "$verdict" "${by:--}" "${why:-exit $rc, no failing line}" >"$R"
    rm -rf "${D:?}"
    exit 0
fi

J=1
while getopts j:h o; do
    case $o in
        j) J=$OPTARG ;;
        *) echo "usage: mutation/run.sh [-j N] [id …]  (MUTATION_TIMEOUT=<seconds per suite>, default 1200)"; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
case "$J" in ''|*[!0-9]*|0) echo "❌ -j needs a positive number, not '$J'" >&2; exit 2 ;; esac

W=$(mktemp -d "${TMPDIR:-/tmp}/mutation.XXXXXX") && W=$(cd -P "$W" && pwd -P) || exit 2
mkdir -p "$W/base" "$W/res" "$W/logs" "$W/m"

# The tree, once: what every mutant starts from. The mutants and this script are read
# from it too, so an edit to the checkout during a run changes nothing in it.
(cd "$ROOT" && tar -cf - --exclude ./.git --exclude ./.ai/worktrees .) | (cd "$W/base" && tar -xf -) \
    || { echo "❌ could not copy $ROOT" >&2; exit 2; }
python3 -I "$W/base/mutation/mutants.py" list "$@" >"$W/list" || { echo "❌ mutants.py list failed" >&2; exit 2; }
N=$(wc -l <"$W/list" | tr -d ' ')
[ "$N" -gt 0 ] || { echo "❌ no mutants selected" >&2; exit 2; }
G=(git -C "$W/base" -c core.hooksPath=/dev/null -c user.name=mutation -c user.email=mutation@invalid -c commit.gpgsign=false)
{ "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -qm base; } >"$W/logs/git-init" 2>&1 \
    || { echo "❌ could not make the copy a repository: $W/logs/git-init" >&2; exit 2; }
if FROM=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null); then
    git -C "$ROOT" diff --quiet HEAD -- 2>/dev/null || FROM="$FROM + uncommitted changes"
else
    FROM="$ROOT (not a repository)"
fi
echo "mutation: $N mutant(s) from $FROM, -j $J, work in $W"

# Baseline: every suite the selection uses must pass on the unmutated copy.
cut -f3 "$W/list" | tr ' ' '\n' | sort -u | grep . >"$W/suites"
mkdir -p "$W/m/base"; cp -R "$W/base" "$W/m/base/tree"
bad=0
while IFS= read -r s; do
    b=$(basename "$s" .test.sh)
    TMPDIR="$W/m/base" bounded "$W/logs/baseline-$b.log" "$W/m/base/tree" bash "$s" 2>>"$W/logs/runner.err"; rc=$?
    [ "$rc" -eq 0 ] || { echo "❌ baseline: $s exited $rc with no mutant applied — $W/logs/baseline-$b.log" >&2; bad=1; }
done <"$W/suites"
rm -rf "${W:?}/m/base"
[ "$bad" -eq 0 ] || exit 2
echo "baseline: $(wc -l <"$W/suites" | tr -d ' ') suite(s) pass unmutated"

cut -f1 "$W/list" | xargs -P "$J" -n 1 bash "$W/base/mutation/run.sh" --mutant "$W"

# A kill under load is believed only if it repeats alone: an abort or a timeout can be
# the machine's, and merge-gate fails unrelated cases with several suites running (the
# sweep's eight false kills). Run alone, its result replaces the first; first/ keeps that.
if [ "$J" -gt 1 ]; then
    mkdir -p "$W/first"
    for r in "$W"/res/*; do
        [ -e "$r" ] || continue
        IFS=$'\t' read -r id v by _ <"$r"
        case "$v:$by" in killed-abort:*|killed-timeout:*|killed:merge-gate) cp "$r" "$W/first/$id" ;; esac
    done
    n=$(find "$W/first" -type f | wc -l | tr -d ' ')
    if [ "$n" -gt 0 ]; then
        echo "re-running alone $n kill(s) made under load (aborts, timeouts, merge-gate)"
        (cd "$W/first" && ls) | xargs -n 1 bash "$W/base/mutation/run.sh" --mutant "$W"
    fi
fi

# --- summary ---------------------------------------------------------------------------
python3 -I - "$W" <<'PY'
import os, sys
W = sys.argv[1]
exp, files = {}, {}
for line in open(os.path.join(W, 'list'), encoding='utf-8'):
    i, f, s, e = line.rstrip('\n').split('\t')
    exp[i] = e; files[i] = f
res = {}
for i in exp:
    p = os.path.join(W, 'res', i)
    res[i] = open(p, encoding='utf-8').read().rstrip('\n').split('\t') if os.path.exists(p) else [i, 'no-result', '-', '']
k = [i for i in exp if res[i][1].startswith('killed')]
ab = [i for i in k if res[i][1] == 'killed-abort']
to = [i for i in k if res[i][1] == 'killed-timeout']
sv = [i for i in exp if res[i][1] == 'survived']
fa = [i for i in exp if res[i][1] not in ('survived',) and not res[i][1].startswith('killed')]
unexpected = [i for i in sv if exp[i] == 'killed']
stale = [i for i in k if exp[i] != 'killed']
first = {}
fd = os.path.join(W, 'first')
if os.path.isdir(fd):
    for i in os.listdir(fd):
        first[i] = open(os.path.join(fd, i), encoding='utf-8').read().rstrip('\n').split('\t')
gone = [i for i in first if not res[i][1].startswith('killed')]
by = {}
for i in k:
    by.setdefault(res[i][2], 0); by[res[i][2]] += 1
print()
print('killed, by the suite that killed it:')
for s in sorted(by): print('  %-22s %d' % (s, by[s]))
for i in ab + to: print('  %s %s by %s: %s' % (res[i][1], i, res[i][2], res[i][3]))
if first:
    print('re-run alone: %d kill(s) made under load, %d of them repeated' % (len(first), len(first) - len(gone)))
for i in gone: print('⚠️  killed under load (%s by %s: %s), %s alone: %s' % (first[i][1], first[i][2], first[i][3], res[i][1], i))
for i in fa: print('❌ %s: %s %s %s' % (res[i][1], i, files[i], res[i][3]))
for i in unexpected: print('❌ survived, expected killed: %s (%s; ran %s) — logs in %s' % (i, files[i], res[i][2], os.path.join(W, 'logs', i)))
for i in stale: print('⚠️  killed, expected to survive (%s): %s — update its expect' % (exp[i], i))
print()
print('mutation: %d run — %d killed (%d aborts, %d timeouts), %d survived (%d expected), %d failed to apply; %d unexpected survivor(s)'
      % (len(exp), len(k), len(ab), len(to), len(sv), len(sv) - len(unexpected), len(fa), len(unexpected)))
print('logs: ' + os.path.join(W, 'logs'))
sys.exit(1 if unexpected or fa else 0)
PY
rc=$?
rm -rf "${W:?}/m" "${W:?}/base"
exit "$rc"
