---
name: feature-start
description: Create a new feature branch as a git worktree following the playbook's strict branching rules.
argument-hint: "<prefix/branch-name>"
---

# /feature-start — Create a Feature Branch Worktree

## Project extensions

Read `.ai/skills/feature-start/EXTENSIONS.md` first if the project has one: extra or
replacement steps, project rules, and `{PLACEHOLDER}` values. It overrides the
defaults below. Branch and path parameters (`{PROTECTED_BRANCHES}`,
`{PR_ONLY_BRANCHES}`, `{NOTE_GATED_BRANCHES}`, `{INTEGRATION_BRANCH}`, `{WORKTREE_DIR}`)
come **only** from `.ai/flight-rules.conf`, the file the hooks read — an extension
restating one is invisible to enforcement, so the conf wins.

Create a new branch as a git worktree per `rules/git-worktree-workflow.md`.
Project parameters: `{PROTECTED_BRANCHES}`, `{INTEGRATION_BRANCH}`, `{WORKTREE_DIR}`
(defaults: `main` / `main` / `.ai/worktrees/`).

## Rules (non-negotiable)
- NEVER `git checkout -b` / `git switch -c` — always `git worktree add`
- All branches live under `{WORKTREE_DIR}`
- Branch name must start with an allowed prefix: `feature/`, `fix/`, `refactor/`, `test/`, `docs/`, `chore/`, `hotfix/`

## Steps

1. **Check current branch** — the main checkout normally rests on `{INTEGRATION_BRANCH}`;
   that's fine (worktree creation never commits to it). If the working tree is dirty,
   stop and ask what to do with the changes.
2. **Check stashes** — `git stash list`; if any exist, list them and ask whether to
   proceed or resolve first.
3. **Validate the branch name** — ask if not provided; verify the prefix.
4. **Sync the base from origin — non-negotiable.**
   - `git fetch origin` first, **always**. New branches derive from
     **`origin/{INTEGRATION_BRANCH}`** (the true remote state) — never a local copy
     that may be behind. Branching off a stale local base is the exact way work gets
     built on the wrong foundation.
   - **Reconcile `main` into the integration branch** — only when
     `{INTEGRATION_BRANCH}` differs from `main`. A hotfix or change applied straight
     to `main` is not on the integration branch, so a branch built off it silently
     misses it. Check:
     ```bash
     git log --oneline origin/{INTEGRATION_BRANCH}..origin/main
     ```
     If non-empty, check the reverse range too:
     ```bash
     git log --oneline origin/main..origin/{INTEGRATION_BRANCH}
     ```
     - Reverse range **empty** → the integration branch is strictly behind; a
       fast-forward is safe. Print the commits that will move, then update the remote
       branch without touching any local checkout:
       ```bash
       git push origin origin/main:refs/heads/{INTEGRATION_BRANCH} && git fetch origin
       ```
       This is a plain (never forced) push of already-reviewed commits; the guard
       allows it for that reason. If the push is still rejected, the likely causes are
       a stale `origin/*` (fetch and re-check), host branch protection, or missing
       permission — say which you think it is and ask; do not guess "diverged".
     - Reverse range **non-empty** → the branches have diverged and reconciling them
       is a real merge into a protected branch, which is the user's call. STOP, show
       both ranges, ask. Never `git merge` here yourself.
   - **No remote** (`git remote` is empty): branch from the local
     `{INTEGRATION_BRANCH}`, skip fetch and reconcile, say so.
5. **Count the open branches — past the limit, ask.** The limit is
   `FLIGHT_RULES_OPEN_BRANCH_LIMIT` if set, else `OPEN_BRANCH_LIMIT` in
   `.ai/flight-rules.conf` (unset or not a positive whole number: 5; `off`: skip this
   step) — as `session-start` reads it. Open means a branch checked out in a worktree
   with commits not yet in `{INTEGRATION_BRANCH}` — the local one when it exists, else
   `origin/{INTEGRATION_BRANCH}` — leaving out `{INTEGRATION_BRANCH}` itself and any
   branch `{PROTECTED_BRANCHES}` matches (case-insensitive; drop that `grep` when it is
   `off`):
   ```bash
   base=refs/heads/{INTEGRATION_BRANCH}
   git rev-parse -q --verify "$base" >/dev/null || base=refs/remotes/origin/{INTEGRATION_BRANCH}
   git rev-parse -q --verify "$base" >/dev/null || echo "COULD NOT COUNT: no {INTEGRATION_BRANCH}, local or origin/"
   git worktree list --porcelain | sed -n 's|^branch refs/heads/||p' \
     | grep -vxF '{INTEGRATION_BRANCH}' | grep -viE -e '{PROTECTED_BRANCHES}' \
     | while IFS= read -r b; do
         n=$(git rev-list --count "$base..refs/heads/$b") || { echo "COULD NOT COUNT: $b"; continue; }
         [ "$n" -gt 0 ] && echo "$b"
       done
   ```
   A `COULD NOT COUNT` line is never "under the limit": say what could not be counted
   and ask, as at the limit (an error sent to `/dev/null` once read as zero open — fix
   review, 2026-10-24). At or over the limit, show the person how many are open and
   which, which of them have a passing note (`git notes --ref=pre-merge-check show
   <branch>` begins `passed:`) and only wait to merge, and say where the limit is set:
   *"OPEN_BRANCH_LIMIT is <n> in .ai/flight-rules.conf — raise it, or set it to off,
   there"* (or that `FLIGHT_RULES_OPEN_BRANCH_LIMIT` set it). Create the branch only once
   they say it is okay. Under the limit, say nothing. With no one to ask, create
   nothing and report the count as the blocker — a question that cannot be put is not
   a yes. A pile of open branches is
   how this repo's own work came to depend on itself: more than ten sat unmerged
   (2026-10-20 to 10-23), and the owner saw it only once they did (#108).
6. **Create the worktree** from `origin/{INTEGRATION_BRANCH}` (repo root, absolute paths):
   ```bash
   git worktree add {WORKTREE_DIR}/<slug> -b <full-branch-name> origin/{INTEGRATION_BRANCH}
   ```
7. **Symlink untracked env files** from the main checkout (symlinks, not copies —
   copies go stale):
   ```bash
   ln -s "$PWD/<path>/.env" {WORKTREE_DIR}/<slug>/<path>/.env
   ```
   Skip with a warning if the source file is missing. This step is required even when
   a worktree was created with a raw `git worktree add` instead of this skill — a
   worktree running without its env files fails in confusing ways (missing keys,
   stale service URLs).

   Heavyweight untracked dirs are NOT all symlink-safe: interpreter venvs generally
   tolerate a symlink, but **do not symlink `node_modules`** — dev tools that resolve
   real paths (e.g. the Vite dev server) break through the link. Run a fresh
   `npm ci` in the worktree instead.
8. **Confirm** — print the worktree path, the `cd` command, and the reminder:
   "Work only in this directory. ONE purpose per branch." If the repo ships git hooks
   and `core.hooksPath` isn't set, print the one-time install command.
9. **List worktrees** — `git worktree list`.

## Cleanup (after merge — required, never leave stale worktrees)

```bash
git worktree remove {WORKTREE_DIR}/<slug>
git branch -d <branch>
```

To find others already merged, **list them and delete by name** — one command per
branch, never piped into `xargs`:

```bash
git for-each-ref --format='%(refname:lstrip=2)' --merged refs/heads/{INTEGRATION_BRANCH} refs/heads/
# then, for each one you actually want gone:
git branch -d <branch>
```

The previous version of this was a single pipeline —
`git branch --merged | grep -vE '^\*|{PROTECTED_BRANCHES}' | xargs -r git branch -d` —
and it **deleted protected branches**. Three reasons at once, and each is worth knowing
because they recur: `{PROTECTED_BRANCHES}` is an anchored regex (`^main$`) while
`git branch --merged` indents every name by two spaces, so the filter matched nothing;
a branch checked out in another worktree is marked `+`, not `*`, so it passed the first
filter too; and in a project that never substituted the placeholder the pattern is the
literal `{PROTECTED_BRANCHES}`, which matches nothing at all. Reproduced 2026-09-11:
`Deleted branch dev`, `Deleted branch release/1.0`.

`xargs` is the part that made it unrecoverable. The branch names never appear in the
command string, so the agent guard — which denies `git branch -d main` — had nothing to
read and allowed the pipeline. Naming each branch is not a style preference: it is what
lets the guard adjudicate.
