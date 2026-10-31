# /pr-create — stacked PRs

Read by `/pr-create` before splitting a change across dependent PRs.

Splitting a large change into an ordered series of PRs, each reviewable on its own diff,
is genuinely worth doing. There are two ways to get it, and only one of them is safe.

**Use GitHub's native stacked pull requests.** Public preview since 2026-07-30, all
repositories:

```bash
gh extension install github/gh-stack
```

The platform owns the ordering, which is the whole point:

- Stacks merge **bottom-up**, and a mid-stack PR **cannot** be merged in isolation — the
  PRs below it always merge with it.
- Merging lands the selected PR *and every unmerged PR below it* as one operation.
- The remaining PRs are **automatically rebased** onto the stack base afterwards.
- The merge box shows the status of the **whole stack**, not just the open PR.

Known limits: **auto-merge is not supported** for stacked PRs, and merge-queue support
arrived separately — check both before relying on them.

**Never hand-roll a stack** by pointing `gh pr create --base` at another open PR's head.
It looks identical in the UI and has none of the guarantees:

> Merging the parent makes GitHub retarget the child — *asynchronously*. Merge the child
> before that lands and its commits go into the already-merged parent branch, which is
> then usually auto-deleted. GitHub reports the child as **MERGED**, truthfully, about the
> wrong destination. The commits never reached `{INTEGRATION_BRANCH}` and nothing in the
> UI says so.

This is not hypothetical. It happened in this repo on 2026-08-15 with 22 seconds between
the two merges, and the work survived only because the commit still existed in a local
worktree. A body note reading *"Stacked on #N — review #N first"* was already the first
thing in the child's description and changed nothing, because merging happens from the PR
list and the merge button, and neither shows the body. Ordering that depends on a human
reading prose is not ordering.

**If `gh stack` isn't available** (preview not enabled, non-GitHub host), then don't stack
at all: keep the second branch local and open its PR once the parent merges. Costs a
delay, removes the failure mode entirely. Do not substitute discipline for the mechanism.

**Either way, verify after merging.** `MERGED` is a claim about the merge, not about the
destination:

```bash
git fetch origin && git log --oneline origin/{INTEGRATION_BRANCH} | grep <child-sha>
```

Empty output means the work is stranded on a deleted branch. Recover by re-pushing the
branch from a local copy and opening a fresh PR against the correct base.
