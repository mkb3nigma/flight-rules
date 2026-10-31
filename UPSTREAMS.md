# Upstream Sources

The external works this playbook adapts from, with the ref we last reviewed against.
`/upstream-check` reads this file, compares each pinned ref to the source's current
state, and reports what moved so it can be folded in by hand. Licence/attribution
detail lives in [ATTRIBUTIONS.md](ATTRIBUTIONS.md) — this file tracks **sync state**.

To add a future external reference: add a row here (and an ATTRIBUTIONS entry if it's a
derivation), then run `/upstream-check`.

| Source | Feeds | Kind | Pinned ref | Pinned |
|--------|-------|------|-----------|--------|
| [v1r3n/dinesh-gilfoyle](https://github.com/v1r3n/dinesh-gilfoyle) | `skills/dg/` | git repo | `48d2f6428cfd0dde7b099bc8a3b4405452937c65` | 2026-07-22 |
| [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) | `rules/engineering-principles.md` (principles 1–4) | git repo | `2c606141936f1eeef17fa3043a72095b4765b9c2` | 2026-07-22 |
| [karpathy LLM-wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) | `skills/docs-lint/` (concept only) | gist | revision as of 2026-07-22 | 2026-07-22 |
| [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/diagnose/` (structure and several disciplines — see ATTRIBUTIONS) | git repo | `8b78b531ab965735c5dc74f6f7a219e1e37326df` | 2026-08-15 |

> **`mattpocock/skills` re-pinned after review.** The row was added pinned at
> `694fa303` (the source's state on 2026-06-10, what the original borrow was reviewed
> against) precisely so the backlog would show. That review is now done — 323 commits
> read, adoptions and deliberate non-adoptions recorded in `ATTRIBUTIONS.md` — so the pin
> moves to the reviewed HEAD. This is the pin-what-you-reviewed rule working end to end.

> **`v1r3n/dinesh-gilfoyle` baseline review done (2026-10-17).** Its `dg/SKILL.md`,
> `dinesh-agent.md`, `gilfoyle-agent.md` and `comic-template.html` at `48d2f642` — still
> upstream HEAD — were read against `skills/dg/`. Taken: no finding quota, research-only
> persona briefs, file:line and fix per finding, the wider review domains, the dependency
> CVE scan, the banter score and the comic strip. Not taken: the "continue?" prompt at the round
> cap (owner's call). What changed in the taking is in `ATTRIBUTIONS.md`. The pin stays.

> **Baseline note:** pins were initialised on 2026-07-22 to each source's then-current
> state. The existing adaptations predate this pin, so a one-time manual review of each
> source is recommended before trusting a future "up to date" — after that first review,
> re-pin and subsequent `/upstream-check` runs are precise.
