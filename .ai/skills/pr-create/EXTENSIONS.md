# /pr-create — flight-rules' own extensions

Step 2b, in this repo: the release PR body also states what the release adds, by class,
from `git diff --numstat origin/main...<sha>` — added and net lines by the classes
`CLAUDE.md` → *Releasing* names, the five summing to the total (`MISSION.md` question
3). The count is evidence, not a gate: whether it is proportionate to what the release
closes is the owner's call, made with the CHANGELOG entry beside the number. 0.27.0
added 4,554 lines, 4,071 of them hook and test code, and no gate recorded the number.
The shipped step leaves it out: its classes are this repo's, and an app has no hook and
guard code to count.
