# flight-rules

Generic, project-agnostic engineering rules and AI workflows, distilled from real
projects (first: [AppliHawk](https://applihawk.com)). One source of truth — projects
consume this repo instead of maintaining drifting copies.

The name is borrowed from NASA's *flight rules* — the accumulated, written-down
procedures for every situation a mission has already encountered, so nobody improvises
a known problem twice.

Everything here is **plain Markdown and tool-agnostic**: the same files work with
Claude Code, Cursor, Windsurf, Codex, or any assistant that reads Markdown context.
A thin Claude Code plugin wrapper is included so Claude installs the skills natively.

## Layout

```
rules/     Always-on principles a project's CLAUDE.md / .cursorrules should point at
skills/    Invocable workflows (/dg, /diagnose, /feature-start, /pre-merge-check, /commit)
.claude-plugin/   Claude Code marketplace + plugin manifests
```

## Consuming from a project

**Claude Code (skills, native):**
```
/plugin marketplace add mkb3nigma/flight-rules     # or the local clone path
/plugin install flight-rules@flight-rules
```

**Any AI tool (rules, by pointer):** add one line to the project's rules entry point
(CLAUDE.md, .cursorrules, `.ai/master-rules.md`, …):

> Generic engineering rules: read `~/Projects/flight-rules/rules/` (or the repo URL).
> Project rules extend and override them.

## Project-specific extensions

Never edit these files with project details. A project that needs to extend a skill
keeps a local copy with a clearly marked `## <Project> Extensions` section at the
bottom (see the sync note pattern inside `skills/dg/SKILL.md`), or overrides a rule in
its own rules file. **Generic changes flow here; project flavor stays in the project.**

## Parameters

Skills refer to placeholders rather than hardcoding a project's setup:

| Placeholder | Meaning | AppliHawk example |
|---|---|---|
| `{PROTECTED_BRANCHES}` | branches that never take direct commits | `main`, `staging`, `dev` |
| `{INTEGRATION_BRANCH}` | where feature branches merge | `dev` |
| `{WORKTREE_DIR}` | where feature worktrees live | `.ai/worktrees/` |
| `{TEST_COMMANDS}` | the project's suites | `pytest` / `npm run test:run` |

A project defines these once in its own rules file; skills read them from there.

## Credits & license

MIT for original content (see `LICENSE`). Two pieces are adaptations of other people's
work and carry their upstream licenses — the `dg` skill (from
[v1r3n/dinesh-gilfoyle](https://github.com/v1r3n/dinesh-gilfoyle), Apache-2.0) and the
engineering principles (from
[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills),
MIT, after Andrej Karpathy's observations). Details and modification notes:
[ATTRIBUTIONS.md](ATTRIBUTIONS.md).
