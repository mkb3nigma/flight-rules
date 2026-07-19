# Multi-AI Rules Architecture

One rules system that works across AI coding assistants (Claude Code, Cursor,
Windsurf, Copilot, Codex, …). Rules are maintained in exactly one place per project;
every assistant reaches them through a small pointer file.

## Layout

```
.ai/
├── master-rules.md          # The project's rules (tech stack, patterns, workflow)
├── rules/                   # Focused rule files (security, testing, …)
├── skills/                  # Reusable AI workflows (plain Markdown, tool-agnostic)
└── hooks/                   # Git hooks (core.hooksPath) + agent/ hook scripts

Root pointer files (each a few lines, all pointing at .ai/master-rules.md):
├── CLAUDE.md                        # Claude Code
├── .cursorrules                     # Cursor
├── .windsurfrules                   # Windsurf
└── .github/copilot-instructions.md  # GitHub Copilot
```

## Principles

1. **Pointer files stay minimal** — a reference to the master rules plus a
   quick-reference table. Content lives in `.ai/`, never in the pointers.
2. **Skills are plain Markdown** — invocation, numbered process, output format. Any
   assistant that reads Markdown can execute them; Claude Code additionally loads them
   as slash commands (directly or via a plugin).
3. **Tiered reading** — mark rules by tier (essential / patterns / reference) so
   assistants stop reading when the current tier suffices; context is a budget.
4. **Two-layer rules** — generic rules live in a shared playbook repo (this one);
   the project's master-rules points at it and adds only project specifics. Project
   files extend and override; generic improvements flow upstream to the playbook.
5. **Local extensions pattern** — a project extending a shared skill keeps the shared
   body verbatim and appends a clearly marked `## <Project> Extensions` section that
   is never synced upstream.
6. **Hook logic lives in `.ai/hooks/`, not in a tool's config dir** — git hooks are
   already tool-agnostic (`git config core.hooksPath .ai/hooks`); assistant-event hook
   *scripts* (commit guards, session banners) go in `.ai/hooks/agent/`, and each
   tool's own config (e.g. `.claude/settings.json` or a `.claude/hooks/*` shim) is a
   thin pointer that just `exec`s them. Caveat: the scripts consume each tool's hook
   I/O protocol (Claude Code: JSON on stdin, structured deny output), so a second
   tool needs a small adapter — but the guard logic stays in one place.
