# Multi-AI Rules Architecture

One rules system that works across AI coding assistants (Claude Code, Codex,
Copilot, …). Rules are maintained in exactly one place per project;
every assistant reaches them through a small pointer file.

## Layout

```
.ai/
├── master-rules.md          # The project's rules (tech stack, patterns, workflow)
├── rules/                   # Focused rule files (security, testing, …)
└── skills/                  # Reusable AI workflows (plain Markdown, tool-agnostic)
    └── <name>/EXTENSIONS.md # This project's deltas to a shared skill

.flight-rules/               # What flight-rules itself keeps in the project
├── conf                     # Branch policy — the one file every hook and skill reads
├── hooks/                   # Git hooks (core.hooksPath); agent/ only when hand-wired
└── worktrees/               # Feature worktrees, git-ignored (WORKTREE_DIR moves it)

Root pointer files (each a few lines, all pointing at .ai/master-rules.md):
├── CLAUDE.md                        # Claude Code
├── AGENTS.md                        # Codex, and any assistant that reads AGENTS.md
├── GEMINI.md                        # Gemini CLI, which reads it, not AGENTS.md, by default
└── .github/copilot-instructions.md  # GitHub Copilot
```

## Principles

1. **Pointer files stay minimal** — a reference to the master rules plus a
   quick-reference table. Content lives in `.ai/`, never in the pointers.
2. **Skills are plain Markdown** — invocation, numbered process, output format. Any
   assistant that reads Markdown can execute them; Claude Code additionally loads them
   as slash commands (directly or via a plugin). Project-local registration is a thin
   pointer file per skill — `.claude/skills/<name>/SKILL.md` today (`.claude/commands/`
   still works but is the legacy location) — frontmatter plus one line pointing at the
   skill's body (for the project's own skill, `.ai/skills/<name>/SKILL.md`):

   ```markdown
   ---
   name: <name>
   description: One-line summary shown in the command picker.
   argument-hint: "<what to pass>"
   ---

   Read and follow `.ai/skills/<name>/SKILL.md`. Arguments: $ARGUMENTS
   ```

   `name:` is not optional — it is what the assistant matches on, and this playbook's
   own `skills/catalogue.test.sh` rejects a pointer without it.

   The pointer may also pin a model (`model: opus`) for expensive skills. Logic never
   goes in the pointer — same rule as the root pointer files.
3. **Two-layer rules** — generic rules live in a shared playbook repo (this one);
   the project's master-rules points at it and adds only project specifics. Project
   files extend and override; generic improvements flow upstream to the playbook.
4. **Local extensions pattern** — a project extending a shared skill writes its deltas
   in a separate `.ai/skills/<name>/EXTENSIONS.md`, which every SKILL.md reads first.
   The shared body is never copied, so it can be updated in place and the project's
   delta is the only thing to review on a sync. (Keeping a full local copy with an
   appended `## <Project> Extensions` section is the **legacy** pattern — it works, and
   it is how forks silently drift from the source.)
5. **Hook logic lives outside any one tool's config dir** — git hooks are already
   tool-agnostic (`git config core.hooksPath <dir>`), and each tool's own config
   (e.g. `.claude/settings.json`) should be a thin pointer that just `exec`s the
   scripts. Caveat: the scripts consume each tool's hook I/O protocol (Claude Code:
   JSON on stdin, structured deny output), so a second tool needs a small adapter —
   but the guard logic stays in one place.
   Where the scripts physically live depends on how the playbook was installed:
   **with the plugin the agent hooks are already
   live from the plugin directory, and a local copy makes the guard run twice.** The
   git hooks are still copy-in — no plugin can set `core.hooksPath`. A project that
   hand-wires everything does use `.flight-rules/hooks/`; one that uses the plugin copies only
   `hooks/git/`.
6. **Planning models plan and review; implementation is handed over** — where a project
   names which of its models plan and review (the most capable, and costliest, tier)
   and which implement, in its master rules, that is the regular course of work. A
   planning model stops at the plan and hands the work over; it reviews what comes
   back. In a review, its part is the cold, independent read; the adversarial debate,
   and a light check of a fix that only applies agreed findings, run on the tier below
   by default (`/dg` step 3). The handover is an issue in the project's tracker
   carrying the plan — what
   changes and where, the tests that must fail first, what is decided and what is still
   open — or a handover file where an issue does not fit; a plan left only in a chat or
   a model's memory is not one. Where the design is uncertain (a test may change it),
   the planning model may run a short spike first and hands over with what it found.
   The implementing model reports where it departed from the plan, and why, so the
   review knows where to look. The person can override this for any task, and a small
   direct ask — a doc line, filing an issue — is done by whoever is asked. The rule
   names roles, not models: model names change within months, and the project names
   its own. Advisory: a hook cannot tell planning from implementing.
