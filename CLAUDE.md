# flight-rules — working in this repo

`MISSION.md` says what flight-rules is for; `AGENTS.md` says how work is done here, for
every assistant. Both are imported so they load with this file.

@MISSION.md
@AGENTS.md

## Claude Code only

`.claude/skills/<name>/SKILL.md` are three-line pointers at `skills/<name>/SKILL.md` (all
but `upstream-check`, which lives there whole), so
`/pre-merge-check`, `/pr-create`, `/commit` and the rest run as slash commands here
without the plugin (which would register the guard twice). `.claude/settings.json`
wires the agent hooks from `hooks/agent/`.
