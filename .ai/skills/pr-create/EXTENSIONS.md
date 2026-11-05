# /pr-create — flight-rules' own extensions

Step 2b, in this repo: the release PR body also states what the release adds, by class,
from `git diff --numstat origin/main...<sha>` — added and net lines by the classes
`AGENTS.md` → *Releasing* names, the five summing to the total (`MISSION.md` question
3). The count is evidence, not a gate: whether it is proportionate to what the release
closes is the owner's call, made with the CHANGELOG entry beside the number. 0.27.0
added 4,554 lines, 4,071 of them hook and test code, and no gate recorded the number.
The shipped step leaves it out: its classes are this repo's, and an app has no hook and
guard code to count.

Before step 2a, in this repo: run `/upstream-check` and put its report in the release PR
body under `## Upstream check` — each `UPSTREAMS.md` source up to date, or what changed
and whether this release takes it (folded in on a branch merged to `dev` first) or
leaves it (an issue). The `release review` check fails a PR into `main` without that
section filled. Owner's instruction, 2026-11-01: the release is the moment a change
upstream can still reach the batch.

Also before step 2a, in this repo: run `mutation/run.sh -j 4` from a worktree of the
commit being promoted (`mutation/README.md` gives the commands) and put its summary line
in the release PR body under `## Mutation run`. The `release review` check fails a PR
into `main` unless that line is clean and names the PR's head commit, so a commit pushed
after the run means running it again. Owner's instruction, 2026-11-04 and -05: the
suites are checked against a broken hook before every release, better safe than sorry.
