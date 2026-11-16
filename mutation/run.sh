#!/usr/bin/env bash
# Mutation run: break one line of a hook (mutants.py), run the suites that should
# notice, and record whether one did. Usage: mutation/run.sh [-j N] [id …]; how far a
# run has got, read-only: mutation/run.sh --status [<work dir>] (status.py).
#
# Every mutant runs in its own copy of the tree, taken once at the start — the files git
# tracks, as they stand — with a fresh index, so docs-consistency.test.sh's `git ls-files`
# reads it. The checkout this runs from is only read, but for the stamp: after a clean
# run of the whole kit, a git note on refs/notes/mutation, origin's merged in first. Exit 0: every mutant expected killed was
# killed and every mutant applied. Exit 1: one survived that should not have, or one
# did not apply. Exit 2: usage, or a suite failing with no mutant applied, at the
# baseline, on Linux, or down the mutant path (the control) — then no result would mean
# anything — or, for the whole kit, the Linux leg not run (no Docker, no image), or a
# commit that is not the release commit (MUTATION_ANY_COMMIT=1 runs it anyway).
set -u
HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || exit 2
ROOT=$(cd -P "$HERE/.." && pwd -P) || exit 2
TIMEOUT=${MUTATION_TIMEOUT:-1200}   # seconds per suite run; a hang counts as killed
CONTROL=control   # the control's id, run down the mutant path with nothing applied; no mutant has it

# Run one command under the timeout; its exit status, or 124 when the timeout fired.
# set -m gives the job its own process group, so the kill reaches git and the rest. Where
# the job has gone before bash can move it, bash says so on stderr: the callers log that.
# TERM first, so the suites' harness can say it was stopped; KILL ten seconds on, for a
# process that ignores TERM — a mutant can make one, and the timeout must still end it.
# The suite itself exits on TERM, so the KILL is sent here too, once it has: stopping the
# watchdog then would cancel its KILL, and a child ignoring TERM outlived the run. A
# marker left by an earlier run on this log is removed first, or a re-run alone that
# passes read as a timeout again.
bounded() {   # <log> <dir> <cmd…>
    local log=$1 dir=$2 pid wd rc; shift 2
    rm -f "$log.timeout"
    set -m
    ( cd "$dir" && exec "$@" ) >"$log" 2>&1 &
    pid=$!
    ( sleep "$TIMEOUT"; echo timeout >"$log.timeout"; kill -TERM -- "-$pid" 2>/dev/null
      sleep 10; kill -KILL -- "-$pid" 2>/dev/null ) >/dev/null 2>&1 &
    wd=$!
    wait "$pid"; rc=$?
    [ -e "$log.timeout" ] && { sleep 10; kill -KILL -- "-$pid" 2>/dev/null; }
    kill -TERM -- "-$wd" 2>/dev/null; wait "$wd" 2>/dev/null
    set +m
    [ -e "$log.timeout" ] && rc=124
    return "$rc"
}

# --- one mutant (xargs calls this): run.sh --mutant <work> <id> ------------------------
if [ "${1:-}" = --mutant ]; then
    W=$2; id=$3
    if [ "$id" = "$CONTROL" ]; then line=$(cat "$W/control")
    else line=$(awk -F '\t' -v id="$id" '$1 == id' "$W/list" | head -1)
    fi
    IFS=$'\t' read -r _ file suites expect <<<"$line"
    D="$W/m/$id"; L="$W/logs/$id"; R="$W/res/$id"
    mkdir -p "$D" "$L"
    cp -R "$W/base" "$D/tree" || { printf '%s\tfailed\t-\tcould not copy the tree\n' "$id" >"$R"; exit 0; }
    if [ "$id" != "$CONTROL" ] && ! python3 -I "$HERE/mutants.py" apply "$id" "$D/tree" >"$L/apply" 2>&1; then
        printf '%s\tapply-failed\t-\t%s\n' "$id" "$(tr '\n' ' ' <"$L/apply")" >"$R"
        rm -rf "${D:?}"; exit 0
    fi
    # A kill records the first line its suite failed on, so the summary can show why.
    verdict=survived; by=""; why=-
    for s in $suites; do
        mkdir -p "$D/tmp"
        b=$(basename "$s" .test.sh)
        # MUTATION_UNDER_TEST: the mutant applied — its own anchor is gone, so the docs
        # suite's every-anchor-once case would fail for that alone, not for the mutant.
        MUTATION_UNDER_TEST=$id TMPDIR="$D/tmp" bounded "$L/$b.log" "$D/tree" bash "$s" 2>>"$L/runner.err"; rc=$?
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

# How far a run has got: read-only, from its work directory (the newest under $TMPDIR
# when none is named). It changes no result, stamp or exit status (issue: progress).
if [ "${1:-}" = --status ]; then
    exec python3 -I "$HERE/status.py" status "${2:-}"
fi

J=1
while getopts j:h o; do
    case $o in
        j) J=$OPTARG ;;
        *) echo "usage: mutation/run.sh [-j N] [id …] | --status [<work dir>]  (MUTATION_TIMEOUT=<seconds per suite>, default 1200; MUTATION_LINUX=skip, MUTATION_LINUX_IMAGE=<image>, default ubuntu:latest; MUTATION_ANY_COMMIT=1)"; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
case "$J" in ''|*[!0-9]*|0) echo "❌ -j needs a positive number, not '$J'" >&2; exit 2 ;; esac

W=$(mktemp -d "${TMPDIR:-/tmp}/mutation.XXXXXX") && W=$(cd -P "$W" && pwd -P) || exit 2
mkdir -p "$W/base" "$W/res" "$W/logs" "$W/m"

# The tree, once: what every mutant starts from. The mutants and this script are read
# from it too, so an edit to the checkout during a run changes nothing in it. In a
# repository it is the files git tracks, as they stand: an untracked file is not the
# commit — a local package-lock.json would have marked a release run dirty, unseen until
# hours later — so it is neither copied nor counted. A new file is in once `git add`ed.
# The list is made here, not in the pipe below, whose subshell an exit would not leave.
REPO=0
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    REPO=1
    git -C "$ROOT" ls-files -z >"$W/tracked" \
        || { echo "❌ git ls-files failed in $ROOT — cannot tell which files are the commit's" >&2; exit 2; }
fi
if [ "$REPO" -eq 1 ]; then
    (cd "$ROOT" && python3 -I -c 'import os, sys
sys.stdout.write("".join(f + "\0" for f in sys.stdin.read().split("\0") if f and os.path.lexists(f)))' <"$W/tracked" | tar --null -T - -cf -)
else
    (cd "$ROOT" && tar -cf - --exclude ./.git --exclude ./.flight-rules/worktrees .)
fi | (cd "$W/base" && tar -xf -) || { echo "❌ could not copy $ROOT" >&2; exit 2; }
python3 -I "$W/base/mutation/mutants.py" list "$@" >"$W/list" || { echo "❌ mutants.py list failed" >&2; exit 2; }
N=$(wc -l <"$W/list" | tr -d ' ')
# A run of the whole kit says "all <n>"; a selection says "<n> of <total>", which the
# release review check refuses: a few ids re-run to confirm a fix are not the release run.
if [ "$#" -eq 0 ]; then SCOPE=all
else SCOPE="of $(python3 -I "$W/base/mutation/mutants.py" list | wc -l | tr -d ' ')"
fi
# Every anchor, before a whole-kit run: one a hook edit moved would surface only as
# apply-failed in the summary, hours in, with no stamp (0.29.0 release review, R-2).
if [ "$SCOPE" = all ] && ! python3 -I "$W/base/mutation/mutants.py" check "$W/base" >"$W/logs/anchors" 2>&1; then
    grep -v ' 0 not anchored' "$W/logs/anchors" >&2
    echo "❌ mutants whose anchor no longer occurs exactly once — update them in the change that moved them (mutation/README.md → Upkeep), then run again" >&2
    exit 2
fi
[ "$N" -gt 0 ] || { echo "❌ no mutants selected" >&2; exit 2; }
G=(git -C "$W/base" -c core.hooksPath=/dev/null -c user.name=mutation -c user.email=mutation@invalid -c commit.gpgsign=false)
{ "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -qm base; } >"$W/logs/git-init" 2>&1 \
    || { echo "❌ could not make the copy a repository: $W/logs/git-init" >&2; exit 2; }
# What the summary line says it ran from: the full sha, which the release review check
# compares with the PR's head, and whether a tracked file differs from it. Said here, at
# the start, with the files and the route, not only in a summary hours away.
if FROM=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null); then
    DIRTY=$(git -C "$ROOT" status --short --untracked-files=no) \
        || { echo "❌ git status failed in $ROOT — cannot tell whether the tree is the commit" >&2; exit 2; }
    [ -z "$DIRTY" ] || FROM="$FROM + uncommitted changes"
else
    DIRTY=""; FROM="$ROOT (not a repository)"
fi
echo "mutation: $N mutant(s) from $FROM, -j $J, work in $W"

# way_past VAR=value: the command that goes ahead anyway, with every MUTATION_* setting
# this run was given and VAR=value added. Each stop printing only its own variable made
# two stops send the person back and forth: the commit check's command lacked the skip,
# the Linux stop's lacked MUTATION_ANY_COMMIT (the release-commit check's /dg, DN1).
way_past() {
    local v out="" new=${1%%=*}
    for v in MUTATION_ANY_COMMIT MUTATION_LINUX MUTATION_LINUX_IMAGE MUTATION_TIMEOUT; do
        [ "$v" = "$new" ] && continue
        [ -n "${!v:-}" ] && out="$out$v=$(printf '%q' "${!v}") "
    done
    printf '%s%s mutation/run.sh -j %s' "$out" "$1" "$J"
}
ANY_NOTE=""

# The release commit: a whole-kit run is hours, and its stamp vouches for one commit, so
# it runs on the tip of the integration branch with every change in, just before the
# dev → main PR (owner, 2026-11-16: "they should ideally run on dev when all changes are
# done and just before dev->main PR"). Before the baseline it checks that HEAD is that tip,
# with no tracked file changed, and that origin's branch holds nothing it lacks (read
# with ls-remote: the checkout is not written). Anything else stops it, named, with the
# route and the way past: MUTATION_ANY_COMMIT=1, for a run the owner called for on
# another commit (a major change before it merges, mutation/README.md), said at the
# start and the end when given. A stop removes the copy it made. A selection is not the
# release run and is not checked.
if [ "$SCOPE" = all ] && [ "${MUTATION_ANY_COMMIT:-}" = 1 ]; then
    ANY_NOTE="⚠️  not checked as the release commit (MUTATION_ANY_COMMIT=1)"
    echo "$ANY_NOTE"
elif [ "$SCOPE" = all ] && [ "$REPO" -eq 1 ]; then
    INT=$(sed -n 's/^[[:space:]]*INTEGRATION_BRANCH[[:space:]]*=[[:space:]]*//p' "$ROOT/.flight-rules/conf" 2>/dev/null \
          | tail -1 | sed -e 's/[[:space:]]*#.*$//' -e "s/^[\"']//" -e "s/[\"']$//")
    INT=${INT:-dev}
    off=()
    head_sha=$(git -C "$ROOT" rev-parse HEAD)
    if ! int_sha=$(git -C "$ROOT" rev-parse -q --verify "refs/heads/$INT^{commit}"); then
        off+=("there is no local $INT")
    elif [ "$head_sha" != "$int_sha" ]; then
        off+=("HEAD ($head_sha) is not the tip of local $INT ($int_sha)")
    fi
    [ -z "$DIRTY" ] || off+=("tracked files differ from the commit: $(printf '%s' "$DIRTY" | tr '\n' ' ')")
    if ! remote=$(git -C "$ROOT" ls-remote --exit-code origin "refs/heads/$INT" 2>/dev/null); then
        off+=("origin's $INT could not be read (offline, or no origin) to check it holds nothing HEAD lacks")
    else
        rsha=${remote%%[[:space:]]*}
        git -C "$ROOT" merge-base --is-ancestor "$rsha" "$head_sha" 2>/dev/null \
            || off+=("origin's $INT ($rsha) has commits HEAD lacks: bring them into $INT first, in the $INT checkout (git pull --ff --no-rebase origin $INT), then make the worktree again")
    fi
    if [ "${#off[@]}" -gt 0 ]; then
        printf '❌ not the release commit, so no mutant is run: %s\n' "${off[@]}" >&2
        echo "   a release run is on the tip of local $INT, every change in, just before the $INT → main PR (AGENTS.md → Releasing):" >&2
        echo "   git worktree add --detach .flight-rules/worktrees/mutation $INT   and run it there (one left from an earlier run: git worktree remove .flight-rules/worktrees/mutation first)" >&2
        echo "   to run on this commit anyway (a run the owner called for): $(way_past MUTATION_ANY_COMMIT=1)" >&2
        rm -rf "${W:?}"   # the copy made above: nothing of a run that never started is left
        exit 2
    fi
fi
# What --status reads: the run's facts and this machine's, then each step as it begins.
phase() { printf '%s\t%s\t%s\n' "$1" "$(date +%s)" "${2:-}" >>"$W/phases"; }
python3 -I "$W/base/mutation/status.py" init "$W" "started=$(date +%s)" "pid=$$" "from=$FROM" "scope=$SCOPE" \
    "n=$N" "j=$J" "timeout=$TIMEOUT" "bash=$BASH_VERSION" "git=$(git --version 2>/dev/null)" \
    || echo "⚠️  could not write $W/run.info: --status will say less about this run" >&2
echo "   progress, any time: mutation/run.sh --status $W"
if [ -n "$DIRTY" ]; then
    printf '%s\n' "⚠️  these differ from the commit, so the release review check will not take this run:" "$DIRTY" \
        "   for a release, run it from a clean worktree of the commit (mutation/README.md):" \
        "   git worktree add --detach .flight-rules/worktrees/mutation $(git -C "$ROOT" rev-parse HEAD)"
fi

# Baseline: every suite the selection uses must pass on the unmutated copy.
phase baseline
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

# Linux: CI runs the suites on ubuntu-latest too, but sees dev only once it is pushed.
# In 0.29.0 the runner had moved to Ubuntu 26.04 (bash 5.3) since the last push, and
# its failures surfaced on the release PR after a six-hour stamped run, which had to
# be made again (2026-11-16). So a whole-kit run first runs the same suites once on
# Linux: in Docker's ubuntu:latest, the newest Ubuntu LTS, which GitHub's ubuntu-latest
# runner tracks with a lag of its own, pulled fresh each run (a cached tag never
# moves); as a user that is not root, LANG C.UTF-8 as on the runner, en_US.UTF-8
# installed for the suites that name it. It is not the runner: on Apple silicon the
# container is arm64, the runner x86_64, and it has only the tools installed below.
# Each suite is cut off after MUTATION_TIMEOUT seconds; --init with the process-group
# kill lets Ctrl-C reach the suites (--init alone did not, round 2 of its review). It
# adds about a minute to set up, then one pass of the suites. A suite failing there,
# or the leg not running at all, stops the run before any mutant, and every such stop
# prints the way on: MUTATION_LINUX=skip, the person's to set, after which the release
# PR's CI is the first Linux run. Either way the closing lines say how the leg went. A
# selection skips the leg: it is not the release run.
LINUX_IMAGE=${MUTATION_LINUX_IMAGE:-ubuntu:latest}
LINUX_NOTE=""
linux_stop() {   # <what went wrong> [<its log>]: the stop, its log, and the way on
    echo "❌ linux: $1 — its log: ${2:-$W/logs/linux.log}. No mutant was run, and nothing is stamped" >&2
    echo "   to go on without the Linux leg (the release PR's CI is then the first Linux run): $(way_past MUTATION_LINUX=skip)" >&2
    exit 2
}
if [ "$SCOPE" = all ] && [ "${MUTATION_LINUX:-}" = skip ]; then
    LINUX_NOTE="⚠️  linux: skipped (MUTATION_LINUX=skip) — the release PR's CI is the first Linux run"
    echo "$LINUX_NOTE"; phase linux-skipped
elif [ "$SCOPE" = all ]; then
    phase linux "$LINUX_IMAGE"
    # docker info's output has a log of its own: in linux.log it came first, and a
    # healthy line of it ("… failed to fetch metadata", or its last line) was named as
    # the cause of a pull or setup failure (the leg's third /dg, F1).
    : >"$W/logs/linux.log"
    if ! docker info >"$W/logs/docker-info.log" 2>&1; then
        linux_stop "Docker is not running, or not installed, so the suites could not run on Linux, as CI's ubuntu-latest will; start Docker and run again" "$W/logs/docker-info.log"
    fi
    # The timeout and the suites, one per line, passed to the container as arguments;
    # its own script is single-quoted, so nothing here is expanded twice. The copy's
    # .git is the host's (the base commit made above, macOS settings and all): it goes,
    # and the container commits the tree afresh, as a CI checkout has it.
    # shellcheck disable=SC2016
    docker run --rm --pull always --init -e TINI_KILL_PROCESS_GROUP=1 -v "$W/base":/src:ro "$LINUX_IMAGE" bash -c '
        export DEBIAN_FRONTEND=noninteractive
        { apt-get update -qq && apt-get install -y -qq git jq python3 procps locales zsh; } >/tmp/apt.log 2>&1 \
            || { tail -20 /tmp/apt.log; echo "linux-setup-failed: apt-get (offline?)"; exit 3; }
        { sed -i "s/^# *en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen && locale-gen; } >/tmp/locale.log 2>&1 \
            || { cat /tmp/locale.log; echo "linux-setup-failed: locale-gen"; exit 3; }
        useradd -m -s /bin/bash mut || { echo "linux-setup-failed: useradd"; exit 3; }
        . /etc/os-release; echo "linux-image: $PRETTY_NAME $(uname -m), bash $(bash -c "echo \$BASH_VERSION")"
        su mut -c "set -u; export LANG=C.UTF-8; to=\$1; shift
            cp -R /src ~/w && cd ~/w && rm -rf .git && git init -q && git add -A \
              && git -c user.name=mutation -c user.email=mutation@invalid -c core.hooksPath=/dev/null commit -qm base \
              || { echo linux-setup-failed: copy; exit 3; }
            for s in \"\$@\"; do timeout --kill-after=10 \"\$to\" bash \"\$s\" >~/out 2>&1; echo \"linux-suite: \$? \$s\"; cat ~/out; done" _ "$@"
    ' _ "$TIMEOUT" $(cat "$W/suites") >>"$W/logs/linux.log" 2>&1; lrc=$?
    nsuites=$(wc -l <"$W/suites" | tr -d ' ')
    npass=$(grep -c '^linux-suite: 0 ' "$W/logs/linux.log")
    if [ "$lrc" -ne 0 ] || [ "$npass" -ne "$nsuites" ]; then
        # A container that never started (an image that cannot be pulled, Ctrl-C during
        # the pull) or was not set up ran no suite: said as that, not as every suite
        # failing. The cause named is the setup step that failed, else the first error
        # Docker wrote, else its last line; linux.log holds only what docker run wrote.
        if grep -q '^linux-setup-failed' "$W/logs/linux.log" || ! grep -q '^linux-image: ' "$W/logs/linux.log"; then
            why=$(grep -m1 '^linux-setup-failed' "$W/logs/linux.log")
            [ -n "$why" ] || why=$(grep -v '^linux-' "$W/logs/linux.log" | grep -iE -m1 'error|unable|denied|cannot|failed')
            [ -n "$why" ] || why=$(grep -v '^linux-' "$W/logs/linux.log" | grep . | tail -1)
            linux_stop "the container did not start or was not set up on $LINUX_IMAGE (docker exited $lrc)${why:+: $why}"
        fi
        # 124: timeout's TERM ended it; 137: it ignored TERM and --kill-after killed it.
        grep -E '^linux-suite: (124|137) ' "$W/logs/linux.log" | sed -E "s/^linux-suite: (124|137) /❌ linux: timed out after ${TIMEOUT}s (exit \1) — /" >&2
        grep -E '^linux-suite: [1-9]' "$W/logs/linux.log" | grep -vE '^linux-suite: (124|137) ' | sed 's/^linux-suite: \([0-9]*\) /❌ linux: exited \1 — /' >&2
        linux_stop "$npass of $nsuites suite(s) passed on $LINUX_IMAGE$([ "$lrc" -ne 0 ] && echo " (docker exited $lrc)")"
    fi
    lname=$(sed -n 's/^linux-image: //p' "$W/logs/linux.log")
    LINUX_NOTE="linux: $nsuites suite(s) passed on $LINUX_IMAGE ($lname)"
    echo "linux: $nsuites suite(s) pass on $LINUX_IMAGE ($lname)"
    printf '%s\t%s\t%s\n' linux-passed "$(date +%s)" "$lname" >>"$W/phases"
fi

# The control: those suites once more, down the path a mutant takes — its own copy of
# the tree, TMPDIR under it, MUTATION_UNDER_TEST set, the verdict as a mutant's is
# written — with nothing applied. A kill is any non-zero suite exit, and the baseline
# runs another path, so a fault in this one alone read as every mutant killed, and a
# whole-kit run stamped clean (0.29.0 release review, second pass, V4).
phase control
printf '%s\t-\t%s\tkilled\n' "$CONTROL" "$(tr '\n' ' ' <"$W/suites" | sed 's/ $//')" >"$W/control"
bash "$W/base/mutation/run.sh" --mutant "$W" "$CONTROL"
cv=no-result; cby=-; cwhy=""
[ -e "$W/res/$CONTROL" ] && IFS=$'\t' read -r _ cv cby cwhy <"$W/res/$CONTROL"
if [ "$cv" != survived ]; then
    echo "❌ control: with nothing mutated, $cby failed down the path a mutant takes ($cv: $cwhy) — its log: $W/logs/$CONTROL/$cby.log. Every mutant would read as killed by that; none was run, and nothing is stamped" >&2
    exit 2
fi
rm -f "$W/res/$CONTROL"
echo "control: $(wc -l <"$W/suites" | tr -d ' ') suite(s) pass down the path a mutant takes, with nothing mutated"

# A line of progress every MUTATION_PROGRESS seconds (default 600; 0: none) while the
# mutants run, so a run of hours says how far it has got without being asked. It stops
# with the run, and if the run is killed: it checks the run is still there each time.
# The sleep holds no output: killed with the loop, it would hold the run's stdout open
# for up to EVERY seconds after the summary, and a caller reading that waited.
phase mutants
EVERY=${MUTATION_PROGRESS:-600}
case "$EVERY" in ''|*[!0-9]*) EVERY=600 ;; esac
TICK=""
if [ "$EVERY" -gt 0 ]; then
    ( while sleep "$EVERY" >/dev/null 2>&1 && kill -0 $$ 2>/dev/null; do python3 -I "$W/base/mutation/status.py" line "$W"; done ) &
    TICK=$!
fi
cut -f1 "$W/list" | xargs -P "$J" -n 1 bash "$W/base/mutation/run.sh" --mutant "$W"

# A kill under load is believed only if it repeats alone: an abort or a timeout can be
# the machine's, merge-gate fails unrelated cases with several suites running (the
# sweep's eight false kills), and so can a case with a time bound — "(bound 8s)", "(want
# ≤30)", "want 'bounded'" — when that is the first case to fail. Run alone, its result
# replaces the first; first/ keeps that.
if [ "$J" -gt 1 ]; then
    mkdir -p "$W/first"
    for r in "$W"/res/*; do
        [ -e "$r" ] || continue
        IFS=$'\t' read -r id v by why <"$r"
        case "$v:$by" in killed-abort:*|killed-timeout:*|killed:merge-gate) cp "$r" "$W/first/$id"; continue ;; esac
        case "$v:$why" in killed:*'(bound '[0-9]*|killed:*'(want ≤'[0-9]*|killed:*"want 'bounded'"*) cp "$r" "$W/first/$id" ;; esac
    done
    n=$(find "$W/first" -type f | wc -l | tr -d ' ')
    if [ "$n" -gt 0 ]; then
        echo "re-running alone $n kill(s) made under load (aborts, timeouts, merge-gate, time bounds)"
        phase rerun "$n"
        (cd "$W/first" && ls) | xargs -n 1 bash "$W/base/mutation/run.sh" --mutant "$W"
    fi
fi

[ -n "$TICK" ] && { kill "$TICK" 2>/dev/null; wait "$TICK" 2>/dev/null; }

# --- summary ---------------------------------------------------------------------------
phase summary
python3 -I - "$W" "$FROM" "$SCOPE" <<'PY'
import os, sys
W, FROM, SCOPE = sys.argv[1], sys.argv[2], sys.argv[3]
# A failing line cut by bytes can end mid-character: read it, never crash on it.
def rd(p): return open(p, encoding='utf-8', errors='replace')
exp, files = {}, {}
for line in rd(os.path.join(W, 'list')):
    i, f, s, e = line.rstrip('\n').split('\t')
    exp[i] = e; files[i] = f
res = {}
for i in exp:
    p = os.path.join(W, 'res', i)
    res[i] = rd(p).read().rstrip('\n').split('\t') if os.path.exists(p) else [i, 'no-result', '-', '']
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
        first[i] = rd(os.path.join(fd, i)).read().rstrip('\n').split('\t')
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
summary = ('mutation: %s run from %s — %d killed (%d aborts, %d timeouts), %d survived (%d expected), %d failed to apply; %d unexpected survivor(s)'
      % ('all %d' % len(exp) if SCOPE == 'all' else '%d %s' % (len(exp), SCOPE), FROM, len(k), len(ab), len(to), len(sv), len(sv) - len(unexpected), len(fa), len(unexpected)))
print(summary)
print('logs: ' + os.path.join(W, 'logs'))
# The stamp the release review check reads (mutants.py verify): written only for a clean
# run of the whole kit on a commit with no tracked file changed. Anything less is said.
why = ('it was a selection, not the whole kit' if SCOPE != 'all'
       else 'the tree is not a commit with no tracked file changed' if len(FROM) != 40 or not all(c in '0123456789abcdef' for c in FROM)
       else 'the run did not pass' if unexpected or fa else '')
if why:
    open(os.path.join(W, 'unstamped'), 'w', encoding='utf-8').write(why)
else:
    with open(os.path.join(W, 'stamp'), 'w', encoding='utf-8') as f:
        f.write('flight-rules mutation stamp\n' + summary + '\n')
        for i in sorted(exp): f.write('%s\t%s\t%s\n' % (i, res[i][1], res[i][2]))
sys.exit(1 if unexpected or fa else 0)
PY
rc=$?
# The stamp goes on the commit as a git note, and the push it needs is printed every
# time: the release review check refuses the PR without it (owner, 2026-11-05: the
# instruction is shown, never left to memory). Every machine keeps its own copy of the
# notes ref, so origin's stamps are merged in first — a push from a machine that never
# fetched them was rejected, and forcing it would have dropped the other machine's. On
# the same commit, the stamp written here replaces origin's.
# How the Linux leg went, beside the closing lines: a skip is said hours later too.
[ -n "$LINUX_NOTE" ] && echo "$LINUX_NOTE"
[ -n "$ANY_NOTE" ] && echo "$ANY_NOTE"
MERGE="git fetch origin refs/notes/mutation:refs/notes/mutation-origin && git notes --ref=mutation merge -s theirs refs/notes/mutation-origin"
if [ -s "$W/stamp" ]; then
    merged=0
    git -C "$ROOT" ls-remote --exit-code origin refs/notes/mutation >/dev/null; lr=$?
    if [ "$lr" -eq 2 ]; then merged=1   # origin has no stamps yet: nothing to merge
    elif [ "$lr" -eq 0 ] && git -C "$ROOT" fetch -q origin refs/notes/mutation:refs/notes/mutation-origin \
        && git -C "$ROOT" notes --ref=mutation merge -q -s theirs refs/notes/mutation-origin; then merged=1
    fi
    git -C "$ROOT" notes --ref=mutation add -f -F "$W/stamp" "$FROM" \
        || { echo "❌ could not write the mutation stamp on $FROM" >&2; exit 2; }
    echo
    echo "✅ stamped $FROM (refs/notes/mutation). Before the release PR, push the stamp:"
    echo "   git push origin refs/notes/mutation"
    [ "$merged" -eq 1 ] || echo "⚠️  origin's stamps could not be fetched and merged (git said why above), so that push may be rejected. First: $MERGE"
    echo "   If the push is rejected — another machine pushed stamps since — run: $MERGE"
    echo "   then push again. Never force it: that drops the other machine's stamps."
    # A worktree made for the run is left behind once it is done, and blocks the next
    # release's `worktree add` at the same path (0.29.0 release review, R-3).
    [ "$(git -C "$ROOT" rev-parse --git-dir)" = "$(git -C "$ROOT" rev-parse --git-common-dir)" ] \
        || printf '   Once it is pushed, remove this worktree: git worktree remove %q\n' "$ROOT"
else
    echo
    echo "not stamped: $(cat "$W/unstamped") — a release needs a clean run of the whole kit from a clean worktree of its commit (mutation/README.md)"
fi
rm -rf "${W:?}/m" "${W:?}/base"
phase done "$rc"
exit "$rc"
