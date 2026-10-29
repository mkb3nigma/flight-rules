# /dg — flight-rules' own extensions

This repo is the playbook, so a review here asks what no adopting project needs asked:
whether the change belongs. `MISSION.md` holds the five questions; this file puts them
in every reviewer's brief.

## Review Domains, this repo

In addition to the skill's domains, every brief — the pre-reviewer's and each
persona's — carries `MISSION.md` → *The five questions* verbatim, and:

- **For the change as a whole**: its answer to each question that applies, and which do
  not and why (`MISSION.md` → *The five questions* says which apply). A change that
  leaves a question that applies to it unanswered is a finding, whatever else is right
  about it. An assistant may apply a finding in the `Mission` column but not decline
  one: a change that cannot answer goes to the owner (`MISSION.md` → *How this file
  changes*).
- **For each finding that proposes a refusal or a check**: the failure tagged
  *accident* or *deliberate* (question 1); the legitimate everyday shape the proposal
  would newly refuse, or "none" (question 4). A deliberate-only failure is recorded, not
  fixed.
- **For a release** (`pr-create` 2b), **or a review of the codebase**: the questions are
  asked of each subsystem, not once of the sum — a change against the mission hides in a
  large diff the way a defect does. The subsystems: git hooks (`hooks/git/`); agent
  hooks and doctor (`hooks/agent/`, `hooks/*.sh`); skills (`skills/`); rules and this
  repo's instructions (`rules/`, `MISSION.md`, `CLAUDE.md`); configuration and wiring
  (`.ai/`, `.claude/`, `.claude-plugin/`, `hooks/hooks.json`); CI (`.github/`); other
  docs (READMEs, CHANGELOG, attributions). A test is reviewed with the subsystem it
  tests; a file that fits none goes to the nearest, and is named. A review of the
  codebase has no diff: there, question 3 is answered with what the subsystem holds —
  its lines by class, and what it costs to read and to keep.

The verdict's register carries a `Mission` column for the change and for each such
finding: the question it fails, or `—`.
