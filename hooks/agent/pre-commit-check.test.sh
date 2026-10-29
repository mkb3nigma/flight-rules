#!/usr/bin/env bash
# Tests for pre-commit-check.sh — the branch-policy and secret guard.
#
# The hook is the only thing standing between an agent and a protected branch, so
# it needs to fail loudly rather than silently stop matching. Run: ./pre-commit-check.test.sh
#
# Each case builds a throwaway git repo, feeds the hook a PreToolUse payload, and
# asserts on whether a "deny" decision comes back.

set -uo pipefail
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pre-commit-check.sh"
PASS=0; FAIL=0
# Assembled at run time so this file never carries a literal key for a scanner to flag.
AKIA=$(printf 'AKIA%s' IOSFODNN7EXAMPLE)

# A fixture that cannot be built is not a test failure, it is an aborted run — so it
# stops the suite rather than being counted. make_repo runs inside a command
# substitution, where a FAIL increment would be discarded with the subshell; `$$` is the
# parent's pid even there, so the signal reaches the trap. Measured 2026-09-12: with the
# fixture's `git init` broken this suite still scored 267 of 574.
MAINPID=$$
trap 'printf "\n%s\n" "ABORTED: a fixture could not be built — no result above is meaningful" >&2; exit 2' TERM
die() { printf '  ❌ harness: %s\n' "$1" >&2; kill -s TERM "$MAINPID"; exit 2; }

# A repo on $1, with the hook scoped to it via CLAUDE_PROJECT_DIR.
make_repo() {
  local branch="$1" dir
  # Resolve symlinks: on macOS mktemp hands back /var/... while git reports the
  # real /private/var/..., and the hook's project-scoping compares the two.
  dir=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$dir" init -q || die "git init failed in $dir"
  git -C "$dir" config user.email t@t.t
  git -C "$dir" config user.name t
  echo x > "$dir/f.txt"
  git -C "$dir" add -A >/dev/null 2>&1
  git -C "$dir" commit -qm init >/dev/null 2>&1 || die "the init commit failed in $dir"
  git -C "$dir" branch -M "$branch" >/dev/null 2>&1 || die "could not rename the branch to $branch"
  # The branch IS the fixture here: every verdict below depends on which one is checked
  # out. A rename that failed leaves the repo on the default branch and the case tests
  # the wrong policy.
  [ "$(git -C "$dir" branch --show-current)" = "$branch" ] \
    || die "fixture is on $(git -C "$dir" branch --show-current), not $branch"
  printf '%s' "$dir"
}

# What the exit-status guards below do and do not prove. The guard signals a block by
# printing JSON and exiting 0; an allow is silence and exit 0. So a non-zero exit means
# the hook DIED, and is reported as a harness failure rather than counted as an allow.
# Two limits, accepted rather than papered over:
#   - an allow is still the absence of a deny. A hook that exits 0 having decided
#     nothing passes every allow case, and there is no signal that would tell them
#     apart while allow stays silent by contract.
#   - if the guard ever moves to exit-status signalling (non-zero = block), these
#     guards would read a legitimate block as a crash. They are pinned to the current
#     JSON contract deliberately; change both together.
# check <description> <expect: deny|allow> <branch> <command> [env assignments...]
check() {
  local desc="$1" expect="$2" branch="$3" cmd="$4"; shift 4
  local dir out got rc
  dir=$(make_repo "$branch")
  # Run from inside the repo so a command with no `cd`/`-C` resolves there.
  out=$(cd "$dir" && CLAUDE_PROJECT_DIR="$dir" env "$@" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null); rc=$?
  if [[ $rc -ne 0 ]]; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: the hook exited %s — a verdict was never reached\n' "$desc" "$rc"
    rm -rf "$dir"; return
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [[ "$got" == "$expect" ]]; then
    PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"
  fi
  rm -rf "$dir"
}

# check_wt <description> <expect> <main-checkout branch> <worktree branch> <command>
# The same assertion, but run from a worktree at .ai/worktrees/x — where the
# workflow says all work happens, and where the branch policy used to switch
# itself off because a worktree's toplevel is never CLAUDE_PROJECT_DIR.
check_wt() {
  local desc="$1" expect="$2" branch="$3" wt_branch="$4" cmd="$5"
  local dir out got rc
  dir=$(make_repo "$branch")
  if ! git -C "$dir" worktree add -q "$dir/.ai/worktrees/x" -b "$wt_branch" >/dev/null 2>&1; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: worktree add failed — nothing was tested\n' "$desc"
    rm -rf "$dir"; return
  fi
  out=$(cd "$dir/.ai/worktrees/x" && CLAUDE_PROJECT_DIR="$dir" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null); rc=$?
  if [[ $rc -ne 0 ]]; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: the hook exited %s — a verdict was never reached\n' "$desc" "$rc"
    rm -rf "$dir"; return
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [[ "$got" == "$expect" ]]; then
    PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"
  fi
  git -C "$dir" worktree remove --force "$dir/.ai/worktrees/x" >/dev/null 2>&1
  rm -rf "$dir"
}

echo "Protected branch — destructive commands must be blocked:"
check "git rm on dev"                    deny  dev  'git rm .ai/rules/x.md'
check "git rm with -C on dev"            deny  dev  "git -C . rm f.txt"
check "git reset --hard on main"         deny  main 'git reset --hard HEAD~1'
check "git clean -fd on dev"             deny  dev  'git clean -fd'
check "git clean --force on dev"         deny  dev  'git clean --force'
check "git checkout -- . on dev"         deny  dev  'git checkout -- .'
check "git restore on staging"           deny  staging 'git restore f.txt'
# Unstaging and untracking touch no file in the tree (mission review H4, 2026-10-29), so
# their plain form is allowed; anything not plainly that is judged as before.
check "restore --staged on dev"          allow dev 'git restore --staged f.txt'
check "restore -S, two paths"            allow dev 'git restore -S a.txt b.txt'
check "restore --staged ."               allow dev 'git restore --staged .'
check "restore --source --staged"        allow dev 'git restore --source=HEAD~1 --staged f.txt'
check "rm --cached on dev"               allow dev 'git rm --cached f.txt'
check "rm -r --cached"                   allow dev 'git rm -r --cached build/'
check "restore --staged --worktree"      deny  dev 'git restore --staged --worktree f.txt'
check "restore --staged --work (prefix)" deny  dev 'git restore --staged --work f'
check "restore -SW"                      deny  dev 'git restore -SW f.txt'
check "restore -s (source: writes the tree)" deny dev 'git restore -s HEAD f.txt'
check "restore --STAGED (not git's)"     deny  dev 'git restore --STAGED f.txt'
check "restore --no-staged"              deny  dev 'git restore --staged --no-staged f'
check "rm --cached --no-cached"          deny  dev 'git rm --cached --no-cached f'
check "rm --end-of-options"              deny  dev 'git rm --cached --end-of-options f'
check "rm -- --cached (a path)"          deny  dev 'git rm -- --cached'
check "rm, --cached quoted"              deny  dev "git rm f '--cached'"
check "rm, --cached in a comment"        deny  dev 'git rm b # --cached'
check "rm --cached, a rm in backticks"   deny  dev 'git rm --cached a `git rm b`'
check "rm --cached, a glob"              deny  dev 'git rm --cached *.log'
check "plain restore, --staged elsewhere" deny dev 'git restore f.txt && echo --staged'
check "rm --cached then plain rm"        deny  dev 'git rm --cached a && git rm b'
check "rm --cached under a git prefix"   allow dev 'git --no-pager rm --cached f'   # normalised to the plain form
check "rm under a git prefix"            deny  dev 'git --no-pager rm f'
check "git commit on dev (regression)"   deny  dev  'git commit -m "x"'

echo "Shell metacharacters must not smuggle a destructive command past the guard:"
# Regression: the first version enumerated separators (space ; & |) and so missed "("
# entirely — a subshell or command substitution was allowed on a protected branch.
# Found in the wild: a verification command of the form `echo x && (git rm ...)` ran
# unblocked on dev.
check "subshell"                         deny  dev '(git rm f.txt)'
check "subshell after &&"                deny  dev 'echo x && (git rm f.txt)'
check "command substitution"             deny  dev 'out=$(git rm f.txt)'
check "backtick substitution"            deny  dev 'out=`git rm f.txt`'
check "brace group"                      deny  dev '{ git rm f.txt; }'
check "if-then"                          deny  dev 'if true; then git rm f.txt; fi'
check "pipeline"                         deny  dev 'git rm f.txt | cat'
check "reset --hard in a subshell"       deny  dev '(git reset --hard HEAD~1)'
# ...without matching words that merely contain the letters "git"
check "mygit is not git"                 allow dev 'mygit rm f.txt'
check "legit is not git"                 allow dev 'legit rm f.txt'
check "git-foo is not git rm"            allow dev 'git-foo rm f.txt'

echo "Protected branch — safe commands must pass:"
check "git clean -n (dry run)"           allow dev  'git clean -n'
check "git status"                       allow dev  'git status --short'
check "git checkout <branch>"            allow dev  'git checkout main'
check "git log"                          allow dev  'git log --oneline -5'
check "unrelated rm"                     allow dev  'rm -rf /tmp/scratch'
check "npm command mentioning git"       allow dev  'npm run git-info'

echo "Feature branch — the same commands are fine:"
check "git rm on a feature branch"       allow feature/x 'git rm f.txt'
check "git reset --hard on feature"      allow feature/x 'git reset --hard HEAD'
check "git commit on feature"            allow feature/x 'git commit -m "x"'

echo "Default protected set covers the common conventions:"
check "master"                           deny  master      'git rm f'
check "develop (git-flow)"               deny  develop     'git rm f'
check "development"                      deny  development 'git rm f'
check "staging"                          deny  staging     'git rm f'
check "qa"                               deny  qa          'git rm f'
check "QA (case-insensitive)"            deny  QA          'git rm f'
check "Main (case-insensitive)"          deny  Main        'git rm f'
check "uat"                              deny  uat         'git rm f'
check "production"                       deny  production  'git rm f'
check "release (bare)"                   deny  release     'git rm f'
check "release/1.0 (train)"              deny  release/1.0 'git rm f'

echo "Default set does NOT over-reach:"
check "hotfix/x is a working branch"     allow hotfix/x     'git rm f'
check "feature/release-notes"            allow feature/release-notes 'git rm f'
check "releases-page (not a release)"    allow releases-page 'git rm f'
check "devtools (not dev)"               allow devtools     'git rm f'

echo "Configurable protected set:"
check "custom: release/1.0 protected"    deny  release/1.0 'git rm f.txt' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^(main|release/.*)$'
check "custom: dev no longer protected"  allow dev  'git rm f.txt' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^(main|release/.*)$'
# Pins the documented footgun: the variable REPLACES the defaults, so a narrow
# custom value leaves previously-protected branches open. If this ever starts
# failing, the override became additive and the README is wrong.
check "custom REPLACES, not extends"     allow main 'git rm f.txt' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^integration$'
check "custom: worktree dir in message"  deny  main 'git rm f.txt' \
      FLIGHT_RULES_WORKTREE_DIR='.worktrees'
# A pattern bash cannot compile protected nothing: =~ returned 2, read as no match, and
# a commit landed on the branch the typo meant to name (#103). Every branch is
# protected until it is fixed; a valid pattern still lets a branch it does not name be.
check "broken pattern: the branch it names"   deny  trunk     'git commit -m x' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^(trunk'
check "broken pattern: any other branch too"  deny  feature/x 'git commit -m x' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^(trunk'
check "broken pattern: a destructive command" deny  feature/x 'git reset --hard HEAD~1' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^(trunk'
check "valid pattern: a branch it does not name" allow feature/x 'git commit -m x' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^(trunk)$'
# The broken pattern in the conf, and a command run against it: <desc> <branch>
# <command> <verdict> <text the output must hold> <text it must not> [env…].
broken_conf() {
  local desc="$1" branch="$2" cmd="$3" want="$4" has="$5" hasnt="$6" D OUT RC got; shift 6
  D=$(make_repo "$branch"); mkdir -p "$D/.ai"; printf 'PROTECTED_BRANCHES=^(trunk\n' > "$D/.ai/flight-rules.conf"
  OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" env "$@" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null); RC=$?
  if grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then got=deny; else got=allow; fi
  if [[ $RC -eq 0 && "$got" == "$want" ]] && { [[ -z "$has" ]] || grep -qF -- "$has" <<<"$OUT"; } \
     && { [[ -z "$hasnt" ]] || ! grep -qF -- "$hasnt" <<<"$OUT"; }; then
    PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %s (rc=%s, %s)\n%s\n' "$desc" "$RC" "$got" "$OUT"
  fi
  rm -rf "$D"
}
broken_conf "broken pattern in the conf: denied, naming the pattern" feature/x 'git commit -m x' \
  deny 'PROTECTED_BRANCHES (^(trunk) is not a pattern bash can read, so every branch, \"feature/x\" included,' ''
# Off in the env wins over a broken conf. The case it replaces set off with no broken
# pattern anywhere, so it pinned nothing about the two together (group A fix review, F4).
broken_conf "broken pattern in the conf, off in the env: allowed" trunk 'git commit -m x' \
  allow '' '' FLIGHT_RULES_PROTECTED_BRANCHES=off
# A branch create on feature/x is refused only because the broken pattern matches every
# branch — a valid one would allow it — so the pattern's block names the cause. The
# worktree block offered `off` and never named the pattern (group A fix review, F3;
# round 3, V1).
broken_conf "broken pattern, checkout -b: denied, naming the pattern" feature/x 'git checkout -b feature/y' \
  deny 'PROTECTED_BRANCHES (^(trunk) is not a pattern bash can read' 'PROTECTED_BRANCHES=off'
# A mirror push is refused under any pattern, so it keeps its own block: the pattern's
# said fixing it would let it through (group A fix review round 2, F7).
broken_conf "broken pattern, mirror push: the protected-branch block" feature/x 'git push --mirror origin' \
  deny 'protected branch \"every branch (--mirror)\"' 'is not a pattern bash can read'
D=$(make_repo main)
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" FLIGHT_RULES_WORKTREE_DIR='.worktrees' \
      bash "$HOOK" <<<'{"tool_input":{"command":"git rm f.txt"}}' 2>/dev/null)
if grep -q 'git worktree add .worktrees/' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ custom worktree dir appears in the suggested command\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ custom worktree dir missing from the block message\n'
fi
rm -rf "$D"

echo "Config file (.ai/flight-rules.conf) — the tool-agnostic home:"
# conf_check <desc> <expect> <branch> <command> <conf-contents>
conf_check() {
  local desc="$1" expect="$2" branch="$3" cmd="$4" conf="$5"
  local dir out got rc
  dir=$(make_repo "$branch")
  mkdir -p "$dir/.ai"; printf '%s\n' "$conf" > "$dir/.ai/flight-rules.conf"
  out=$(cd "$dir" && CLAUDE_PROJECT_DIR="$dir" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null); rc=$?
  if [[ $rc -ne 0 ]]; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: the hook exited %s — a verdict was never reached\n' "$desc" "$rc"
    rm -rf "$dir"; return
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [[ "$got" == "$expect" ]]; then
    PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"
  fi
  rm -rf "$dir"
}

# An inline comment on a value is ordinary config-file writing, not evasion. Until
# 2026-09-11 the three `(.*)` parsers kept it, so the value became a regex that matches
# nothing and the layer reading it silently stopped enforcing — while flight-rules-doctor.sh, which
# DOES strip comments, printed ✅ for the same line. Four parsers, three behaviours.
conf_check "trailing comment on the value"   deny  main 'git rm f' \
      'PROTECTED_BRANCHES=^main$   # trunk-based, no dev'
conf_check "comment with a single space"     deny  main 'git rm f' \
      'PROTECTED_BRANCHES=^main$ # why'
conf_check "comment after a quoted value"    deny  main 'git rm f' \
      'PROTECTED_BRANCHES="^main$"  # quoted and commented'
conf_check "comment on a custom set"         deny  integration 'git rm f' \
      'PROTECTED_BRANCHES=^integration$  # our trunk'
conf_check "…and that set still excludes others" allow main 'git rm f' \
      'PROTECTED_BRANCHES=^integration$  # our trunk'
# A `#` that is NOT preceded by whitespace belongs to the value.
conf_check "hash inside the value is kept"   deny  'feature#1' 'git rm f' \
      'PROTECTED_BRANCHES=^feature#1$'
conf_check "off with a trailing comment"     allow main 'git rm f' \
      'PROTECTED_BRANCHES=off   # this project works on main'

conf_check "conf protects a custom branch"  deny  integration 'git rm f' \
  'PROTECTED_BRANCHES=^integration$'
conf_check "conf narrows: dev now allowed"  allow dev 'git rm f' \
  'PROTECTED_BRANCHES=^integration$'
conf_check "comments and blanks ignored"    deny  integration 'git rm f' \
  '# flight-rules config

PROTECTED_BRANCHES=^integration$'
conf_check "quoted value is unwrapped"      deny  integration 'git rm f' \
  'PROTECTED_BRANCHES="^integration$"'
conf_check "spaces around = tolerated"      deny  integration 'git rm f' \
  'PROTECTED_BRANCHES = ^integration$'
conf_check "absent key falls back to default" deny main 'git rm f' \
  'WORKTREE_DIR=.worktrees'
# The conf file is parsed, never sourced. If someone "simplifies" read_conf to
# `source`, this repo-supplied command would run and create the marker file.
# Expect ALLOW: read as data, the value is the literal string "$(touch ...)^main$",
# which is a regex that simply does not match the branch "main". That inertness is
# the point — the real assertion is the marker check below.
MARKER=$(cd "$(mktemp -d)" && pwd -P)/pwned
conf_check "substitution in conf stays inert" allow main 'git rm f' \
  "PROTECTED_BRANCHES=\$(touch $MARKER)^main\$"
if [[ -e "$MARKER" ]]; then
  FAIL=$((FAIL+1)); printf '  ❌ conf file was EXECUTED — read_conf must not source\n'
else
  PASS=$((PASS+1)); printf '  ✅ no code execution from conf file\n'
fi

echo "Escape hatch — the plugin now activates this guard, so opting out must work:"
check "off: commit on main allowed"      allow main 'git commit -m x' \
      FLIGHT_RULES_PROTECTED_BRANCHES=off
check "off: git rm on main allowed"      allow main 'git rm f.txt' \
      FLIGHT_RULES_PROTECTED_BRANCHES=off
check "none: synonym for off"            allow main 'git rm f.txt' \
      FLIGHT_RULES_PROTECTED_BRANCHES=none
conf_check "off via the conf file"       allow main 'git rm f' 'PROTECTED_BRANCHES=off'
# Opting out of the branch policy must NOT disable the secret scan — leaking a key
# is not a workflow preference.
D=$(make_repo main)
printf 'AWS_KEY = "%s"\n' "$AKIA" > "$D/leak.py"
git -C "$D" add leak.py >/dev/null 2>&1
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" FLIGHT_RULES_PROTECTED_BRANCHES=off \
      bash "$HOOK" <<<'{"tool_input":{"command":"git commit -m x"}}' 2>/dev/null)
if grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ secret scan still fires when the guard is off\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ secret scan was disabled by PROTECTED_BRANCHES=off\n'
fi
rm -rf "$D"
# The block message must name the opt-out, or a project that never wanted the
# worktree workflow has no way to discover it short of reading hooks/README.md.
D=$(make_repo main)
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" \
      bash "$HOOK" <<<'{"tool_input":{"command":"git commit -m x"}}' 2>/dev/null)
if grep -q 'PROTECTED_BRANCHES=off' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ block message names PROTECTED_BRANCHES=off\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ block message does not name PROTECTED_BRANCHES=off\n'
fi
rm -rf "$D"

echo "Precedence — environment beats the conf file:"
D=$(make_repo dev)
mkdir -p "$D/.ai"; echo 'PROTECTED_BRANCHES=^nothing$' > "$D/.ai/flight-rules.conf"
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" FLIGHT_RULES_PROTECTED_BRANCHES='^dev$' \
      bash "$HOOK" <<<'{"tool_input":{"command":"git rm f"}}' 2>/dev/null)
if grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ env overrides conf\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ env did not override conf\n'
fi
rm -rf "$D"

echo "Global git options must not hide the verb from the guard:"
# Regression: the commit check was a substring match for "git commit", so anything
# between `git` and `commit` — `-C <dir>`, `-c key=val` — bypassed the branch policy.
check "git -C <dir> commit"              deny  main 'git -C . commit -m x'
check "git -c key=val commit"            deny  main 'git -c user.name=t commit -m x'
check "git -C <dir> -c key=val commit"   deny  main 'git -C . -c user.name=t commit -m x'
check "git -c … commit on feature"       allow feature/x 'git -c user.name=t commit -m x'

echo "Force-push to a protected branch is blocked, wherever you stand:"
check "push --force origin main (from feature)" deny  feature/x 'git push --force origin main'
check "push -f origin main (from feature)"      deny  feature/x 'git push -f origin main'
check "push --force-with-lease origin main"     deny  feature/x 'git push --force-with-lease origin main'
check "push +feature:main refspec"              deny  feature/x 'git push origin +feature/x:main'
check "push -f with no refspec, on main"        deny  main      'git push -f'
check "push -f origin, on main"                 deny  main      'git push -f origin'
check "push --force to a feature branch"        allow feature/x 'git push --force origin feature/x'
check "plain push of main is not a force-push"  allow feature/x 'git push origin main'
check "push -u (not a force flag)"              allow feature/x 'git push -u origin feature/x'
check "push -f to a deploy remote named production" allow feature/x 'git push -f production'
check "push -f production feature/x"            allow feature/x 'git push -f production feature/x'

echo "Target directory — the last cd wins, and quotes are tolerated:"
# Regression: only the FIRST `cd` was honoured, so `cd /tmp && cd <repo> && git rm`
# judged /tmp. Since #61 a relative `cd` chains onto the one before it, which is what
# the shell does — so the case names the repo absolutely instead of as `cd .`.
D=$(make_repo main)
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
      <<<"$(jq -n --arg c "cd /tmp && cd $D && git rm f.txt" '{tool_input:{command:$c}}')" 2>/dev/null); RC=$?
if [[ $RC -ne 0 ]]; then FAIL=$((FAIL+1)); printf '  ❌ harness: the hook exited %s on the last-cd case\n' "$RC"
elif grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then PASS=$((PASS+1)); printf '  ✅ last cd wins\n'
else FAIL=$((FAIL+1)); printf '  ❌ last cd wins — expected deny, got allow\n'; fi
rm -rf "$D"
check "a relative cd chains onto the cd before it" allow main 'cd /tmp && cd . && git rm f.txt'
check "double-quoted cd path"            deny  main 'cd "." && git rm f.txt'
check "single-quoted cd path"            deny  main "cd '.' && git rm f.txt"

echo "Secret scan — staged content on a feature branch:"
# secret_check <desc> <expect> <file path> <content>
secret_check() {
  local desc="$1" expect="$2" path="$3" content="$4"
  local dir out got rc
  dir=$(make_repo feature/x)
  mkdir -p "$dir/$(dirname "$path")"
  printf '%s\n' "$content" > "$dir/$path"
  if ! git -C "$dir" add "$path" >/dev/null 2>&1; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: git add failed — nothing was staged to scan\n' "$desc"
    rm -rf "$dir"; return
  fi
  out=$(cd "$dir" && CLAUDE_PROJECT_DIR="$dir" bash "$HOOK" \
        <<<'{"tool_input":{"command":"git commit -m x"}}' 2>/dev/null); rc=$?
  if [[ $rc -ne 0 ]]; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: the hook exited %s — a verdict was never reached\n' "$desc" "$rc"
    rm -rf "$dir"; return
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [[ "$got" == "$expect" ]]; then
    PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"
  fi
  rm -rf "$dir"
}
# Regression: every pattern was anchored `^\+[^+].*`, demanding a character between
# the diff's "+" and the secret — a column-zero assignment was never matched.
secret_check "password at column zero"        deny  src/config.py 'password = "hunter2hunter2"'
secret_check "AWS key at column zero"         deny  src/config.py "$AKIA"
secret_check "indented password (control)"    deny  src/config.py '    password = "hunter2hunter2"'
secret_check "PASSWORD (case-insensitive)"    deny  src/config.py 'PASSWORD = "hunter2hunter2"'
secret_check "API_KEY"                        deny  src/config.py 'API_KEY = "abcdefghijklmnop"'
secret_check "token"                          deny  src/config.py 'token = "abcdefghijklmnop"'
secret_check "YAML password:"                 deny  config.yml   'password: "hunter2hunter2"'
secret_check "JSON \"password\":"             deny  config.json  '{"password": "hunter2hunter2"}'
secret_check "sk-ant-… key"                   deny  src/a.py 'k = "sk-ant-api03-Abc123Abc123Abc123Abc123Abc123Abc123-AA"'
secret_check "sk-proj-… key"                  deny  src/a.py 'k = "sk-proj-Abc123Abc123Abc123Abc123Abc123Abc123"'
secret_check "legacy sk-… key"                deny  src/a.py 'k = "sk-Abc123Abc123Abc123Abc123Abc123Abc123Abc123Abc12"'
secret_check "GitHub ghp_ token"              deny  src/a.py 'k = "ghp_Abc123Abc123Abc123Abc123Abc123Abc123"'
secret_check "GitHub fine-grained PAT"        deny  src/a.py 'k = "github_pat_11ABCDEFG0abcdefghijklmnopqrstuvwxyz"'
secret_check "Slack xoxb token"               deny  src/a.py 'k = "xoxb-123456789012-abcdefghijkl"'
secret_check "Google AIza key"                deny  src/a.py 'k = "AIzaSyAbc123Abc123Abc123Abc123Abc123Abc12"'
secret_check "OPENSSH private key"            deny  id_ed25519 '-----BEGIN OPENSSH PRIVATE KEY-----'
secret_check "EC private key"                 deny  key.pem    '-----BEGIN EC PRIVATE KEY-----'
secret_check "RSA private key (control)"      deny  key.pem    '-----BEGIN RSA PRIVATE KEY-----'
secret_check ".env staged"                    deny  .env       'X=1'
secret_check ".env.example is fine"           allow .env.example 'X='
secret_check "placeholder <your-password>"    allow src/config.py 'password = "<your-password-here>"'
secret_check "placeholder REDACTED"           allow src/config.py 'password = "REDACTED_VALUE"'
secret_check "env-var reference"              allow src/config.py 'password = "${DB_PASSWORD}"'
secret_check "short literal"                  allow src/config.py 'password = "short"'
secret_check "ordinary source"                allow src/app.py 'x = compute(y)'
# Test fixtures may hold literal passwords — every common naming convention.
secret_check "tests/ dir excluded"            allow tests/test_a.py 'password = "hunter2hunter2"'
secret_check "__tests__/ dir excluded"        allow src/__tests__/a.ts 'password = "hunter2hunter2"'
secret_check "test_*.py excluded"             allow test_auth.py 'password = "hunter2hunter2"'
secret_check "*_test.go excluded"             allow auth_test.go 'password = "hunter2hunter2"'
secret_check "*.test.ts excluded"             allow src/auth.test.ts 'password = "hunter2hunter2"'
secret_check "*.spec.js excluded"             allow src/auth.spec.js 'password = "hunter2hunter2"'
secret_check "conftest.py excluded"           allow conftest.py 'password = "hunter2hunter2"'
# …but a provider key is a leak wherever it sits.
secret_check "AWS key in a test file"         deny  tests/test_a.py "$AKIA"
# Post-merge review: names git quotes, documented .env templates, prose files, the
# allow trailer, and the extra placeholder words.
secret_check "non-ASCII filename is scanned"  deny  'src/cönfig.py' 'password = "hunter2hunter2"'
secret_check "filename with spaces scanned"   deny  'src/my config.py' 'password = "hunter2hunter2"'
secret_check ".env.sample is a template"      allow .env.sample   'DB_PASSWORD='
secret_check ".env.template is a template"    allow .env.template 'DB_PASSWORD='
secret_check ".env.dist is a template"        allow .env.dist     'DB_PASSWORD='
secret_check "docs/.env.md is a docs page"    allow docs/.env.md  '# The .env file'
secret_check ".env.local is still a leak"     deny  .env.local    'DB_PASSWORD=hunter2'
secret_check "docs prose example"             allow docs/setup.md 'secret = "your-secret-here-please"'
secret_check "locale string"                  allow locales/en.json '{"password": "Password must be 8 characters"}'
secret_check "README example"                 allow README.md 'api_key = "abcdefghijklmnop"'
secret_check "placeholder your-…"             allow src/config.py 'password = "your-password-goes"'
secret_check "placeholder …-here"             allow src/config.py 'password = "put-real-value-here"'
secret_check "flight-rules: allow trailer"    allow src/config.py 'password = "hunter2hunter2"  # flight-rules: allow'
secret_check "provider key in docs still caught" deny docs/setup.md "key: $AKIA"
secret_check "provider key in locale still caught" deny locales/en.json '{"k": "sk-ant-api03-Abc123Abc123Abc123Abc123Abc123Abc123"}'
# An added line whose own text begins "++ " is "+++ …" in the diff — a file header's
# shape, which the line filter dropped, so no pattern saw it (#77). Each of the six;
# the password literal is a control — its check already tracked the header.
secret_check "++ line: AWS key"               deny  src/a.py "++ $AKIA"
secret_check "++ line: sk-… key"              deny  src/a.py "++ $(printf 'sk-%s' ant-api03-Abc123Abc123Abc123Abc123Abc123Abc123-AA)"
secret_check "++ line: GitHub token"          deny  src/a.py "++ $(printf 'ghp_%s' Abc123Abc123Abc123Abc123Abc123Abc123)"
secret_check "++ line: Slack token"           deny  src/a.py "++ $(printf 'xox%s' b-123456789012-abcdefghijkl)"
secret_check "++ line: Google key"            deny  src/a.py "++ $(printf 'AIza%s' SyAbc123Abc123Abc123Abc123Abc123Abc12)"
secret_check "++ line: private key"           deny  key.pem  "++ $(printf -- '-----BEGIN %s PRIVATE KEY-----' RSA)"
secret_check "++ line: password literal"      deny  src/a.py "++ $(printf 'pass%s = "%s"' word hunter2hunter2)"

echo "The repo's own diff settings do not hide a staged key, and a .env leaving is not one entering:"
# scan_case <desc> <expect> <setup> [<command>] — <setup> runs in the fixture repo before
# the commit is judged, and must leave something staged; a setup that fails aborts the
# run. <command> is what the agent runs, `git commit -m x` by default.
# The first five were allowed until the scan read the diff with --no-color, --no-ext-diff,
# --no-textconv and --text: color.ui=always prefixed every added line with an escape
# code, so no pattern anchored on "+" matched (probed 2026-10-05 on dev at adbabc5).
scan_case() {
  local desc="$1" expect="$2" setup="$3" cmd="${4:-git commit -m x}" dir out got rc
  dir=$(make_repo feature/x)
  (cd "$dir" && eval "$setup") >/dev/null 2>&1 || die "setup failed for: $desc"
  [ -n "$(git -C "$dir" diff --cached --name-only)" ] || die "setup staged nothing for: $desc"
  out=$(cd "$dir" && CLAUDE_PROJECT_DIR="$dir" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null); rc=$?
  if [[ $rc -ne 0 ]]; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: the hook exited %s — a verdict was never reached\n' "$desc" "$rc"
    rm -rf "$dir"; return
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [[ "$got" == "$expect" ]]; then
    PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"
  fi
  rm -rf "$dir"
}
STAGE_KEY='printf "%s\n" "$AKIA" > k.txt && git add k.txt'
scan_case "color.ui=always"                  deny "git config color.ui always && $STAGE_KEY"
scan_case "color.diff=always"                deny "git config color.diff always && $STAGE_KEY"
scan_case "diff.external that prints nothing" deny "git config diff.external true && $STAGE_KEY"
scan_case "-diff attribute (binary)"         deny "echo '*.txt -diff' > .gitattributes && $STAGE_KEY"
scan_case "textconv that redacts"            deny "echo '*.txt diff=r' > .gitattributes && git config diff.r.textconv 'sed s/AKIA/XXXX/' && $STAGE_KEY"
# diff.relative cut the diff to the directory the commit ran from, so a key staged at the
# root passed a commit made from a subdirectory (/dg, 2026-10-05).
scan_case "diff.relative, commit from a subdirectory" deny "mkdir sub && echo s > sub/s && git config diff.relative true && $STAGE_KEY" 'cd sub && git commit -m x'
# The credential check passed root-relative names back as cwd-relative pathspecs, so from
# a subdirectory nothing matched and it never ran — with no config at all.
scan_case "a password at the root, commit from a subdirectory" deny "mkdir -p sub src && echo s > sub/s && printf 'password = \"hunter2hunter2\"\n' > src/config.py && git add src/config.py" 'cd sub && git commit -m x'
# A `-diff` attribute makes a large TEXT file look binary to git; the 1 MB limit is for
# real binaries only, so a lockfile marked -diff is still read.
scan_case "a key in a 2 MB text file marked -diff" deny "echo '*.lock -diff' > .gitattributes && for i in \$(seq 1 40000); do echo 'line of a large generated lockfile entry'; done > big.lock && printf '%s\\n' \"\$AKIA\" >> big.lock && git add .gitattributes big.lock"
# The credential check left binaries out; which files were binary was git's call, so a
# `-diff` or `binary` attribute on source files hid them from it (security review,
# 2026-10-12), then the content's — and one planted NUL did the same (#76). Nothing a
# file contains exempts it now; the exemptions are by name only.
scan_case "a password in source marked -diff" deny "mkdir -p src && echo '*.py -diff' > .gitattributes && printf 'password = \"hunter2hunter2\"\n' > src/config.py && git add .gitattributes src/config.py"
scan_case "a password in source marked binary" deny "mkdir -p src && echo '*.py binary' > .gitattributes && printf 'password = \"hunter2hunter2\"\n' > src/config.py && git add .gitattributes src/config.py"
scan_case "a password-shaped string in a real binary is reported too" deny "mkdir -p src && printf '\000\001password = \"hunter2hunter2\"\n' > src/blob.dat && git add src/blob.dat"
scan_case "a key inside a small binary"      deny "printf '\\000\\001%s\\000\\n' \"\$AKIA\" > k.dat && git add k.dat"
# The key's position crossed with a payload past 64 KB: the git hook committed a key with
# more than 64 KB of added text after it (/dg, 2026-10-08), and every large case here put
# the key last. A binary over 1 MB is not read by the guard, by design; the git hook is.
FILL="awk 'BEGIN { for (i = 0; i < 30000; i++) print \"line of a large generated lockfile entry\" }'"
scan_case "a key first in 1.2 MB of text"   deny "{ printf '%s\\n' \"\$AKIA\"; $FILL; } > big.txt && git add big.txt"
scan_case "a key mid-way in 1.2 MB of text" deny "{ $FILL; printf '%s\\n' \"\$AKIA\"; $FILL; } > big.txt && git add big.txt"
scan_case "a key last in 1.2 MB of text"    deny "{ $FILL; printf '%s\\n' \"\$AKIA\"; } > big.txt && git add big.txt"
scan_case "a key first in 2 MB marked -diff" deny "echo '*.lock -diff' > .gitattributes && { printf '%s\\n' \"\$AKIA\"; $FILL; $FILL; } > big.lock && git add .gitattributes big.lock"
scan_case "a key first in a 900 KB binary"  deny "{ printf '%s\\n' \"\$AKIA\"; head -c 921600 /dev/urandom; } > k.dat && git add k.dat"
# The credential-literal check reads its own diff of the non-test files; that one too.
scan_case "diff.external hiding a password"  deny "mkdir -p src && git config diff.external true && printf 'password = \"hunter2hunter2\"\n' > src/config.py && git add src/config.py"
# --text hands the scan a binary file's raw bytes. Under a UTF-8 locale macOS grep skips a
# line holding an invalid byte (Codex, /dg), and tr stops at the first one — "Illegal
# byte sequence" — so nothing after it was scanned at all.
LC_ALL=en_US.UTF-8 scan_case "a key after an invalid byte, UTF-8 locale" deny "echo '*.bin -diff' > .gitattributes && printf '\377\n%s\377\n' \"\$AKIA\" > k.bin && git add k.bin"
# Removing a .env is the one change let through, as in the git pre-commit hook: deleting
# or untracking it is how a leak is cleaned up, and was refused because the name list
# carried no --diff-filter. Editing one already tracked is still refused (owner's call,
# 2026-10-05): a password typed into it has no quotes for the literal check to catch.
TRACK_ENV='printf "X=1\n" > .env && git add .env && git commit -qm env'
scan_case "git rm of a tracked .env"         allow "$TRACK_ENV && git rm -q .env"
scan_case "untracking a .env (rm --cached)"  allow "$TRACK_ENV && git rm -q --cached .env"
scan_case "editing a tracked .env"           deny  "$TRACK_ENV && printf 'DB_PASSWORD=hunter2\n' >> .env && git add .env"
scan_case "renaming a .env away"             deny  "$TRACK_ENV && git mv .env config.txt"
scan_case "renaming a .env away, renames off" deny "$TRACK_ENV && git config diff.renames false && git mv .env config.txt"
scan_case "renaming a .env to a template"    deny  "$TRACK_ENV && git mv .env .env.example"
scan_case "…but a key written into it"       deny  "$TRACK_ENV && printf '%s\n' \"\$AKIA\" >> .env && git add .env"
scan_case "a .env renamed in"                deny  "printf 'X=1\n' > .env.example && git add .env.example && git commit -qm e && git mv .env.example .env"

echo "Concluding a merge, the scan reads the resolution, as the git pre-commit hook does (#101):"
# Against HEAD, the guard scanned every incoming commit, so it refused the commit #100's
# box prints to conclude a merge whose incoming key had been reviewed, while git's hook
# let it through (0.27.0 release review). MERGE_FROM: a conflicted merge of `other`,
# which carries a key, stopped and staged with the resolution of f.txt given after it.
MERGE_FROM='git checkout -qb other && printf "%s\n" "$AKIA" > k.txt && echo other > f.txt && git add . && git commit -qm other && git checkout -q feature/x && echo mine > f.txt && git commit -qam mine && { git merge other >/dev/null 2>&1; [ -f .git/MERGE_HEAD ]; } &&'
scan_case "a key on the incoming side is not the resolution's"   allow "$MERGE_FROM echo resolved > f.txt && git add f.txt"
scan_case "…a key written into the resolution is refused"         deny  "$MERGE_FROM printf 'resolved %s\n' \"\$AKIA\" > f.txt && git add f.txt"
scan_case "…with no AUTO_MERGE, merge-tree works the merge out"   allow "$MERGE_FROM echo resolved > f.txt && git add f.txt && rm -f .git/AUTO_MERGE"
scan_case "…and the resolution's key is still refused there"      deny  "$MERGE_FROM printf 'resolved %s\n' \"\$AKIA\" > f.txt && git add f.txt && rm -f .git/AUTO_MERGE"
scan_case "…an octopus with no AUTO_MERGE is read in full"        deny  "$MERGE_FROM echo resolved > f.txt && git add f.txt && rm -f .git/AUTO_MERGE && git rev-parse HEAD^ >> .git/MERGE_HEAD"
scan_case "…a tag named AUTO_MERGE is not git's merge"            deny  "$MERGE_FROM printf 'resolved %s\n' \"\$AKIA\" > f.txt && git add f.txt && rm -f .git/AUTO_MERGE && git tag AUTO_MERGE \"\$(git write-tree)\""
scan_case "a leftover MERGE_HEAD naming HEAD is an ordinary commit" deny "git rev-parse HEAD > .git/MERGE_HEAD && $STAGE_KEY"
# Unstaging a file mid-merge commits HEAD's copy and drops the incoming change, so the
# refusal must not say to; outside a merge it still does.
MD=$(make_repo feature/x)
(cd "$MD" && eval "$MERGE_FROM printf 'resolved %s\n' \"\$AKIA\" > f.txt && git add f.txt") >/dev/null 2>&1 || die "could not build the merge in $MD"
OUT=$(cd "$MD" && CLAUDE_PROJECT_DIR="$MD" bash "$HOOK" <<<'{"tool_input":{"command":"git commit --no-edit"}}' 2>/dev/null)
say_n() { if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); printf '  ✅ %s\n' "$3"; else FAIL=$((FAIL+1)); printf '  ❌ %s (got %s, want %s)\n' "$3" "$1" "$2"; fi; }
say_n "$(grep -c 'do not unstage' <<<"$OUT")" 1 "mid-merge, the refusal says not to unstage"
say_n "$(grep -c 'unstage and re-check' <<<"$OUT")" 0 "…and drops the advice to"
rm -rf "$MD"; MD=$(make_repo feature/x)
(cd "$MD" && eval "$STAGE_KEY") >/dev/null 2>&1 || die "could not stage a key in $MD"
OUT=$(cd "$MD" && CLAUDE_PROJECT_DIR="$MD" bash "$HOOK" <<<'{"tool_input":{"command":"git commit -m x"}}' 2>/dev/null)
say_n "$(grep -c 'unstage and re-check' <<<"$OUT")" 1 "outside a merge, it still says to unstage"
rm -rf "$MD"

echo "More ways to rewrite or discard a protected branch (post-merge review):"
check "checkout <rev> -- <path>"          deny  main 'git checkout HEAD -- f.txt'
check "checkout <branch> -- <path>"       deny  main 'git checkout other -- f.txt'
check "switch --discard-changes"          deny  main 'git switch --discard-changes main'
check "switch -f"                         deny  main 'git switch -f main'
check "reset --merge"                     deny  main 'git reset --merge'
check "rebase onto a feature"             deny  main 'git rebase feature/x'
check "rebase -i"                         deny  main 'git rebase -i HEAD~3'
check "stash drop"                        deny  main 'git stash drop'
check "stash clear"                       deny  main 'git stash clear'
check "rebase --abort is the way out"     allow main 'git rebase --abort'
check "rebase --continue"                 allow main 'git rebase --continue'
check "stash list / push are fine"        allow main 'git stash list && git stash push -m wip'
check "switch to a branch"                allow main 'git switch feature/x'
check "rebase on a feature branch"        allow feature/x 'git rebase main'

echo "Workflow rule 6 — branches are created as worktrees, on any branch:"
check "checkout -b on main"               deny  main      'git checkout -b feature/y'
# Narrowed 2026-09-14: rule 6 guards the MAIN checkout against feature work landing in
# it, which is a protected-branch condition. It was nominally universal but not actually
# enforced — a `git commit` in the same command elected `commit` and branch creation was
# never judged. Made consistent, universal cost 7 of 405 real commands; narrowed instead.
check "checkout -b on a feature branch"   allow feature/x 'git checkout -b feature/y'
check "…and still denied on a protected branch when a commit shares the command" \
                                          deny  main      'git commit -m x && git checkout -b feature/y'
check "checkout -B"                       deny  main      'git checkout -B feature/y'
check "checkout -q -b (option before)"    deny  main      'git checkout -q -b feature/y'
check "switch -c"                         deny  main      'git switch -c feature/y'
check "switch -C"                         deny  main      'git switch -C feature/y'
check "switch --create"                   deny  main      'git switch --create feature/y'
check "switch --force-create"             deny  main      'git switch --force-create feature/y'
check "cd && checkout -b"                 deny  main      'cd . && git checkout -b feature/y'
check "worktree add -b is the right way"  allow main      'git worktree add .ai/worktrees/y -b feature/y origin/main'
check "checkout <existing branch>"        allow main      'git checkout feature/x'
check "switch <existing branch>"          allow main      'git switch feature/x'
check "checkout -b with the guard off"    allow main      'git checkout -b feature/y' \
      FLIGHT_RULES_PROTECTED_BRANCHES=off
check "branch <name> (no switch) is not gated" allow main 'git branch feature/y'
D=$(make_repo main)
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" <<<'{"tool_input":{"command":"git checkout -b feature/y"}}' 2>/dev/null)
if grep -q 'git worktree add .ai/worktrees/<name> -b' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ block message shows the worktree command\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ block message lacks the worktree command\n'
fi
# A worktree directory with a space is quoted, so the route pastes as one path: printed
# bare, it split into two arguments (fix review, 2026-10-26).
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" FLIGHT_RULES_WORKTREE_DIR="my wt" bash "$HOOK" <<<'{"tool_input":{"command":"git checkout -b feature/y"}}' 2>/dev/null)
if grep -qF "git worktree add 'my wt'/<name> -b" <<<"$OUT" && grep -qF "cd 'my wt'/<name>" <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ …a worktree directory with a space is quoted to paste\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ …a worktree directory with a space is printed unquoted\n'
fi
rm -rf "$D"
# Another repo's branches are not ours to police (same scoping as the branch policy).
D=$(make_repo main); O=$(make_repo main)
OUT=$(cd "$O" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" <<<'{"tool_input":{"command":"git checkout -b feature/y"}}' 2>/dev/null); RC=$?
# An "allow" here is the ABSENCE of a deny, which is also what a hook that died
# produces. The exit status is what tells the two apart.
if [[ $RC -ne 0 ]]; then
  FAIL=$((FAIL+1)); printf '  ❌ harness: the hook exited %s — the sibling-repo case proved nothing\n' "$RC"
elif grep -q '"deny"' <<<"$OUT"; then
  FAIL=$((FAIL+1)); printf '  ❌ checkout -b in a sibling repo was denied\n'
else
  PASS=$((PASS+1)); printf '  ✅ checkout -b in a sibling repo is not our business\n'
fi
rm -rf "$D" "$O"

echo "Deleting or overwriting a protected branch on the remote:"
check "push --delete origin main"         deny  feature/x 'git push --delete origin main'
check "push -d origin main"               deny  feature/x 'git push -d origin main'
check "push origin :main (empty source)"  deny  feature/x 'git push origin :main'
check "push --mirror"                     deny  feature/x 'git push --mirror origin'
check "push --delete a feature branch"    allow feature/x 'git push --delete origin feature/old'
check "push origin main:main (no force)"  allow feature/x 'git push origin main:main'


echo "The branch policy applies inside this project's own worktrees:"
# Regression: the project-scoping compared `--show-toplevel` against
# CLAUDE_PROJECT_DIR, and a worktree's toplevel is $WORKTREE_DIR/<name> by
# construction — so the whole policy below switched itself off inside every
# worktree, which is where the workflow says all work happens. Probed 2026-09-10:
# force-push to main, remote deletion of main and `checkout -b` were all allowed
# from a worktree while being denied from the main checkout.
check_wt "force-push to main from a worktree"   deny  scratch feature/x 'git push --force origin main'
check_wt "remote-delete main from a worktree"   deny  scratch feature/x 'git push --delete origin main'
check_wt "empty-source push from a worktree"    deny  scratch feature/x 'git push origin :main'
check_wt "--mirror from a worktree"             deny  scratch feature/x 'git push --mirror origin'
check_wt "checkout -b from a worktree on a feature branch" allow scratch feature/x 'git checkout -b feature/y'
# A worktree checked out ON the protected branch: commits and destructive
# commands there are the plain case, and were allowed too.
check_wt "commit on main from a worktree"       deny  scratch main 'git commit -m x'
check_wt "reset --hard on main from a worktree" deny  scratch main 'git reset --hard HEAD~1'
# What the scoping is actually for must still hold: ordinary feature work in a
# worktree is allowed, and a sibling repo is still none of our business.
check_wt "commit on a feature branch in a worktree" allow scratch feature/x 'git commit -m x'
check_wt "push a feature branch from a worktree"    allow scratch feature/x 'git push --force origin feature/x'

D=$(make_repo main); O=$(make_repo main)
if ! git -C "$O" worktree add -q "$O/.ai/worktrees/x" -b feature/x >/dev/null 2>&1; then
  FAIL=$((FAIL+1)); printf '  ❌ harness: worktree add failed — the sibling-worktree case proved nothing\n'
fi
OUT=$(cd "$O/.ai/worktrees/x" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
      <<<'{"tool_input":{"command":"git push --force origin main"}}' 2>/dev/null); RC=$?
if [[ $RC -ne 0 ]]; then
  FAIL=$((FAIL+1)); printf '  ❌ harness: the hook exited %s — the sibling-worktree case proved nothing\n' "$RC"
elif grep -q '"deny"' <<<"$OUT"; then
  FAIL=$((FAIL+1)); printf '  ❌ a sibling repo'"'"'s worktree was policed as ours\n'
else
  PASS=$((PASS+1)); printf '  ✅ a sibling repo'"'"'s worktree is still not ours to police\n'
fi
git -C "$O" worktree remove --force "$O/.ai/worktrees/x" >/dev/null 2>&1
rm -rf "$D" "$O"

echo "A push names its target; the branch you stand on is only the fallback:"
# Regression: IS_PROTECTED was set from CURRENT_BRANCH for every action, so
# deleting a merged feature branch's remote ref — post-merge cleanup, which the
# workflow has you do FROM main — was blocked. Blocked a real cleanup 2026-09-10.
check "delete a feature ref from main"    allow main 'git push --delete origin docs/rules-draft'
check "delete a feature ref with -d"      allow main 'git push -d origin feature/old'
check "force-push a feature ref from main" allow main 'git push --force origin feature/old'
check "empty-source push of a feature ref" allow main 'git push origin :feature/old'
# The fallback still stands when the push names no ref of its own.
check "bare force-push from main"         deny  main 'git push --force'
check "bare force-push with -f"           deny  main 'git push -f'
check "force-push to main from main"      deny  main 'git push --force origin main'
check "--mirror from main names no ref"   deny  main 'git push --mirror origin'

echo "Deleting a protected branch locally is not cleanup:"
# Regression 2026-09-10: post-merge listed protected branches under "safe to delete"
# in the note the next session is told to act on, and every layer allowed the command.
# Forbidden 5 was deliberately scoped to the remote (a local ref is recoverable) —
# that reasoning stops holding once the tooling recommends the command.
check "branch -d a protected branch"     deny  feature/x 'git branch -d main'
check "branch -D a protected branch"     deny  feature/x 'git branch -D main'
check "branch --delete a protected"      deny  feature/x 'git branch --delete main'
check "branch -D with a custom set"      deny  feature/x 'git branch -D trunk' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^(trunk|qa)$'
check "branch -d qa with a custom set"   deny  feature/x 'git branch -d qa' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^(trunk|qa)$'
check "delete several, one protected"    deny  feature/x 'git branch -d feature/old main'
check "branch -d from the protected one" deny  main      'git branch -d main'
# ...without breaking the cleanup step the workflow actually prescribes
check "branch -d a feature branch"       allow main      'git branch -d feature/old'
check "branch -D a feature branch"       allow main      'git branch -D feature/old'
check "branch -d two feature branches"   allow main      'git branch -d feature/a feature/b'
check "listing branches"                 allow main      'git branch'
check "listing merged branches"          allow main      'git branch --merged main'
check "creating a branch (not a delete)" allow main      'git branch feature/new'
check "renaming is not deleting"         allow main      'git branch -m old new'
# `-r` deletes remote-TRACKING refs — a local cache, not a branch.
check "branch -dr origin/main (cache)"   allow main      'git branch -dr origin/main'
check "branch -d -r origin/main"         allow main      'git branch -d -r origin/main'
check "guard off lets deletion through"  allow feature/x 'git branch -D main' \
      FLIGHT_RULES_PROTECTED_BRANCHES=off
# The block must name the branch it saved, not the one you are standing on.
D=$(make_repo feature/x)
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
      <<<'{"tool_input":{"command":"git branch -D main"}}' 2>/dev/null)
if grep -qE 'protected branch [\\"]*main' <<<"$OUT" \
   && grep -q 'Leave it alone' <<<"$OUT" \
   && ! grep -q 'Create a feature worktree instead' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ the block names the deleted branch, and does not tell you to make a worktree\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ the block is wrong for a deletion\n'
fi
rm -rf "$D"
# The worktree the blocks suggest goes through /feature-start first: a raw worktree add
# skips its open-branch count, the only gate on it (0.27.0 release review).
for c in 'git checkout -b feature/y|main|checkout -b on main' 'git commit -m x|main|a commit on main'; do
  D=$(make_repo "$(cut -d'|' -f2 <<<"$c")")
  OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
        <<<"$(jq -n --arg c "$(cut -d'|' -f1 <<<"$c")" '{tool_input:{command:$c}}')" 2>/dev/null)
  if grep -q '"permissionDecision": *"deny"' <<<"$OUT" && grep -q '/feature-start' <<<"$OUT" && grep -q 'open-branch limit\|OPEN_BRANCH_LIMIT' <<<"$OUT" \
     && grep -q 'raw worktree add skips\|by hand, which skips' <<<"$OUT" \
     && grep -q 'worktree add .* origin/<integration-branch>' <<<"$OUT"; then
    PASS=$((PASS+1)); printf '  ✅ %s: the block points at /feature-start and its branch count, and labels the raw add as skipping it, based on origin/<integration-branch>\n' "$(cut -d'|' -f3 <<<"$c")"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %s: the block does not point at /feature-start and its branch count\n' "$(cut -d'|' -f3 <<<"$c")"
  fi
  rm -rf "$D"
done

echo "Target parsing is per simple command, not per command STRING:"
# Both directions were live and both are reproduced here (2026-09-10).
#
# FALSE NEGATIVE — a bypass. The parser found the git verb with a greedy `.*`, so it
# saw only the LAST occurrence and a protected target in an earlier command escaped.
check "delete main, then delete a feature"  deny  feature/x 'git branch -d main && git branch -d feature/x'
check "delete main, then any git command"   deny  feature/x 'git branch -D main && git branch --list'
check "force-push main, then a feature"     deny  feature/x 'git push --force origin main && git push --force origin feature/x'
check "force-push main, then an echo"       deny  feature/x 'git push --force origin main && echo done'
check "delete main on the first line"       deny  feature/x 'git branch -D main
git status'
check "delete main inside a subshell"       deny  feature/x '(git branch -D main) && git status'
check "delete main after a pipe"            deny  feature/x 'git status | cat; git branch -D main'
#
# FALSE POSITIVE — the parser read past the end of the command it matched, so a word
# in a LATER command became a "target". This blocked ordinary post-merge cleanup.
check "delete a feature, then echo main"    allow main 'git branch -d feature/old
echo "=== main now ==="'
check "delete a feature, then log main"     allow main 'git branch -d feature/old && git log --oneline main -1'
check "delete a feature, ; then the word"   allow main 'git branch -d feature/old ; echo main'
check "push a feature, then echo main"      allow main 'git push --force origin feature/x && echo main'
check "worktree remove, then delete branch" allow main 'git worktree remove .ai/worktrees/x && git branch -d fix/x'
#
# The single-command cases must keep working — a bare command is one segment with
# nothing after it, and an earlier draft of the segment splitter dropped exactly that.
check "delete main alone"                   deny  feature/x 'git branch -d main'
check "force-push main alone"               deny  feature/x 'git push --force origin main'
check "delete a feature alone"              allow main      'git branch -d feature/old'
check "push a feature alone"                allow main      'git push --force origin feature/x'

echo "Shape coverage — every wrapper crossed with every dangerous core:"
# The cases above test each wrapper against ONE core and each core against ONE wrapper.
# Every guard bug found on 2026-09-10 lived in a combination neither axis covered:
#   - `git branch -d main && git branch -d feature/x` — a bypass; the parser's greedy
#     match saw only the last command (#30).
#   - `git branch -d feature/old` + a following `echo "=== main now ==="` — a false
#     positive that blocked real cleanup (#30).
#   - a bare `git branch -d main` broke and no case noticed, because every case covering
#     it was written single-line, which is the shape the bug hid in (#30, caught by hand).
# So the cross product is generated rather than enumerated. The invariant is simple:
# WRAPPING OR COMPOSING A COMMAND MUST NOT CHANGE THE VERDICT ON ITS DANGEROUS PART.
#
# The repos are built once and reused: the guard is a pure decision over (cwd, command),
# and 150+ fresh clones would dominate the suite's runtime for no extra coverage.
GEN_MAIN=$(make_repo main)
GEN_FEAT=$(make_repo feature/x)
# A sibling repo that some wrappers name with `git -C` or `cd`: the segment that names it
# is aimed there, and must not drag the verdict on the OTHER segments with it (#61).
GEN_OTHER=$(make_repo feature/elsewhere)

gen_check() {   # <expect: deny|allow> <main|feat> <wrapper-name> <command>
  local expect="$1" where="$2" wname="$3" cmd="$4" dir out got rc
  [ "$where" = main ] && dir="$GEN_MAIN" || dir="$GEN_FEAT"
  out=$(cd "$dir" && CLAUDE_PROJECT_DIR="$dir" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null); rc=$?
  # "allow" is the absence of a deny, and a hook that never ran produces exactly that.
  # These loops print one ✅ for hundreds of cases, so a silent vacuous pass is invisible.
  if [ $rc -ne 0 ]; then
    FAIL=$((FAIL+1))
    printf '  ❌ [%s] %s\n     %s\n     harness: the hook exited %s — no verdict\n' "$where" "$wname" "$cmd" "$rc"
    return
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    printf '  ❌ [%s] %s\n     %s\n     expected %s, got %s\n' "$where" "$wname" "$cmd" "$expect" "$got"
  fi
}

# Wrapper names and their printf templates, index-aligned. %s is the core.
# Trimmed 2026-09-11. `brace-group`, `if-then`, `cmd-subst` and `for-loop` all asserted
# the same property as `subshell` — that a command terminated by `)` or `;` is still
# matched — which was 4 x 18 cases for one assertion. `semi-echo` duplicated `and-echo`.
# The budget went to PREFIX_FMT below, an axis that had no coverage at all and where two
# criticals were living.
# `brace-group` is NOT redundant with `subshell`: subshell asserts `)` as the command
# terminator, brace-group asserts `;`. They are different characters in `E`. A mutant
# hook with `;` deleted from E passes a suite without brace-group and fails 18 cases with
# it — proven, not assumed. `if-then`, `for-loop`, `cmd-subst` and `semi-echo` caught
# nothing the survivors do not.
# The three RETARGETING wrappers (#61, probed 2026-09-17 on dev at c3a708e): a `git -C
# <other-repo>` on a harmless segment, before or after the core, and a `cd <other-repo>`
# AFTER it. The target used to be resolved once per command — the last `cd` anywhere,
# else the first `git -C` anywhere — so each of these judged the core against the other
# repo's branch and ALLOWED a commit on a protected branch. An assistant only has to
# inspect another worktree and commit in the same line. `cd` must only affect the
# segments after it, and `-C` only its own segment.
# The two SUBSHELL-cd wrappers (#70, probed 2026-10-05 on dev at 85df164): a `cd` inside
# `( … )` or `$( … )` ends at the `)` in the shell, but persisted for the guard, so the
# core was judged in the other repo — and allowed. `(cd sub && make) && git commit` is
# the everyday shape.
WRAP_NAME=( bare subshell brace-group cd-prefix and-echo echo-and pipe newline-after-main
            other-C-before other-C-after cd-other-after subshell-cd-other cmd-subst-cd-other )
WRAP_FMT=(  '%s'
            '(%s)'
            '{ %s; }'
            'cd . && %s'
            '%s && echo done'
            'echo start && %s'
            '%s | cat'
            '%s
echo "=== main now ==="'
            "git -C $GEN_OTHER status && %s"
            "%s && git -C $GEN_OTHER status"
            "%s && cd $GEN_OTHER"
            "(cd $GEN_OTHER && true) && %s"
            "x=\$(cd $GEN_OTHER && pwd) && %s" )

# The GIT-INVOCATION PREFIX axis. Everything between the word `git` and its verb.
# `NORM` normalised away only `-C <dir>` and `-c key=val`, so every other global option
# carried the verb past every matcher: `git --no-pager commit` on a protected branch was
# ALLOWED, as were `--no-pager` forms of push --force, branch -D, checkout -b and
# reset --hard. Measured 2026-09-11.
#
# The unresolvable-target forms are here too. `cd "$(git rev-parse --show-toplevel)"`
# and `cd "$VAR"` leave `git -C "$WORK_DIR"` unable to resolve a repo, which emptied
# both the branch AND the staged diff — so the SECRET SCAN was skipped as well. The
# repo's own docs and the guard's own deny message tell an agent to write commands in
# exactly those shapes.
# Index-aligned. Includes the two spellings of a value-taking option, and three flags
# that are NOT in any list in the hook — they are there to prove the generic
# dash-leading rule works rather than a hand-written enumeration.
PREFIX_NAME=( no-pager P-flag git-dir-eq git-dir-space literal-pathspecs
              no-optional-locks bare no-advice no-lazy-fetch attr-source )
PREFIX_FMT=(  'git --no-pager %s'
              'git -P %s'
              'git --git-dir=.git %s'
              'git --git-dir .git %s'
              'git --literal-pathspecs %s'
              'git --no-optional-locks %s'
              'git --bare %s'
              'git --no-advice %s'
              'git --no-lazy-fetch %s'
              'git --attr-source=HEAD %s' )

# Denied on a protected branch, whatever shape they arrive in.
DANGER_MAIN=( 'git commit -m x'
              # Moved from DANGER_ANY on 2026-09-14. Branch creation is now judged on the
              # branch you stand on, like a commit — see the narrowing note in the guard.
              'git checkout -b feature/y'
              'git rm f.txt'
              'git reset --hard HEAD~1'
              'git clean -fd'
              'git restore f.txt'
              'git restore --staged -W f.txt'
              'git stash drop'
              'git stash clear'
              'git rebase'
              'git switch -f'
              'git checkout --' )

# Denied from ANY branch, because they name the protected branch themselves.
DANGER_ANY=( 'git branch -D main'
             'git push --force origin main'
             'git push --mirror' )

# Allowed everywhere — these must survive every wrapper, including the one whose
# suffix contains the word "main".
SAFE=( 'git status --short'
       'git log --oneline -5'
       'echo hello'
       'git branch --list' )

j=0
while [ $j -lt ${#PREFIX_NAME[@]} ]; do
  pfmt="${PREFIX_FMT[$j]}"; pname="${PREFIX_NAME[$j]}"
  for core in "${DANGER_MAIN[@]}"; do
    gen_check deny  main "prefix:$pname" "$(printf "$pfmt" "${core#git }")"
  done
  for core in "${DANGER_ANY[@]}"; do
    gen_check deny  feat "prefix:$pname" "$(printf "$pfmt" "${core#git }")"
  done
  for core in "${SAFE[@]}"; do
    case "$core" in git\ *) gen_check allow main "prefix:$pname" "$(printf "$pfmt" "${core#git }")" ;; esac
  done
  j=$((j+1))
done
_git_safe=0; for core in "${SAFE[@]}"; do case "$core" in git\ *) _git_safe=$((_git_safe+1)) ;; esac; done
printf '  ✅ %s git-invocation-prefix combinations\n' \
  "$(( ${#PREFIX_NAME[@]} * (${#DANGER_MAIN[@]} + ${#DANGER_ANY[@]} + _git_safe) ))"

i=0
while [ $i -lt ${#WRAP_NAME[@]} ]; do
  fmt="${WRAP_FMT[$i]}"; wname="${WRAP_NAME[$i]}"
  for core in "${DANGER_MAIN[@]}"; do
    gen_check deny  main "$wname" "$(printf "$fmt" "$core")"
  done
  for core in "${DANGER_ANY[@]}"; do
    gen_check deny  feat "$wname" "$(printf "$fmt" "$core")"
  done
  for core in "${SAFE[@]}"; do
    gen_check allow main "$wname" "$(printf "$fmt" "$core")"
  done
  i=$((i+1))
done
printf '  ✅ %s wrapper × core combinations\n' "$(( ${#WRAP_NAME[@]} * (${#DANGER_MAIN[@]} + ${#DANGER_ANY[@]} + ${#SAFE[@]}) ))"

echo "A merge in progress waives the commit, and nothing else in the same command:"
# Committing the merge is the whole point of standing on the branch, so that refusal is
# waived. The waiver used to be applied to the COMMAND after the scan had already stopped
# at the first refused segment, so anything after it was never judged — found by review
# 2026-09-14, and it had no coverage at all, which is why it had to be reasoned rather
# than run. Each case pairs the waived thing with a thing that must stay refused.
MG=$(make_repo main)
printf '%s' "$(git -C "$MG" rev-parse HEAD)" > "$MG/.git/MERGE_HEAD"
mg() {   # mg <expect> <desc> <command>
  local expect="$1" desc="$2" cmd="$3" out rc got
  out=$(cd "$MG" && CLAUDE_PROJECT_DIR="$MG" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null); rc=$?
  if [[ $rc -ne 0 ]]; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: the hook exited %s\n' "$desc" "$rc"; return
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [[ "$got" == "$expect" ]]; then PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"; fi
}
mg allow "mid-merge: the merge commit itself is waived"        'git commit -m "merge feature/x"'
mg deny  "mid-merge: branch creation is not waivable"          'git checkout -b feature/y'
mg deny  "mid-merge: the waived commit does not carry a branch creation with it" \
         'git commit -m "merge feature/x" && git checkout -b feature/y'
mg deny  "mid-merge: nor a forced push at a protected branch" \
         'git commit -m "merge feature/x" && git push --force origin main'
mg deny  "mid-merge: nor a local delete of a protected branch" \
         'git commit -m "merge feature/x" && git branch -D main'
rm -rf "$MG"

echo "…and the merge is the one in the -C target, not in the hook's own cwd (#98):"
# `rev-parse --git-dir` printed `.git` relative to the -C target, and the test resolved
# it from the cwd: from a linked worktree (where .git is a file) a merge being finished
# in the main checkout was refused, and from a repo mid-merge a direct commit to another
# repo's protected branch was waived. Each case runs with cwd ≠ the target.
mgc() {   # mgc <expect> <desc> <cwd> <project dir> <command>
  local expect="$1" desc="$2" cwd="$3" proj="$4" cmd="$5" out rc got
  out=$(cd "$cwd" && CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null); rc=$?
  if [[ $rc -ne 0 ]]; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: the hook exited %s\n' "$desc" "$rc"; return
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [[ "$got" == "$expect" ]]; then PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"; fi
}
MR=$(make_repo main)
git -C "$MR" worktree add -q "$MR/.ai/worktrees/x" -b feature/x >/dev/null 2>&1 \
  || die "could not add a worktree to $MR"
printf '%s' "$(git -C "$MR" rev-parse HEAD)" > "$MR/.git/MERGE_HEAD"
mgc allow "from a worktree, finishing the main checkout's merge is waived" \
    "$MR/.ai/worktrees/x" "$MR" "git -C $MR commit --no-edit"
# A linked worktree keeps its MERGE_HEAD in its own gitdir (.git/worktrees/<name>), so
# the main checkout's .git is the wrong place to look for it, from either side.
git -C "$MR" worktree add -q "$MR/.ai/worktrees/d" -b dev >/dev/null 2>&1 \
  || die "could not add a dev worktree to $MR"
mgc deny  "from the main checkout, a merge there does not waive a commit in a worktree on dev" \
    "$MR" "$MR" "git -C $MR/.ai/worktrees/d commit -m x"
printf '%s' "$(git -C "$MR" rev-parse HEAD)" > "$(git -C "$MR/.ai/worktrees/d" rev-parse --absolute-git-dir)/MERGE_HEAD"
mgc allow "from the main checkout, finishing a merge in a worktree on dev is waived" \
    "$MR" "$MR" "git -C $MR/.ai/worktrees/d commit --no-edit"
NM=$(make_repo main)
# git -C walks a path as the kernel does: lnk/.. is the parent of where lnk leads, not
# the cwd. The guard already judged this as git does; pinned when install.sh's plain
# cd was found to read lnk/.. by name (second fix review).
LP=$(make_repo main); LQ=$(make_repo feature/q); mkdir -p "$LP/sub"
ln -s "$LP/sub" "$LQ/lnk" || die "could not link $LQ/lnk to $LP/sub"
[ "$(git -C "$LQ/lnk/.." branch --show-current)" = main ] || die "git -C lnk/.. did not reach $LP"
mgc deny  "git -C through a link and ..: judged where git goes, the project's main" \
    "$LQ" "$LP" "git -C lnk/.. commit -m x"
rm -rf "$LP" "$LQ"
mgc deny  "a merge in the cwd's repo does not waive a commit to another repo's main" \
    "$MR" "$NM" "git -C $NM commit -m x"
rm -rf "$MR" "$NM"

echo "…and the project is found as git finds it, whatever the shell's cd settings (third fix review):"
# The project dir is the harness's spelling. Through a symlink to a subdirectory, git
# answers `../.git` from where the link leads, and plain cd applied it to the link's own
# parent: here another repo, so the guard took the project for that one and allowed a
# commit on main.
LB=$(make_repo main); LA=$(make_repo feature/a); mkdir -p "$LB/sub"
ln -s "$LB/sub" "$LA/proj" || die "could not link $LA/proj to $LB/sub"
[ "$(git -C "$LA/proj" rev-parse --git-common-dir)" = "../.git" ] || die "git did not answer ../.git from the linked subdirectory: the case below tests nothing"
mgc deny  "project dir a symlinked subdirectory whose link sits in another repo: a commit on main is refused" \
    "$LA/proj" "$LA/proj" "git commit -m x"
rm -rf "$LA" "$LB"
# An exported CDPATH holding `.` made `cd .git` print where it went, so the comparison
# never matched and the branch policy was off — for a worktree on dev committed to from
# the main checkout, among others.
MR=$(make_repo main)
git -C "$MR" worktree add -q "$MR/.ai/worktrees/d" -b dev >/dev/null 2>&1 || die "could not add a dev worktree to $MR"
CDPATH=.:/usr mgc deny "CDPATH=.:/usr exported: a commit in a worktree on dev is still refused" \
    "$MR" "$MR" "git -C $MR/.ai/worktrees/d commit -m x"
# …and with the project dir a subdirectory of its repo, committing on main from the top:
# the target's `.git` is the relative answer CDPATH bent. The case before this one, with
# target_root == the project dir, short-circuited before the compare and could not fail
# (fourth fix review).
mkdir -p "$MR/sub"
CDPATH=.:/usr mgc deny "…and a commit on main, the project dir a subdirectory of the checkout" \
    "$MR" "$MR/sub" "git commit -m x"
rm -rf "$MR"

echo "…and a harmless command is not made dangerous by its neighbour:"
# The mirror of the section below, and the direction that had no coverage. The target
# parsers have run per SEGMENT since 2026-09-10, for the reason written above them; the
# CLASSIFIERS matched the whole string, so a flag belonging to one command was read as
# another's. Measured 2026-09-13: an ordinary push of `dev` was refused as a remote
# branch DELETION because `tr -d` appeared later in the pipeline — which made the
# two-branch workflow unusable, `dev` being protected but not PR-only and therefore
# meant to move by local merge and push.
check "a -d elsewhere is not a push --delete"  allow feature/x "git push origin main && wc -l | tr -d ' '"
check "a -f elsewhere is not a clean -f"       allow main      "git clean -n && rm -f /tmp/nothing"
check "a -f elsewhere is not a switch -f"      allow main      "git switch feature/x && chmod -f 644 f.txt"
check "a --hard elsewhere is not a reset"      allow main      "git reset HEAD~1 --soft && echo --hard"
# Each of those exonerates a verb; the real form of the same verb must not have moved.
check "push --delete origin main still denied" deny  feature/x "git push --delete origin main"
check "git clean -f still denied"              deny  main      "git clean -fd"
check "git switch -f still denied"             deny  main      "git switch -f main"
check "git reset --hard still denied"          deny  main      "git reset --hard HEAD~1"

echo "Composition — a dangerous command is not laundered by a harmless neighbour:"
# Order matters in both directions: the greedy parser saw only the LAST git verb, so a
# protected target in the FIRST command escaped entirely.
for pair in "git branch --list|git branch -D main" \
            "git branch -D main|git branch --list" \
            "git status|git push --force origin main" \
            "git push --force origin main|git status" \
            "git push --force origin feature/x|git push --force origin main" \
            "git push --force origin main|git push --force origin feature/x" \
            "git branch -d feature/old|git branch -D main" \
            "git branch -D main|git branch -d feature/old"; do
  a="${pair%%|*}"; b="${pair##*|}"
  gen_check deny feat "composed" "$a && $b"
  gen_check deny feat "composed-semi" "$a ; $b"
done
printf '  ✅ 16 composed pairs, both orders\n'

echo "Composition — two harmless commands stay harmless:"
for pair in "git status|echo main" \
            "git branch -d feature/old|echo \"=== main now ===\"" \
            "git branch -d feature/old|git log --oneline main -1" \
            "git push --force origin feature/x|echo main" \
            "git worktree remove .ai/worktrees/x|git branch -d fix/x"; do
  a="${pair%%|*}"; b="${pair##*|}"
  gen_check allow main "harmless-pair" "$a && $b"
done
printf '  ✅ 5 harmless pairs\n'

rm -rf "$GEN_MAIN" "$GEN_FEAT" "$GEN_OTHER"

echo "The target is resolved per segment, not per command (#61):"
# The product above proves a harmless segment aimed elsewhere cannot clear the core. The
# cases here pin the other half of the rule: a segment GENUINELY aimed at another repo is
# still not ours to judge, a `-C` on the segment itself beats an earlier `cd`, and the
# secret scan reads the repo the COMMIT is aimed at — which the same bug also retargeted:
# `git -C other status && git commit` from a repo with a staged key scanned `other`.
D=$(make_repo dev); O=$(make_repo feature/elsewhere)
seg() {   # seg <expect> <desc> <command>   — run from $D with the project scoped to $D
  local expect="$1" desc="$2" cmd="$3" out rc got
  out=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null); rc=$?
  if [[ $rc -ne 0 ]]; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: the hook exited %s\n' "$desc" "$rc"; return
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [[ "$got" == "$expect" ]]; then PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"; fi
}
seg deny  "the #61 shape: -C elsewhere on a status, then a bare commit"   "git -C $O status && git commit -m x"
seg deny  "cd elsewhere AFTER the commit does not retarget it"            "git commit -m x && cd $O"
seg deny  "-C on the commit segment beats an earlier cd elsewhere"        "cd $O && git -C $D commit -m x"
seg deny  "cd elsewhere, then cd back, then commit"                       "cd $O && git status && cd $D && git commit -m x"
seg allow "cd elsewhere, then commit: aimed there, not ours"              "cd $O && git commit -m x"
seg allow "-C elsewhere on the commit itself: aimed there, not ours"      "git -C $O commit -m x"
seg allow "-C elsewhere on a status alone is just a status"               "git -C $O status"
seg allow "a relative -C after a cd is relative to the cd, not the cwd"  "cd $O && git -C . commit -m x"
seg allow "…and so is a relative cd in a subshell"                         "cd $O && (cd . && git commit -m x)"
seg deny  "a relative -C with no cd is relative to the cwd"                "git -C . commit -m x"
# From the cross-family pre-review of this change (2026-10-04). `cd` is a directory change
# only as the command of its segment; `-C` is found after other global flags and may be
# quoted.
seg deny  "'cd /tmp' inside a commit message does not retarget the commit" 'git commit -m "cd /tmp"'
seg deny  "…nor does an echo of it in an earlier segment"                  'echo "cd /tmp" && git commit -m x'
seg allow "cd as the first command of a brace group is a cd"              "{ cd $O && git commit -m x; }"
seg allow "…and, as in the shell, it persists past the closing brace"      "{ cd $O && git status; } && git commit -m x"
seg allow "-C after another global flag is still read"                     "git --no-pager -C $O commit -m x"
seg deny  "…and judged where it points"                                    "cd $O && git --no-pager -C $D commit -m x"
mkdir -p "$O/with space" && git init -q -b feature/spaced "$O/with space" 2>/dev/null \
  && git -C "$O/with space" commit -q --allow-empty -m i 2>/dev/null
seg allow "a quoted -C path with a space resolves whole"                   "git -C \"$O/with space\" commit -m x"
# The scan follows the commit. A key staged HERE must be caught when the commit is here,
# whatever another segment names; and a commit aimed at the other repo scans that repo.
# Assembled at run time: the guard scans this file's own staged diff, and a literal
# key here is exactly what it blocks (it did, 2026-10-04 — the right answer).
printf 'AKIA%s\n' IOSFODNN7EXAMPLE > "$D/leak.txt"; git -C "$D" add leak.txt >/dev/null 2>&1
git -C "$D" checkout -q -b feature/here 2>/dev/null   # off the protected branch, so only the scan can deny
seg deny  "staged key here is caught despite -C elsewhere on another segment" "git -C $O status && git commit -m x"
seg deny  "…and despite a cd elsewhere after the commit"                       "git commit -m x && cd $O"
# Allowed until 2026-10-05: the commit is aimed at $O, which is clean. Now the cwd is
# scanned whatever the command's cd's say, because the scope reading can be fooled (see
# below), so a key staged where the command was typed blocks it — and the deny names it.
seg deny  "a commit aimed at the other repo still scans the cwd"                 "cd $O && git commit -m x"
# A `cd` inside `( … )` or `$( … )` ends at the `)` (#70). It used to persist for the
# guard, so the scan read the other repo, found it clean, and let the key here through.
seg deny  "a cd inside ( … ) does not move the scan off the commit's repo"      "(cd $O && make) && git commit -m x"
seg deny  "…nor does one inside \$( … )"                                         "x=\$(cd $O && pwd) && git commit -m x"
seg deny  "an unbalanced ) in a commit message does not disturb the target"     'git commit -m "fix)" && true'
# The splitter's paren scope is a guess (quotes, heredocs, `case` are not parsed), so the
# scan does not use it: the cwd and every repo a `cd` names are scanned too. Each of these
# fooled the scoped reading in review (/dg, 2026-10-05) and is caught by the union.
seg deny  "a quoted ) inside a subshell, then a cd: the cwd is still scanned"    "(echo \"doing ) thing\" && cd $O && true) && git commit -m x"
seg deny  "a case pattern ) inside a subshell, then a cd"                        "(case x in x) cd $O ;; esac) && git commit -m x"
seg deny  "a quoted ( inside a subshell pairs with the real )"                   "(cd $O && git commit -m \"wip (part\") && git commit -m y"
seg deny  "a cd in a pipeline runs in a subshell"                                "cd $O | true; git commit -m x"
seg deny  "heredoc text with stray parens around a real cd"                      "cat > n.md <<'EOF'
- see (below
EOF
cd $O
cat > m.md <<'EOF'
- done :)
EOF
cd $D && git commit -m x"
seg deny  "the commit-message heredoc with a 1) list, key here"                  "git commit -m \"\$(cat <<'EOF'
fix: thing (scope)

1) first
2) second
EOF
)\""
seg deny  "a commit inside a subshell elsewhere still scans the cwd it was typed in" "(cd $O && git commit -m x)"
# Every commit's repo is scanned, not the first one's (#69). A command that commits in
# two repos had the second one's staged diff never looked at.
seg deny  "a key here is caught when another repo's commit comes first"         "git -C $O commit -m a && git commit -m x"
git -C "$D" reset -q leak.txt 2>/dev/null
printf 'AKIA%s\n' IOSFODNN7EXAMPLE > "$O/leak.txt"; git -C "$O" add leak.txt >/dev/null 2>&1
seg deny  "a key staged in the SECOND commit's repo is caught (-C)"             "git commit -m x && git -C $O commit -m b"
seg deny  "…and when the second commit is reached by cd"                         "git commit -m x && cd $O && git commit -m b"
seg allow "a key in a repo the command never names is not its business"        "git commit -m x"
seg deny  "a key in a repo the command cds through is — a false deny, by design" "cd $O && git status; cd $D && git commit -m x"
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
      <<<"$(jq -n --arg c "cd $O && git status; cd $D && git commit -m x" '{tool_input:{command:$c}}')" 2>/dev/null)
if grep -qF "In $O:" <<<"$OUT"; then PASS=$((PASS+1)); printf '  ✅ …and the deny names the repo holding the key\n'
else FAIL=$((FAIL+1)); printf '  ❌ …and the deny names the repo holding the key\n     got: %s\n' "$OUT"; fi
git -C "$O" reset -q leak.txt 2>/dev/null
printf 'AKIA%s\n' IOSFODNN7EXAMPLE > "$D/leak.txt"; git -C "$D" add leak.txt >/dev/null 2>&1
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
      <<<"$(jq -n --arg c "git commit -m a && git commit -m b" '{tool_input:{command:$c}}')" 2>/dev/null)
if grep -q 'AWS access key' <<<"$OUT" && ! grep -q '  In /' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ two commits in one repo: one finding, no repo label\n'
else FAIL=$((FAIL+1)); printf '  ❌ two commits in one repo: one finding, no repo label\n     got: %s\n' "$OUT"; fi
rm -rf "$D" "$O"

echo "Paren scope still decides the BRANCH verdict (#70):"
# The scan no longer depends on the scope; the branch policy still does, so the stack is
# pinned here, from a protected checkout with nothing staged.
D=$(make_repo dev); O=$(make_repo feature/elsewhere)
seg allow "a commit inside ( cd elsewhere … ) is aimed there"                    "(cd $O && git commit -m x)"
seg allow "a closing ) restores the directory of its own (, not the cwd"         "(cd $O && (cd $D && true) && git commit -m x)"
seg deny  "…and the outer ) restores the cwd"                                    "(cd $O && (cd $D && true)) && git commit -m x"
seg deny  "\$(( )) arithmetic is balanced and changes nothing"                  "n=\$((1+2)) && git commit -m x"
rm -rf "$D" "$O"

echo "The scan is bounded, and closed at the bound:"
# Every directory a cd names is scanned, at a git call or two each. A command with
# hundreds of them would run the hook past its timeout, and a killed hook lets the
# command through unchecked — so past the bound it denies instead. 2026-10-05.
D=$(make_repo feature/x)
MANY=$(for i in $(seq 1 100); do printf 'cd /tmp/d%d\n' "$i"; done; echo "cd $D && git commit -m x")
SECONDS=0
seg deny  "a commit after 100 distinct cd targets is denied, not scanned"        "$MANY"
T=$SECONDS
if [[ $T -le 20 ]]; then PASS=$((PASS+1)); printf '  ✅ …in %ss\n' "$T"
else FAIL=$((FAIL+1)); printf '  ❌ …in %ss (want ≤20)\n' "$T"; fi
SAME=$(for i in $(seq 1 100); do printf 'cd %s\n' "$D"; done; echo "git commit -m x")
seg allow "one directory named 100 times is one entry, not a hundred"           "$SAME"
rm -rf "$D"

echo "The paren splitter stays linear on a long command:"
# bash 3.2 runs \${s//(/…} super-linearly under a UTF-8 locale: the first version of the
# marked splitter took 188s on this input, past any hook timeout — and a hook that is
# killed lets the command through unchecked. 2026-10-05.
eval "$(sed -n '/^command_segments() {/,/^}/p;/^command_segments_marked() {/,/^}/p' "$HOOK")"
BIG=$(for i in $(seq 1 1000); do printf 'x%d = f(g(%d), h(%d))\n' "$i" "$i" "$i"; done)
SECONDS=0; NSEG=$(LC_ALL=en_US.UTF-8 command_segments_marked "$BIG" | grep -c '^[()]$'); T=$SECONDS
if [[ $NSEG -eq 6000 && $T -le 10 ]]; then PASS=$((PASS+1)); printf '  ✅ %s bytes, %s parens, %ss\n' "${#BIG}" "$NSEG" "$T"
else FAIL=$((FAIL+1)); printf '  ❌ %s bytes: %s parens (want 6000) in %ss (want ≤10)\n' "${#BIG}" "$NSEG" "$T"; fi
echo "An unresolvable cd target: the SECRET half is fixed, the branch half is not:"
# `cd "$(git rev-parse --show-toplevel)"` and `cd "$VAR"` arrive unexpanded, so
# `git -C "$WORK_DIR"` resolves no repo. Two different halves, two different answers,
# both deliberate:
#
#   - The staged-secret scan now falls back to the shell's cwd. A leaked key is
#     backstopped by nothing, so scanning nothing was the wrong answer.
#   - Branch policy still resolves to nothing and therefore allows. Failing closed would
#     mean judging the cwd's branch for a command aimed elsewhere — and `cd "$W" && git
#     commit` run from a main checkout, aimed at a feature worktree, is the single most
#     common shape in this project's own transcripts. It would deny all of them. The
#     branch half is backstopped by the ref gate; this is F6's accepted limit, recorded
#     in hooks/README.md, not an oversight.
check "cd \$(...) then commit is allowed"  allow main 'cd "$(git rev-parse --show-toplevel)" && git commit -m x'
check "cd \$VAR then commit is allowed"    allow main 'cd "$REPO_ROOT" && git commit -m x'
check "…while a resolvable cd still denies" deny main "cd . && git commit -m x"

echo "A staged secret is caught even when the target repo cannot be resolved:"
# `git -C "$WORK_DIR"` failing emptied STAGED_DIFF as well as the branch, so the secret
# scan silently had nothing to look at. The branch half is backstopped by the ref gate;
# this half is backstopped by nothing.
for pfx in 'cd "$(git rev-parse --show-toplevel)" && ' 'cd "$REPO_ROOT" && ' 'git --no-pager ' ''; do
  D=$(make_repo feature/x)
  printf '%s\n' "$AKIA" > "$D/leak.txt"
  git -C "$D" add leak.txt >/dev/null 2>&1
  case "$pfx" in
    'git --no-pager ') cmd="git --no-pager commit -m x" ;;
    '')                cmd="git commit -m x" ;;
    *)                 cmd="${pfx}git commit -m x" ;;
  esac
  OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null)
  if grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
    PASS=$((PASS+1)); printf '  ✅ staged AWS key caught: %s\n' "$cmd"
  else
    FAIL=$((FAIL+1)); printf '  ❌ staged AWS key MISSED: %s\n' "$cmd"
  fi
  rm -rf "$D"
done

echo "A bare +refspec is a force push:"
# The bare +refspec is deliberately NOT matched — see is_force_push. These pin that
# decision, and the ordinary commands it protects.
check "bare +refspec is not matched"  allow feature/x 'git push origin +main'
check "the colon form still is"       deny  feature/x 'git push origin +feature/x:main'
check "chmod +x then push"            allow main      'chmod +x hooks/agent/foo.sh && git push'
check "push then tail -n +2"          allow main      'git push origin main 2>&1 | tail -n +2'
check "a date +FORMAT beside a push"  allow main      'git push origin feature/x && date -u +%Y-%m-%dT%H:%M:%SZ'

echo "Missing JSON parser must fail loud, not silent:"
# Regression: with jq absent the command parsed as "" and the hook exited 0 —
# the guard switched itself off without a word.
bare_path() {  # a PATH holding the tools the hook needs, minus whatever is named
  local b; b=$(mktemp -d)
  local t; for t in bash sh git sed grep tail cat env printf; do
    command -v "$t" >/dev/null 2>&1 && ln -s "$(command -v "$t")" "$b/$t"
  done
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 && ln -s "$(command -v "$t")" "$b/$t"; done
  printf '%s' "$b"
}
D=$(make_repo main); P=$(bare_path)
OUT=$(cd "$D" && PATH="$P" CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
      <<<'{"tool_input":{"command":"git rm f.txt"}}' 2>/dev/null)
if grep -q '"permissionDecision": *"deny"' <<<"$OUT" && grep -q 'jq' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ no jq, no python3: git command denied with an install hint\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ no jq, no python3: git command was not denied\n'
fi
OUT=$(cd "$D" && PATH="$P" CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
      <<<'{"tool_input":{"command":"ls -la"}}' 2>/dev/null); RC=$?
# With no jq and no python3 this is the case most likely to die rather than decide,
# and dying would satisfy the assertion below.
if [[ $RC -ne 0 ]]; then
  FAIL=$((FAIL+1)); printf '  ❌ harness: the hook exited %s with no parser — the pass-through proved nothing\n' "$RC"
elif grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
  FAIL=$((FAIL+1)); printf '  ❌ no parser: a non-git command was denied\n'
else
  PASS=$((PASS+1)); printf '  ✅ no parser: a non-git command still passes\n'
fi
rm -rf "$P"
# The ref a push or a branch deletion NAMES is read by splitting the command, and that
# split used to shell out to `tr`. bare_path has never included it, so this case also
# pins the dependency: without `tr` the split returned nothing, the target read as "none
# named", and the verdict fell back to the branch you stand on — measured 2026-09-12,
# `git push --force origin main` from a feature branch was ALLOWED, silently.
# `bare_path jq`, not `bare_path`: with neither jq nor python3 the guard denies on the
# input-parse path instead, and the assertion below would pass without ever reaching the
# code it is about. Checked — it did, against the unfixed guard.
P=$(bare_path jq); FB=$(make_repo feature/x)
for c in 'git push --force origin main' 'git push origin :main' 'git branch -D main'; do
  OUT=$(cd "$FB" && PATH="$P" CLAUDE_PROJECT_DIR="$FB" bash "$HOOK" \
        <<<"$(printf '{"tool_input":{"command":"%s"}}' "$c")" 2>/dev/null); RC=$?
  if [[ $RC -ne 0 ]]; then
    FAIL=$((FAIL+1)); printf '  ❌ harness: the hook exited %s on a bare PATH\n' "$RC"
  elif grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
    PASS=$((PASS+1)); printf '  ✅ no tr on PATH: %s is still denied\n' "$c"
  else
    FAIL=$((FAIL+1)); printf '  ❌ no tr on PATH: %s was ALLOWED — the target was never parsed\n' "$c"
  fi
done
rm -rf "$P" "$FB"

if command -v python3 >/dev/null 2>&1; then
  P=$(bare_path python3)
  OUT=$(cd "$D" && PATH="$P" CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
        <<<'{"tool_input":{"command":"git rm f.txt"}}' 2>/dev/null)
  if grep -q '"permissionDecision": *"deny"' <<<"$OUT" && grep -q 'protected branch' <<<"$OUT"; then
    PASS=$((PASS+1)); printf '  ✅ python3 fallback parses and denies normally\n'
  else
    FAIL=$((FAIL+1)); printf '  ❌ python3 fallback did not produce a normal deny\n'
  fi
  rm -rf "$P"
fi
rm -rf "$D"

echo "A large staged binary is not read as text (/dg, 2026-10-05):"
# Scanned whole, a 30 MB asset took 16s and a 100 MB one 52s; past the hook's timeout the
# commit runs unchecked. Loose bound, as below.
D=$(make_repo feature/x)
head -c 41943040 /dev/urandom > "$D/big.bin" && git -C "$D" add big.bin || die "could not stage the large binary"
START=$SECONDS
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" <<<'{"tool_input":{"command":"git commit -m x"}}' 2>/dev/null); rc=$?
TOOK=$((SECONDS - START))
if [[ $rc -eq 0 && "$TOOK" -le 8 ]] && ! grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ a 40 MB binary: allowed in %ss (bound 8s)\n' "$TOOK"
else
  FAIL=$((FAIL+1)); printf '  ❌ a 40 MB binary: rc=%s, %ss (bound 8s)\n' "$rc" "$TOOK"
fi
rm -rf "$D"
# The same binary with a `diff` attribute, which tells git it is text: the size limit
# followed git's word, so it was read whole, and could outrun the timeout. "Binary" is now
# the content's call, not the repo's attributes (security review, 2026-10-12).
D=$(make_repo feature/x)
echo '*.bin diff' > "$D/.gitattributes" && head -c 41943040 /dev/urandom > "$D/big.bin" \
  && git -C "$D" add .gitattributes big.bin || die "could not stage the attributed binary"
START=$SECONDS
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" <<<'{"tool_input":{"command":"git commit -m x"}}' 2>/dev/null); rc=$?
TOOK=$((SECONDS - START))
if [[ $rc -eq 0 && "$TOOK" -le 8 ]] && ! grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ a 40 MB binary marked diff (text): skipped in %ss (bound 8s)\n' "$TOOK"
else
  FAIL=$((FAIL+1)); printf '  ❌ a 40 MB binary marked diff (text): rc=%s, %ss (bound 8s)\n' "$rc" "$TOOK"
fi
rm -rf "$D"
# A name starting with `:` looked like git's status line in the listing, so the file was
# never sized and was read whole (security review of 77fa561, 2026-10-12).
D=$(make_repo feature/x)
head -c 41943040 /dev/urandom > "$D/:big.bin" && git -C "$D" add ":(literal):big.bin" || die "could not stage :big.bin"
START=$SECONDS
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" <<<'{"tool_input":{"command":"git commit -m x"}}' 2>/dev/null); rc=$?
TOOK=$((SECONDS - START))
if [[ $rc -eq 0 && "$TOOK" -le 8 ]] && ! grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ a 40 MB binary named :big.bin: skipped in %ss (bound 8s)\n' "$TOOK"
else
  FAIL=$((FAIL+1)); printf '  ❌ a 40 MB binary named :big.bin: rc=%s, %ss (bound 8s)\n' "$rc" "$TOOK"
fi
rm -rf "$D"

echo "A long heredoc and a commit are judged well inside the hook's timeout (#73):"
# A hook killed by its timeout lets the command run unchecked. A heredoc splits into a
# segment per line, and the guard forked once or twice per segment: 64 KB took ~17s on
# macOS before #73 and ~1.5s after. The bound is loose on purpose — this catches the
# per-segment fork coming back, not a slow CI runner.
D=$(make_repo feature/x)
printf '%s\n' "$AKIA" > "$D/leak.txt"; git -C "$D" add leak.txt >/dev/null 2>&1 || die "could not stage the key"
BODY=$(for i in $(seq 1 1600); do printf 'x_%04d = compute(value_%04d) + 1  # c\n' "$i" "$i"; done)
CMD=$(printf 'cat > f.py <<EOF\n%s\nEOF\ngit add f.py && git commit -m x' "$BODY")
[ "${#CMD}" -gt 60000 ] || die "the long command is only ${#CMD} bytes"
START=$SECONDS
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$HOOK" \
      <<<"$(jq -n --arg c "$CMD" '{tool_input:{command:$c}}')" 2>/dev/null)
TOOK=$((SECONDS - START))
if grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ 64 KB heredoc + commit: a verdict was reached (the staged key denied)\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ 64 KB heredoc + commit: no deny for the staged key\n'
fi
if [ "$TOOK" -le 8 ]; then
  PASS=$((PASS+1)); printf '  ✅ 64 KB heredoc + commit: judged in %ss (bound 8s)\n' "$TOOK"
else
  FAIL=$((FAIL+1)); printf '  ❌ 64 KB heredoc + commit: took %ss (bound 8s)\n' "$TOOK"
fi
rm -rf "$D"

echo "A git read that fails is a deny, not a clean scan (2026-10-12):"
# Every git read of the staged diff had its status dropped, so a git that failed was an
# empty diff and the commit was allowed unscanned. The hook is run with a `git` that
# fails (exit 128, saying so) when every word of $FAIL_ON is among its arguments.
D=$(make_repo feature/x); SHIM=$(mktemp -d)
REAL_GIT=$(command -v git)
cat > "$SHIM/git" <<SH
#!/bin/sh
[ -n "\$FAIL_ON" ] || exec "$REAL_GIT" "\$@"
for w in \$FAIL_ON; do case " \$* " in *"\$w"*) ;; *) exec "$REAL_GIT" "\$@" ;; esac; done
[ -z "\$PARTIAL" ] || printf '1\t0\tpart'
echo "git-said-\$FAIL_ON" >&2; exit 128
SH
chmod +x "$SHIM/git" || die "could not build the failing git"
echo clean > "$D/a.py" && printf '\000\001bin' > "$D/b.bin" && git -C "$D" add a.py b.bin >/dev/null 2>&1 \
  || die "could not stage the clean files"
# guard_run <dir> <command> [env…] — the hook's stdout; rc in $GUARD_RC.
guard_run() {
  local d="$1" c="$2"; shift 2
  GUARD_OUT=$(cd "$d" && CLAUDE_PROJECT_DIR="$d" env "$@" bash "$HOOK" \
              <<<"$(jq -n --arg c "$c" '{tool_input:{command:$c}}')" 2>/dev/null); GUARD_RC=$?
}
# verdict <description> <expect deny|allow> [<text the output must hold>…]
verdict() {
  local desc="$1" expect="$2" got t; shift 2
  if [[ $GUARD_RC -ne 0 ]]; then
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     harness: the hook exited %s\n' "$desc" "$GUARD_RC"; return
  fi
  if grep -q '"permissionDecision": *"deny"' <<<"$GUARD_OUT"; then got=deny; else got=allow; fi
  for t in "$@"; do grep -qF -- "$t" <<<"$GUARD_OUT" || got="$got, without \"$t\""; done
  if [[ "$got" == "$expect" ]]; then PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"; fi
}
guard_run "$D" "git commit -m x" PATH="$SHIM:$PATH"
verdict "the stand-in git, failing nothing, allows a clean commit" allow
for f in --raw --text --name-only --name-status; do
  guard_run "$D" "git commit -m x" FAIL_ON="$f" PATH="$SHIM:$PATH"
  verdict "git diff $f fails — denied, with git's error" deny "could not read what is staged" "git-said-$f"
done
# The size lookup reads its input from stdin, so a re-run for its error has nothing to
# say; its status is the message.
guard_run "$D" "git commit -m x" FAIL_ON="--batch-check=%(objectsize)" PATH="$SHIM:$PATH"
verdict "git cat-file --batch-check fails — denied" deny "could not read what is staged" "batch-check exited 128"
# The credential filter is a step too: an awk that fails there is a deny, not "nothing
# found". The stand-in awk fails when its program reads the binaries' list.
REAL_AWK=$(command -v awk)
printf '#!/bin/sh\n[ -n "$FAIL_AWK" ] && case "$*" in *ENVIRON*) echo awk-said >&2; exit 2 ;; esac\nexec "%s" "$@"\n' "$REAL_AWK" > "$SHIM/awk" \
  && chmod +x "$SHIM/awk" || die "could not build the failing awk"
guard_run "$D" "git commit -m x" FAIL_AWK=1 PATH="$SHIM:$PATH"
verdict "the credential filter (awk) fails — denied" deny "could not read what is staged" "filtering the staged diff"
# A git that dies mid-record: its partial record and the status record must not merge
# into one the loop skips.
guard_run "$D" "git commit -m x" FAIL_ON=--raw PARTIAL=1 PATH="$SHIM:$PATH"
verdict "git diff --raw fails after partial output — denied, with its status" deny "--raw exited 128"
rm -rf "$D"

# The same, with a real git: a repo whose diff config git rejects (git commit fails there
# too). Another repo in the same command holds a key; the deny names both.
D=$(make_repo feature/x); O=$(make_repo feature/o)
echo clean > "$D/a.py" && git -C "$D" add a.py && git -C "$D" config diff.renameLimit abc \
  && printf 'AKIA%s\n' IOSFODNN7EXAMPLE > "$O/k.txt" && git -C "$O" add k.txt || die "could not build the two repos"
guard_run "$D" "git -C $O commit -m a && git commit -m b"
verdict "a repo git cannot diff, and a key in another — denied, naming both" deny \
  "could not read what is staged" "In $D:" "In the repos it could read" "In $O:" "AWS access key"
rm -rf "$D" "$O"

# One read for the whole diff: a per-file pathspec of 14,000 files overran the argument
# limit (exit 126) and denied a legitimate commit; before that, the credential check was
# silently skipped. 9,000 files of 240-character paths is past the limit on macOS and
# Linux; one of them holds a credential literal, which must still be found.
D=$(make_repo feature/x); _long=$(printf 'd%.0s' $(seq 1 200))
mkdir -p "$D/src/$_long" || die "could not build the large tree"
for i in $(seq 1 9000); do echo "v = $i" > "$D/src/$_long/file_$i.py"; done
echo 'password = "hunter2hunter2"' > "$D/src/$_long/file_9000.py"
git -C "$D" add src >/dev/null 2>&1 || die "could not stage the large tree"
guard_run "$D" "git commit -m x"
verdict "9,000 staged files: read whole, the credential literal among them found" deny "hardcoded credential"
grep -q 'could not read' <<<"$GUARD_OUT" && { FAIL=$((FAIL+1)); printf '  ❌ …and no read failed\n'; } \
  || { PASS=$((PASS+1)); printf '  ✅ …and no read failed\n'; }
rm -rf "$D"

# The binaries' names reach the credential filter too: passed in the environment, a few
# thousand of them overran Linux's 128 KB limit on one variable, awk never started, and
# the check found nothing (/dg, 2026-10-12). 3,000 small binaries under a 60-character
# directory is past it; a credential literal in a source file must still be found.
D=$(make_repo feature/x); _dir=$(printf 'b%.0s' $(seq 1 60))
mkdir -p "$D/assets/$_dir" || die "could not build the binary tree"
for i in $(seq 1 3000); do printf '\000%s' "$i" > "$D/assets/$_dir/icon_$i.bin"; done
echo 'password = "hunter2hunter2"' > "$D/app.py"
git -C "$D" add . >/dev/null 2>&1 || die "could not stage the binary tree"
guard_run "$D" "git commit -m x"
verdict "3,000 staged binaries: the credential literal in source is still found" deny "hardcoded credential"
rm -rf "$D"

# A file was exempt from the credential heuristic when its diff held a NUL (read as
# \001) — "a binary". So one planted control byte, visible in the diff but easy to miss,
# muted the warning for everything else in that file, while the six key patterns still
# fired (#76, confirmed against the running hook 2026-10-12). Nothing a file contains
# switches its own scan off now: byte × payload, both scanners' bullets asserted.
for byte in '\000' '\001'; do
  for payload in "password = \"hunter2hunter2hunter2\"" "$AKIA"; do
    case "$payload" in password*) want="hardcoded credential" ;; *) want="AWS access key" ;; esac
    D=$(make_repo feature/x)
    { echo "x = 1"; printf 'junk%bjunk\n' "$byte"; echo "$payload"; } > "$D/app.py"
    git -C "$D" add app.py || die "could not stage the control-byte fixture"
    guard_run "$D" "git commit -m x"
    verdict "a $byte byte in the file does not hide \`${payload%% *}…\` from the scan" deny "$want"
    rm -rf "$D"
  done
done
# The byte's position, not only its value: inside the literal, inside the keyword, and
# in a file exempt by name — dropped from the line, the literal and the keyword
# reassemble; the name exemption is untouched by what the file holds (pre-review of
# this change, 2026-10-12: value was crossed with payload, never with position).
for byte in '\000' '\001'; do
  D=$(make_repo feature/x); printf 'password = \"hunter2%bhunter2hunter2\"\n' "$byte" > "$D/app.py"
  git -C "$D" add app.py || die "could not stage the split-literal fixture"
  guard_run "$D" "git commit -m x"
  verdict "a $byte inside the credential literal does not split it" deny "hardcoded credential"
  rm -rf "$D"
  D=$(make_repo feature/x); printf 'pass%bword = \"hunter2hunter2hunter2\"\n' "$byte" > "$D/app.py"
  git -C "$D" add app.py || die "could not stage the split-keyword fixture"
  guard_run "$D" "git commit -m x"
  verdict "a $byte inside the keyword does not split it" deny "hardcoded credential"
  rm -rf "$D"
  D=$(make_repo feature/x); mkdir -p "$D/tests"; printf 'junk%bjunk\npassword = \"hunter2hunter2\"\n' "$byte" > "$D/tests/fx.py"
  git -C "$D" add tests || die "could not stage the exempt-file fixture"
  guard_run "$D" "git commit -m x"
  verdict "a $byte in a test file: the name exemption still holds — allowed" allow
  rm -rf "$D"
done
# And the cost of having no content-based exemption, pinned so it is a decision and not a
# surprise: a small binary with a credential-shaped string in it is reported too. A real
# binary with no such string is not — the ordinary case, paired with the deny above.
D=$(make_repo feature/x); printf '\000\001PNG\000 password = \"hunter2hunter2\" \000\n' > "$D/img.png"
git -C "$D" add img.png || die "could not stage the binary fixture"
guard_run "$D" "git commit -m x"
verdict "a binary holding a credential-shaped string is reported (no exemption to plant)" deny "hardcoded credential"
rm -rf "$D"
D=$(make_repo feature/x); printf '\000\001PNG\000\377\376 pixels \000\n' > "$D/img.png"; echo "x = 1" > "$D/app.py"
git -C "$D" add . || die "could not stage the clean binary fixture"
guard_run "$D" "git commit -m x"
verdict "a binary with no credential-shaped string, beside clean source — allowed" allow
rm -rf "$D"

# git's file-name prefixes are the repo's to set (diff.dstPrefix, diff.noprefix); the
# filter reads names from `+++ b/…`, so a test fixture's password stops being a test
# file's under another prefix (/dg, 2026-10-12). The scan pins them.
for cfg in "diff.dstPrefix x" "diff.noprefix true" "diff.mnemonicPrefix true"; do
  D=$(make_repo feature/x); mkdir -p "$D/tests"
  echo 'password = "hunter2hunter2"' > "$D/tests/fx.py" && git -C "$D" add tests && git -C "$D" config $cfg \
    || die "could not build the $cfg fixture"
  guard_run "$D" "git commit -m x"
  verdict "with $cfg, a test fixture's password is still a test file's" allow
  rm -rf "$D"
done

# A name with a space gets a trailing tab on its `+++ b/<path>` line; kept, it broke every
# `$`-anchored file rule, and a prose page lost its exemption (/dg, 2026-10-12).
for c in "allow|setup guide.md" "allow|test_login flow.py" "allow|notes on sign in.txt" "deny|my icon.bin" \
         "allow|ünïcode notes.md" 'allow|say "hi".md' "deny|src/app main.py"; do
  D=$(make_repo feature/x); f=${c#*|}; mkdir -p "$D/$(dirname "$f")"
  { case "$f" in *.bin) printf '\000' ;; esac; echo 'password = "correcthorsebattery"'; } > "$D/$f" \
    && git -C "$D" add . || die "could not stage $f"
  guard_run "$D" "git commit -m x"
  verdict "a credential-shaped line in \"$f\": ${c%%|*}" "${c%%|*}"
  rm -rf "$D"
done

echo "A ~ or \$HOME commit target, from outside every repo (2026-10-12):"
# `~` and `$HOME` were left unexpanded, so from a directory that is no repo the target
# resolved nowhere and nothing was scanned. They are expanded now. Any other `$VAR` the
# guard cannot expand stays unscanned here, by the owner's call: it is allowed, and the
# repo's own git hook scans it if it runs one.
H=$(cd "$(mktemp -d)" && pwd -P); R=$(make_repo feature/x); mv "$R" "$H/r"
printf 'AKIA%s\n' IOSFODNN7EXAMPLE > "$H/r/k.txt" && git -C "$H/r" add k.txt || die "could not stage in \$HOME/r"
for c in 'cd ~/r && git commit -m x' 'cd $HOME/r && git commit -m x' 'cd "$HOME/r" && git commit -m x' \
         'cd ${HOME}/r && git commit -m x' 'git -C ~/r commit -m x'; do
  guard_run "$H" "$c" HOME="$H"
  verdict "$c — the key is found" deny "AWS access key"
done
guard_run "$H" 'cd "$REPO" && git commit -m x' HOME="$H"
verdict 'cd "$REPO" && git commit, from outside every repo — allowed, unscanned (owner'"'"'s call)' allow
rm -rf "$H"

# No repo at all is not a failed read: nothing is staged anywhere yet, and what the
# command itself stages is the git pre-commit hook's to scan (#71).
N=$(cd "$(mktemp -d)" && pwd -P)
guard_run "$N" "git init -q r && cd r && git commit --allow-empty -m x"
verdict "a commit in a repo the command creates, from outside any repo, is allowed" allow
rm -rf "$N" "$SHIM"

echo
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
