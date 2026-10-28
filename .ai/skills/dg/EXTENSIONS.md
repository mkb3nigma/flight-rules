# /dg — flight-rules' own extensions

This repo is the playbook, so a review here asks what no adopting project needs asked:
whether the change belongs. `MISSION.md` holds the five questions; this file puts them
in every reviewer's brief.

## Review Domains, this repo

In addition to the skill's domains, every brief — the pre-reviewer's and each
persona's — carries `MISSION.md` → *The five questions* verbatim, and:

- **For the change as a whole**: its answer to each of the five, or the class that
  exempts it from 1, 2, 4 and 5 (question 3 is never exempt). A change that answers
  none is a finding, whatever else is right about it.
- **For each finding that proposes a rule, a refusal or a check**: the failure tagged
  *accident* or *deliberate* (question 1); the legitimate everyday shape the proposal
  would newly refuse, or "none" (question 4). A deliberate-only failure is recorded, not
  fixed.
- **For a release** (`pr-create` 2b): the questions are asked of each subsystem of the
  diff, not once of the sum — a change against the mission hides in a large diff the
  way a defect does.

The verdict's register carries a `Mission` column for the change and for each such
finding: the question it fails, or `—`.
