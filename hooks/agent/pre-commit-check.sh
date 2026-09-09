#!/bin/bash
# Agent hook: Branch Policy Enforcer + Secret Leak Watcher
# Wire as a Claude Code PreToolUse hook on the Bash tool (see hooks/README.md).
# Fires on every Bash tool use; only acts on git commands that could damage a
# protected branch — the commit itself, a working-tree mutation that would land
# there without ever reaching a commit, or a force-push that rewrites it.
#
# I/O protocol is Claude Code's: tool input as JSON on stdin, a structured
# permissionDecision on stdout. Another assistant needs a thin adapter around the
# same checks.

# ── Project configuration ────────────────────────────────────────────────────
# Override per project WITHOUT forking this file. Resolution order, first match wins:
#
#   1. Environment             FLIGHT_RULES_PROTECTED_BRANCHES=...   (override)
#   2. .ai/flight-rules.conf   PROTECTED_BRANCHES=^(main|dev)$       (the normal home)
#   3. The defaults below
#
# Put the policy in .ai/flight-rules.conf. It sits beside the rules in the
# tool-agnostic .ai/ directory, so a git hook, a Claude Code hook and any other
# assistant's adapter read one list instead of each restating it in its own settings
# file — the same reason this script lives in .ai/hooks/ rather than .claude/.
# The environment is for a one-off, or a policy meant for one tool only.
#
# It is parsed as DATA — matched with sed, never sourced — so a hostile repository
# cannot execute code through it. Do not "simplify" this to `source`.
read_conf() {
  local key="$1" file="$2"
  [ -r "$file" ] || return 1
  sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$/\1/p" "$file" \
    | sed -E 's/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/' \
    | tail -1
}
#
# The default covers the branch names teams protect in practice, across the common
# conventions (git-flow's develop, release trains, QA/UAT gates), because the guard
# should fail safe. Being stopped on a branch you did not mean to protect costs one
# message; NOT being stopped on one you did costs work. Matching is
# case-insensitive, so QA, Qa and qa are all the same branch to this check.
#
# ⚠️  Either source *REPLACES* the default list below — it does not
#     add to it. "^(integration)$" protects that branch and NOTHING ELSE: main and dev
#     become unguarded. To keep the defaults and add your own, copy the whole pattern
#     and extend the first group:
#       ^(main|master|dev|develop|development|staging|stage|qa|uat|prod|production|integration)$|^release(/|$)
# `^release(/|$)` covers both a bare `release` branch and a `release/1.0` train.
# hotfix/* is deliberately absent: you commit to a hotfix branch, so it is a working
# branch, not one to defend.
DEFAULT_PROTECTED='^(main|master|dev|develop|development|staging|stage|qa|uat|prod|production)$|^release(/|$)'
DEFAULT_WORKTREE_DIR='.ai/worktrees'

# Resolution happens further down, once the command has told us which repo is
# being acted on — the conf file is read from that repo, not from wherever the
# shell happens to be.

# ── Input / output ───────────────────────────────────────────────────────────
# jq is preferred, python3 is the fallback. With neither, the hook cannot see the
# command at all — and the first version then exited 0, so a missing jq switched the
# guard off without a word. A guard that fails silent is the worst kind. Now: a
# payload that does not even mention git has nothing to guard and passes; anything
# else is refused with a message that says what to install.
json_command() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.tool_input.command // ""'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("tool_input") or {}).get("command") or "")'
  else
    return 1
  fi
}
deny() {  # deny <reason> — emit the PreToolUse deny decision
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  else
    python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.argv[1]}}))' "$reason"
  fi
}

INPUT=$(cat)
if ! COMMAND=$(printf '%s' "$INPUT" | json_command); then
  [[ "$INPUT" == *git* ]] || exit 0
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"⛔ BLOCKED: the flight-rules guard cannot read the tool input — neither jq nor python3 is on PATH. Install jq (brew install jq / apt install jq). The guard refuses git commands rather than silently waving them through."}}'
  exit 0
fi

# ── What kind of command is this? ────────────────────────────────────────────
# `git -C <dir>` and `git -c key=val` (both repeatable) sit between `git` and its
# verb. Normalise them away once so every matcher below sees `git <verb>`. The
# first version matched the literal substring "git commit", so `git -C /x commit`
# and `git -c user.name=x commit` walked straight past the branch guard.
NORM=$(printf '%s' "$COMMAND" | sed -E 's/git([[:space:]]+-(C|c)[[:space:]]+[^[:space:]]+)+/git/g')

# $B is what may precede the `git` word. It is a NEGATED class rather than a list
# of separators: the first version enumerated space/;/&/| and so missed `(git rm)`
# and `x=$(git rm)`, letting a subshell or command substitution walk straight past
# the guard. Enumerating metacharacters means the next unlisted one is another hole,
# so anything that cannot continue a command word counts as a boundary. Excluding
# alnum/_/-/. keeps `mygit`, `legit` and `git-foo` from matching.
B='(^|[^[:alnum:]_.-])'

is_commit() { [[ "$1" =~ ${B}git[[:space:]]+commit([[:space:]]|$) ]]; }

# Does this command destroy work in the tree without going through a commit?
# Gating only on `git commit` leaves the branch policy bypassable: `git rm`,
# `git reset --hard`, `git clean -f` and `git checkout -- .` all mutate a
# protected branch's tree, and the guard never sees them because no commit
# follows. `git clean -n` and a bare `git checkout <branch>` are not destructive
# and stay allowed.
is_destructive() {
  [[ "$1" =~ ${B}git[[:space:]]+(rm|restore)([[:space:]]|$) ]] && return 0
  [[ "$1" =~ ${B}git[[:space:]]+reset[[:space:]]+.*--(hard|merge) ]] && return 0
  [[ "$1" =~ ${B}git[[:space:]]+clean[[:space:]]+.*-[a-zA-Z]*f ]] && return 0
  [[ "$1" =~ ${B}git[[:space:]]+checkout[[:space:]]+(--|\.)([[:space:]]|$) ]] && return 0
  # `git checkout <rev> -- <path>` overwrites the path from <rev>; `git switch
  # --discard-changes`/`-f` throws local edits away; `git rebase` rewrites the
  # branch in place (its --abort/--quit/--continue are the way OUT of one and stay
  # allowed); `git stash drop|clear` deletes the only copy of stashed work.
  [[ "$1" =~ ${B}git[[:space:]]+checkout[[:space:]]+[^[:space:]-][^[:space:]]*[[:space:]]+--([[:space:]]|$) ]] && return 0
  [[ "$1" =~ ${B}git[[:space:]]+switch[[:space:]]+.*(--discard-changes|--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$) ]] && return 0
  if [[ "$1" =~ ${B}git[[:space:]]+rebase([[:space:]]|$) ]]; then
    [[ "$1" =~ ${B}git[[:space:]]+rebase[[:space:]]+.*--(abort|quit|continue|skip)([[:space:]]|$) ]] || return 0
  fi
  [[ "$1" =~ ${B}git[[:space:]]+stash[[:space:]]+(drop|clear)([[:space:]]|$) ]] && return 0
  return 1
}

# A force-push rewrites the branch on the remote for everyone. The workflow rule
# ("never force-push a protected branch") was advisory until this matcher existed.
is_force_push() {
  [[ "$1" =~ ${B}git[[:space:]]+push([[:space:]]|$) ]] || return 1
  [[ "$1" =~ [[:space:]](-[a-zA-Z]*f[a-zA-Z]*|--force|--force-with-lease(=[^[:space:]]*)?)([[:space:]]|$) ]] && return 0
  # A leading "+" on a refspec (`+src:dst`) forces that one ref without any flag.
  [[ "$1" =~ [[:space:]]\+[^[:space:]]*:[^[:space:]]+ ]] && return 0
  # Deleting a branch on the remote is the most destructive push of all: `--delete`,
  # `-d`, an empty-source refspec (`origin :main`), or `--mirror` (which deletes
  # everything the remote has that you do not).
  [[ "$1" =~ [[:space:]](--delete|-d|--mirror)([[:space:]]|$) ]] && return 0
  [[ "$1" =~ [[:space:]]:[^[:space:]]+ ]]
}
# The branches a `git push` names. `git push --force origin main` from a feature
# branch still rewrites main, so the target is checked as well as the current
# branch. A refspec `+src:dst` pushes to dst. The first non-flag word after `push`
# is the remote and is skipped — so a deploy remote named `production` is not
# mistaken for the branch. With no explicit ref, the target is the current branch,
# which the caller checks anyway.
push_targets() {
  local rest w words=()
  rest=$(printf '%s' "$1" | sed -E "s/.*${B}git[[:space:]]+push//")
  for w in $rest; do
    case "$w" in -*|'&&'|'||'|';'|'|') continue ;; esac
    w="${w#+}"; w="${w##*:}"; w="${w#refs/heads/}"
    words+=("$w")
  done
  [[ ${#words[@]} -ge 1 ]] && unset 'words[0]'
  printf '%s\n' "${words[@]+"${words[@]}"}"
}

# Workflow rule 6: branches are created as worktrees, never with `checkout -b` /
# `switch -c`. A branch created in place puts feature work in the main checkout —
# the drift the whole worktree workflow exists to prevent — so this is denied on
# EVERY branch of the project, not just protected ones. `git worktree add … -b`
# is the sanctioned form and contains neither verb.
is_branch_create() {
  [[ "$1" =~ ${B}git[[:space:]]+checkout[[:space:]]+([^[:space:]]+[[:space:]]+)*-[bB]([[:space:]]|$) ]] && return 0
  [[ "$1" =~ ${B}git[[:space:]]+switch[[:space:]]+([^[:space:]]+[[:space:]]+)*(-[cC]|--create|--force-create)([[:space:]]|$) ]] && return 0
  return 1
}

if is_commit "$NORM"; then
  ACTION="commit"
elif is_force_push "$NORM"; then
  ACTION="force-push"
elif is_branch_create "$NORM"; then
  ACTION="branch-create"
elif is_destructive "$NORM"; then
  ACTION="destructive"
else
  exit 0
fi

# ─────────────────────────────────────────────
# 1. BRANCH POLICY CHECK
# ─────────────────────────────────────────────
# Which repo is the command aimed at? The LAST `cd` wins (`cd /a && cd /b && git …`
# acts in /b), quotes around the path are tolerated, and `git -C <dir>` retargets
# the repo just as surely as a `cd` does. Without this the guard resolves the
# branch from the shell's cwd and can clear a command that is actually aimed at a
# protected branch in another checkout.
WORK_DIR=""
CD_RE="${B}cd[[:space:]]+(\"[^\"]+\"|'[^']+'|[^[:space:]&;|)]+)"
if [[ "$COMMAND" =~ $CD_RE ]]; then
  WORK_DIR=$(printf '%s' "$COMMAND" | sed -E "s/.*${B}cd[[:space:]]+(\"[^\"]+\"|'[^']+'|[^[:space:]&;|)]+).*/\2/")
  WORK_DIR="${WORK_DIR#\"}"; WORK_DIR="${WORK_DIR%\"}"
  WORK_DIR="${WORK_DIR#\'}"; WORK_DIR="${WORK_DIR%\'}"
elif [[ "$COMMAND" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  WORK_DIR="${BASH_REMATCH[1]}"
fi
GIT=(git)
[[ -n "$WORK_DIR" ]] && GIT=(git -C "$WORK_DIR")
CURRENT_BRANCH=$("${GIT[@]}" branch --show-current 2>/dev/null)

# Now that the target repo is known, resolve config from it: environment first,
# then that repo's .ai/flight-rules.conf, then the built-in defaults.
CONF_ROOT=$("${GIT[@]}" rev-parse --show-toplevel 2>/dev/null)
[ -z "$CONF_ROOT" ] && CONF_ROOT="${CLAUDE_PROJECT_DIR:-.}"
CONF_FILE="$CONF_ROOT/.ai/flight-rules.conf"

PROTECTED_RE="${FLIGHT_RULES_PROTECTED_BRANCHES:-$(read_conf PROTECTED_BRANCHES "$CONF_FILE")}"
PROTECTED_RE="${PROTECTED_RE:-$DEFAULT_PROTECTED}"
WORKTREE_DIR="${FLIGHT_RULES_WORKTREE_DIR:-$(read_conf WORKTREE_DIR "$CONF_FILE")}"
WORKTREE_DIR="${WORKTREE_DIR:-$DEFAULT_WORKTREE_DIR}"

# Escape hatch. Installing the plugin now activates this guard, so a project whose
# normal working branch IS main (or one that simply does not want the worktree
# workflow) needs a way out that is not "uninstall the plugin". PROTECTED_BRANCHES=off
# turns the branch policy off. The secret scan below still runs — leaking a key is
# not a workflow preference.
GUARD_OFF=0
if [[ "$PROTECTED_RE" == "off" || "$PROTECTED_RE" == "none" ]]; then
  GUARD_OFF=1
  # Nothing else to check unless this is a commit: the branch policy was the only
  # gate for the other actions, and there is no staged diff to scan.
  [[ "$ACTION" != "commit" ]] && exit 0
fi

# Case-insensitively, so QA/Qa/qa and Main/main are each one branch to this check.
# Scoped to these comparisons: the command-matching regexes above must stay
# case-sensitive, or `git RM` style false matches creep in.
IS_PROTECTED=0
BLOCKED_BRANCH="$CURRENT_BRANCH"
shopt -s nocasematch
if [[ "$GUARD_OFF" == "0" ]]; then
  [[ "$CURRENT_BRANCH" =~ $PROTECTED_RE ]] && IS_PROTECTED=1
  if [[ "$ACTION" == "force-push" ]]; then
    while IFS= read -r t; do
      [[ -n "$t" && "$t" =~ $PROTECTED_RE ]] && { IS_PROTECTED=1; BLOCKED_BRANCH="$t"; }
    done <<<"$(push_targets "$NORM")"
    # `--mirror` names no branch and touches all of them, protected ones included.
    [[ "$NORM" =~ [[:space:]]--mirror([[:space:]]|$) ]] && { IS_PROTECTED=1; BLOCKED_BRANCH="every branch (--mirror)"; }
  fi
fi
shopt -u nocasematch

# Scope the branch policy to the project this hook belongs to. Without this, the
# guard applies the project's branch rules to every repo the session touches —
# including a sibling repo whose normal working branch IS main. (The secret scan
# below stays global on purpose: secrets are bad in any repo.)
IN_THIS_PROJECT=1
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  TARGET_ROOT=$("${GIT[@]}" rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$TARGET_ROOT" && "$TARGET_ROOT" != "$CLAUDE_PROJECT_DIR" ]]; then
    IN_THIS_PROJECT=0
  fi
fi

# Allow merge commits on protected branches — merging feature branches in is the
# intended workflow — and the working-tree commands that resolving conflicts needs.
# A force-push gets no such pass: nothing about a merge in progress calls for one.
GIT_DIR_PATH=$("${GIT[@]}" rev-parse --git-dir 2>/dev/null)
if [[ "$IN_THIS_PROJECT" == "0" ]]; then
  # Another repo — its branch policy is not ours to enforce
  :
elif [[ -f "$GIT_DIR_PATH/MERGE_HEAD" && "$ACTION" != "force-push" && "$ACTION" != "branch-create" ]]; then
  # A merge is in progress; let it through
  :
elif [[ "$ACTION" == "branch-create" ]]; then
  deny "⛔ BLOCKED: branches are created as worktrees, not with checkout -b / switch -c.

A branch created in place puts feature work in this checkout — the drift the worktree workflow exists to prevent.

Instead, from the repo root with absolute paths:
  git fetch origin
  git worktree add $WORKTREE_DIR/<name> -b <prefix>/<name> origin/<integration-branch>
  cd $WORKTREE_DIR/<name>

Prefixes: feature/ fix/ refactor/ test/ docs/ chore/ hotfix/. The /feature-start skill does all of this.

If this project does not use the worktree workflow, the owner can set PROTECTED_BRANCHES=off in .ai/flight-rules.conf. That is the owner's call — do not add it yourself to get past this block; ask."
  exit 0
elif [[ "$IS_PROTECTED" == "1" ]]; then
  case "$ACTION" in
    commit)      VERB="You are on it. Never commit directly to a protected branch." ;;
    destructive) VERB="You are on it. This command would rewrite it or discard work in its working tree." ;;
    force-push)  VERB="This command would force-push, delete or overwrite it on the remote, destroying history others have built on." ;;
  esac
  # The message names the opt-out so a project that never wanted the worktree
  # workflow can find the way out without reading hooks/README.md — but it is
  # addressed to the project owner, not to the agent that just got blocked. An
  # assistant editing the conf to get past its own block is exactly the accidental
  # bypass the README's threat model says to close, so the wording says "ask".
  deny "⛔ BLOCKED: protected branch \"$BLOCKED_BRANCH\".

$VERB

Create a feature worktree instead:
  git worktree add $WORKTREE_DIR/<name> -b feature/<name>
  cd $WORKTREE_DIR/<name>

Use absolute paths in the same command as every git operation — a drifting cwd is how the wrong repo gets modified.

If this project deliberately works on \"$BLOCKED_BRANCH\" and does not use the worktree workflow, the project owner can turn the branch policy off with PROTECTED_BRANCHES=off in .ai/flight-rules.conf (the secret scan stays on). That is the owner's call — do not add it yourself to get past this block; ask."
  exit 0
fi

# Only a commit has a staged diff to scan; the other actions end here.
[[ "$ACTION" != "commit" ]] && exit 0

# ─────────────────────────────────────────────
# 2. SECRET LEAK CHECK
# ─────────────────────────────────────────────
STAGED_DIFF=$("${GIT[@]}" diff --cached 2>/dev/null)
# core.quotePath=false: by default git prints a non-ASCII name as "c\303\266nfig.py"
# in quotes, and feeding that back to `git diff -- <path>` matches nothing — so the
# file was silently never scanned for credential literals.
STAGED_FILES=$("${GIT[@]}" -c core.quotePath=false diff --cached --name-only 2>/dev/null)
FINDINGS=""

# Added lines only, leading "+" stripped. Each file's `+++ b/path` header is dropped
# as its own step: the first version folded that into every pattern as `^\+[^+]`,
# which also demanded one character between the "+" and the secret — so an
# assignment at column zero, the commonest place for one, was never matched.
added_lines() { grep -E '^\+' | grep -vE '^\+\+\+ ' | sed 's/^+//'; }
ADDED=$(printf '%s\n' "$STAGED_DIFF" | added_lines)
hit() { printf '%s\n' "$ADDED" | grep -qE "$1"; }

# .env file staged (matches .env, .env.local, path/.env — but not the documented
# templates: .env.example/.sample/.template/.dist, or a docs page named .env.md)
if printf '%s\n' "$STAGED_FILES" | grep -E '(^|/)\.env(\.|$)' | grep -qvE '\.env\.(example|sample|template|dist|md)$'; then
  FINDINGS="$FINDINGS\n  • .env file is staged for commit"
fi

# Provider key formats. Each is a fixed prefix plus a run of the provider's own
# alphabet; the prefixes are the stable part, so keep the runs generous rather than
# exact. `sk-` keys now carry hyphens and underscores (sk-ant-…, sk-proj-…) — the
# first version required 32 unbroken alphanumerics and missed both.
if hit 'AKIA[A-Z0-9]{16}'; then
  FINDINGS="$FINDINGS\n  • AWS access key pattern detected (AKIA...)"
fi
if hit '(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{20,}'; then
  FINDINGS="$FINDINGS\n  • API key pattern detected (sk-... — OpenAI/Anthropic style)"
fi
if hit 'gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}'; then
  FINDINGS="$FINDINGS\n  • GitHub token pattern detected (ghp_/gho_/github_pat_...)"
fi
if hit 'xox[baprs]-[A-Za-z0-9-]{10,}'; then
  FINDINGS="$FINDINGS\n  • Slack token pattern detected (xox...)"
fi
if hit 'AIza[0-9A-Za-z_-]{35}'; then
  FINDINGS="$FINDINGS\n  • Google API key pattern detected (AIza...)"
fi
# Any PEM private key: RSA, EC, DSA, OPENSSH, ENCRYPTED, or the bare PKCS#8 header.
if hit 'BEGIN [A-Z ]*PRIVATE KEY'; then
  FINDINGS="$FINDINGS\n  • Private key header detected"
fi

# Hardcoded credential literals in non-test source files only. Test fixtures
# legitimately use literal passwords, so test files are excluded by the common
# naming conventions: tests/ and __tests__/ dirs, pytest's test_*.py, Go/Python
# *_test.*, Jest/Vitest *.test.* and *.spec.*, conftest.py.
TEST_FILE_RE='(^|/)(tests?|__tests__|spec|fixtures)/|(^|/)test_[^/]*\.py$|_test\.(py|go|ts|tsx|js|jsx)$|\.(test|spec)\.(ts|tsx|js|jsx|mjs|cjs)$|conftest\.py$'
# Prose and UI strings are not credentials either: a docs page's `secret = "your-…"`
# or a locale file's "Password must be 8 characters" is the commonest false block.
# Provider-key patterns above still scan these files — a real key is a leak anywhere.
PROSE_FILE_RE='(^|/)(docs?|locales?|i18n|translations?)/|\.(md|rst|txt)$'
NON_TEST=()
while IFS= read -r -d '' f; do
  [[ -n "$f" && ! "$f" =~ $TEST_FILE_RE && ! "$f" =~ $PROSE_FILE_RE ]] && NON_TEST+=("$f")
done < <("${GIT[@]}" diff --cached --name-only -z 2>/dev/null)
if [[ ${#NON_TEST[@]} -gt 0 ]]; then
  NON_TEST_ADDED=$("${GIT[@]}" diff --cached -- "${NON_TEST[@]}" 2>/dev/null | added_lines)
  # Case-insensitive (PASSWORD, ApiKey), `=` or `:` (YAML/JSON), quoted key tolerated
  # ("password": "…"). Obvious placeholders are let through so an example does not
  # block a commit: <angle-bracket>, REDACTED, CHANGEME, EXAMPLE, your-…, …-here,
  # xxxxxxxx. A line carrying `flight-rules: allow` is a reviewed, deliberate
  # exception — it is greppable, so it is also auditable.
  if printf '%s\n' "$NON_TEST_ADDED" \
      | grep -iE '(password|passwd|secret|token|api_?key)["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"'$\{]{8,}' \
      | grep -v 'flight-rules: allow' \
      | grep -qviE '<[^>]*>|redacted|changeme|example|placeholder|your[-_ ]|[-_ ]here["'"'"']|x{8,}|\*{8,}'; then
    FINDINGS="$FINDINGS\n  • Possible hardcoded credential (password/secret/token/api_key assigned to a string literal)"
  fi
fi

if [ -n "$FINDINGS" ]; then
  deny "🔐 BLOCKED: Possible secret detected in staged files:
$(echo -e "$FINDINGS")

Remove these before committing. If this is a false positive, unstage and re-check."
  exit 0
fi

exit 0
