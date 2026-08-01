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

# A repo on $1, with the hook scoped to it via CLAUDE_PROJECT_DIR.
make_repo() {
  local branch="$1" dir
  # Resolve symlinks: on macOS mktemp hands back /var/... while git reports the
  # real /private/var/..., and the hook's project-scoping compares the two.
  dir=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$dir" init -q
  git -C "$dir" config user.email t@t.t
  git -C "$dir" config user.name t
  echo x > "$dir/f.txt"
  git -C "$dir" add -A >/dev/null 2>&1
  git -C "$dir" commit -qm init >/dev/null 2>&1
  git -C "$dir" branch -M "$branch" >/dev/null 2>&1
  printf '%s' "$dir"
}

# check <description> <expect: deny|allow> <branch> <command> [env assignments...]
check() {
  local desc="$1" expect="$2" branch="$3" cmd="$4"; shift 4
  local dir out got
  dir=$(make_repo "$branch")
  # Run from inside the repo so a command with no `cd`/`-C` resolves there.
  out=$(cd "$dir" && CLAUDE_PROJECT_DIR="$dir" env "$@" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null)
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [[ "$got" == "$expect" ]]; then
    PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"
  fi
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

echo "Config file (.ai/flight-rules.conf) — the tool-agnostic home:"
# conf_check <desc> <expect> <branch> <command> <conf-contents>
conf_check() {
  local desc="$1" expect="$2" branch="$3" cmd="$4" conf="$5"
  local dir out got
  dir=$(make_repo "$branch")
  mkdir -p "$dir/.ai"; printf '%s\n' "$conf" > "$dir/.ai/flight-rules.conf"
  out=$(cd "$dir" && CLAUDE_PROJECT_DIR="$dir" bash "$HOOK" \
        <<<"$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')" 2>/dev/null)
  if grep -q '"permissionDecision": *"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [[ "$got" == "$expect" ]]; then
    PASS=$((PASS+1)); printf '  ✅ %s\n' "$desc"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected %s, got %s\n' "$desc" "$expect" "$got"
  fi
  rm -rf "$dir"
}

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
printf 'AWS_KEY = "AKIAIOSFODNN7EXAMPLE"\n' > "$D/leak.py"
git -C "$D" add leak.py >/dev/null 2>&1
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" FLIGHT_RULES_PROTECTED_BRANCHES=off \
      bash "$HOOK" <<<'{"tool_input":{"command":"git commit -m x"}}' 2>/dev/null)
if grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
  PASS=$((PASS+1)); printf '  ✅ secret scan still fires when the guard is off\n'
else
  FAIL=$((FAIL+1)); printf '  ❌ secret scan was disabled by PROTECTED_BRANCHES=off\n'
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

echo
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
