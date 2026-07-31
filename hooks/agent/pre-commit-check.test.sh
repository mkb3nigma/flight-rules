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

echo "Configurable protected set:"
check "custom: release/1.0 protected"    deny  release/1.0 'git rm f.txt' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^(main|release/.*)$'
check "custom: dev no longer protected"  allow dev  'git rm f.txt' \
      FLIGHT_RULES_PROTECTED_BRANCHES='^(main|release/.*)$'

echo
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
