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
# nothing and the layer reading it silently stopped enforcing — while doctor.sh, which
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
# resolved the branch from /tmp (no repo, no branch) and was allowed on main.
check "last cd wins"                     deny  main 'cd /tmp && cd . && git rm f.txt'
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
secret_check "AWS key at column zero"         deny  src/config.py 'AKIAIOSFODNN7EXAMPLE'
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
secret_check "AWS key in a test file"         deny  tests/test_a.py 'AKIAIOSFODNN7EXAMPLE'
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
secret_check "provider key in docs still caught" deny docs/setup.md 'key: AKIAIOSFODNN7EXAMPLE'
secret_check "provider key in locale still caught" deny locales/en.json '{"k": "sk-ant-api03-Abc123Abc123Abc123Abc123Abc123Abc123"}'

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
check "checkout -b on a feature branch"   deny  feature/x 'git checkout -b feature/y'
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
check_wt "checkout -b from a worktree"          deny  scratch feature/x 'git checkout -b feature/y'
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
WRAP_NAME=( bare subshell brace-group cd-prefix and-echo echo-and pipe newline-after-main )
WRAP_FMT=(  '%s'
            '(%s)'
            '{ %s; }'
            'cd . && %s'
            '%s && echo done'
            'echo start && %s'
            '%s | cat'
            '%s
echo "=== main now ==="' )

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
              'git rm f.txt'
              'git reset --hard HEAD~1'
              'git clean -fd'
              'git restore f.txt'
              'git stash drop'
              'git stash clear'
              'git rebase'
              'git switch -f'
              'git checkout --' )

# Denied from ANY branch, because they name the protected branch themselves.
DANGER_ANY=( 'git branch -D main'
             'git push --force origin main'
             'git push --mirror'
             'git checkout -b feature/y' )

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
printf '  ✅ %s git-invocation-prefix combinations\n' \
  "$(( ${#PREFIX_NAME[@]} * (${#DANGER_MAIN[@]} + ${#DANGER_ANY[@]} + 3) ))"

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

rm -rf "$GEN_MAIN" "$GEN_FEAT"
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
  printf 'AKIAIOSFODNN7EXAMPLE\n' > "$D/leak.txt"
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

echo
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
