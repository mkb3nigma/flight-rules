---
name: rules-sync
description: Pull the latest playbook (flight-rules) and diff a project's local rule/skill copies against it — reporting upstream improvements to fold in, expected local adaptations, and conflicts. Does not auto-apply.
---

# /rules-sync — Sync a Project's Local Rule Copies With the Playbook

## Project extensions

Read `.ai/skills/rules-sync/EXTENSIONS.md` first if the project has one: extra or
replacement steps, project rules, and `{PLACEHOLDER}` values. It overrides the
defaults below.

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
- `.ai/skills/<name>/<file>` ↔ `{PLAYBOOK_PATH}/skills/<name>/<file>` — the files a
  copied-in skill reads from its own directory — each one its SKILL.md names as
  "`<file>` beside this file". One upstream has and the copy lacks is
  **Available-but-not-adopted** with its `cp` command: the copied SKILL.md looks for it
  beside itself, and the step that reads it cannot run without it.
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

## Step 3b — EXTENSIONS.md and the conf
An extension is a delta, so it breaks silently when the skill under it moves. For each
one, report ✖ if: a step it replaces or inserts after no longer exists upstream; a
`{PLACEHOLDER}` it fills is no longer used, or is one of the five branch/path
parameters (those live in the conf only — the hooks never read an extension); a rule it
overrides has since become a hook.
Then `.ai/flight-rules.conf`: the hooks ignore unknown keys, so a typo silently falls
back to the default. ✖ any key outside those `hooks/flight-rules-doctor.sh` lists in `KNOWN` — read it rather than hard-coding a count. An absent key is NOT an error: every one has a default, and `NOTE_GATED_BRANCHES` is deliberately absent in the playbook itself.

## Step 3c — The git hooks
The project's `.ai/hooks/` (or whatever `core.hooksPath` names) is a copy too, and the
one a plugin update can never refresh: AppliHawk ran four 0.22.0 hooks under a 0.23.0
plugin with nothing but a CHANGELOG paragraph to say so (2026-10-12). Run
`bash {PLAYBOOK_PATH}/hooks/flight-rules-doctor.sh` and carry its hook lines into the
report: ❌ a copy byte-identical to an older release (stale, no question), ⚠️ one that
matches no release (adapted here, or stale — show the diff and ask). The fix is the
command doctor prints, `install.sh --from {PLAYBOOK_PATH}/hooks/git --stale-only
--this-checkout`, run on a branch; without `--stale-only` it replaces every copy that
differs, adapted ones included. A hook marked `# flight-rules: adapted`
shows ✅ in doctor — the mark silences the daily check, not this one: show its diff
against `{PLAYBOOK_PATH}/hooks/git/` on every sync, so an upstream fix to a hook the
project adapted is folded in by hand rather than lost. It writes a diff the owner commits; with
`HOOK_SYNC=auto` in the conf, `session-start.sh` runs the `--stale-only` form at the
first session after an update, so a project that sets it should rarely show ❌ here.

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
