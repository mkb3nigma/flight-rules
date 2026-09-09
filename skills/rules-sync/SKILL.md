---
name: rules-sync
description: Pull the latest playbook (flight-rules) and diff a project's local rule/skill copies against it — reporting upstream improvements to fold in, expected local adaptations, and conflicts. Does not auto-apply.
---

# /rules-sync — Sync a Project's Local Rule Copies With the Playbook

## Project extensions

Before executing, check the consuming project for `.ai/skills/rules-sync/EXTENSIONS.md`.
If present, read it first: it supplies the project's `{PLACEHOLDER}` values, plus any
additional or replacement steps and project-specific rules — extensions take
precedence over the generic defaults below. If absent, use the defaults as-is.

A project that adopts flight-rules keeps **local copies** of some rules/skills under
`{LOCAL_RULES_DIRS}` (default: `.ai/rules/`, `.ai/skills/`), adapted with filled-in
`{PLACEHOLDER}` values and `## <Project> Extensions` sections. Those forks drift as the
playbook evolves — nothing keeps them in sync automatically. This skill **pulls the
latest playbook, then diffs each local copy against its upstream counterpart** and
reports what to reconcile. It never edits local files without your say-so.

Project parameters:
- `{PLAYBOOK_PATH}` — the authoritative flight-rules checkout to compare against: the
  installed plugin dir (often `${CLAUDE_PLUGIN_ROOT}` for `flight-rules`) or a local
  clone (e.g. `~/Projects/flight-rules`).
- `{LOCAL_RULES_DIRS}` — where the project keeps its adapted copies (default
  `.ai/rules/`, `.ai/skills/`).

---

## Step 1 — Refresh the playbook to latest
Bring `{PLAYBOOK_PATH}` up to date so the comparison is against current upstream:
- **Plugin install:** update it through the Claude Code marketplace (`/plugin` →
  update, or rely on marketplace auto-update). Note the installed version from
  `.claude-plugin/plugin.json`.
- **Local clone:** `git -C {PLAYBOOK_PATH} pull --ff-only` and report the new commit.

Record the playbook version/commit you are syncing against — it goes in the report so
the sync is reproducible.

## Step 2 — Map local copies to upstream files
Match by path/basename:
- `{LOCAL_RULES_DIRS}/<name>.md` ↔ `{PLAYBOOK_PATH}/rules/<name>.md`
- `.ai/skills/<name>/SKILL.md` ↔ `{PLAYBOOK_PATH}/skills/<name>/SKILL.md` (copy-in)
- `.ai/skills/<name>/EXTENSIONS.md` ↔ `{PLAYBOOK_PATH}/skills/<name>/SKILL.md`
  (the recommended model — the project holds only a delta, so there is nothing to
  diff line-by-line; see Step 3b)

Classify every local file:
- **Mapped** — has an upstream counterpart → compare in Step 3.
- **Project-only** — no upstream match (e.g. a project-specific rule) → skip, list as
  "local-only, not from the playbook".
- **Available-but-not-adopted** — an upstream rule/skill the project has no local copy
  of → list as "available upstream; adopt if useful".

## Step 3 — Diff and classify each mapped pair
For each pair, diff local vs upstream and sort every hunk into one bucket:

- **Expected local adaptation — ignore.** Filled-in `{PLACEHOLDER}` values, and anything
  inside a `## <Project> Extensions` (or equivalently-marked local-only) section. Per the
  playbook's sync-note convention, extensions are local-only and are **never** drift.
- **Upstream ahead — candidate to fold in.** Upstream added or improved content the local
  copy lacks, in a region the project did *not* customize.
- **Conflict — needs a decision.** Upstream changed the same region the project also
  edited. Show both sides.

Treat pure line-rewrapping / whitespace as non-substantive (note it, don't dwell).

## Step 3b — Check each EXTENSIONS.md against its upstream skill
An extension is a delta, so it can break silently when the skill it extends moves
under it. For each one, check that:
- every **step number or step name** it replaces or inserts after still exists
  upstream and still means the same thing;
- every `{PLACEHOLDER}` it fills is still used by the skill — and is **not** one of the
  five branch/path parameters, which belong in `.ai/flight-rules.conf` only (an
  extension restating `{PROTECTED_BRANCHES}` is a value the hooks never see: report it
  as a conflict, fix is to delete it from the extension);
- any rule it overrides has not since been folded into a hook, in which case the
  override is dead.
Report as ⬆ / ✖ like Step 3.

## Step 3c — Check `.ai/flight-rules.conf`
The hooks read this file as data and **ignore any key they do not know**, so a typo
(`PROTECTED_BRANCH=`) silently falls back to the default. Report any key outside
`PROTECTED_BRANCHES`, `PR_ONLY_BRANCHES`, `NOTE_GATED_BRANCHES`, `INTEGRATION_BRANCH`,
`WORKTREE_DIR` as ✖, and any of the five that is absent as "(default in effect)".

## Step 4 — Report (do not auto-apply)
Print a per-file summary:

```
Playbook: flight-rules <version/commit> (synced <date>)

engineering-principles.md   ⬆ upstream ahead (2 hunks) · 🔧 3 local adaptations · ✔ no conflicts
skills/commit/SKILL.md      ✔ up to date
git-workflow.md             ✖ CONFLICT (1) · 🔧 6 local adaptations
<name>                      (local-only — not from the playbook)
docs-lint                   (available upstream — not adopted here)
```

For each **upstream-ahead** hunk, show what folding it in would add. For each
**conflict**, show upstream vs local and state the trade-off.

## Step 5 — Offer to apply, selectively
Ask which upstream-ahead hunks to fold into the local copies. Apply only the ones the
user approves; leave conflicts for a manual decision. Never touch `## <Project>
Extensions` sections or overwrite filled-in placeholders. Summarise what changed.

> This skill reconciles a project **downstream** of the playbook. To check whether the
> playbook's own upstream sources (the repos it adapts from) have moved, use
> `/upstream-check` inside the flight-rules repo.
