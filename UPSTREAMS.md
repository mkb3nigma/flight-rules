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
| [WCAG 2.2](https://www.w3.org/TR/WCAG22/) | `skills/ux/accessibility.md`, `skills/ux/forms.md` (the level-A and AA success criteria they cite) | W3C spec | W3C Recommendation of 2024-12-12 | 2026-11-11 |
| [Core Web Vitals thresholds](https://web.dev/articles/defining-core-web-vitals-thresholds) | `skills/ux/states.md` (UX-S10, the 200 ms and 500 ms responsiveness thresholds) | web page | INP good ≤ 200 ms, poor > 500 ms, as read 2026-11-11 | 2026-11-11 |
| [NN/g: Response Times, the 3 Important Limits](https://www.nngroup.com/articles/response-times-3-important-limits/) | `skills/ux/states.md` (UX-S08, UX-S09) | web page | 0.1 s / 1 s / 10 s, as read 2026-11-11 | 2026-11-11 |
| [The UX laws in my CLAUDE.md](https://adamhayes.xyz/blog/the-ux-laws-in-my-claude-md) | `skills/ux/principles.md`, `states.md` and `forms.md` (the starting list; concept only) | web page | as published 2026-09-01 | 2026-11-11 |
| [APG: Dialog (Modal) pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/) | `skills/ux/accessibility.md` (UX-A02, UX-A06) | web page | Tab and Shift+Tab wrap inside the dialog, Escape closes it, windows under it are inert, named by `aria-labelledby` or `aria-label`, focus returns to the invoking element, as read 2026-11-13 | 2026-11-13 |
| [APG: Developing a Keyboard Interface](https://www.w3.org/WAI/ARIA/apg/practices/keyboard-interface/) | `skills/ux/accessibility.md` (UX-A06) | web page | persistence of focus: a removed active element drops focus to the body, as read 2026-11-13 | 2026-11-13 |
| [MDN: the Dialog element](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog) | `skills/ux/accessibility.md` (UX-A06) | web page | `showModal()` makes the rest of the page inert and closes on Esc; no name given by the browser, as read 2026-11-13 | 2026-11-13 |
| [APG: Read Me First](https://www.w3.org/WAI/ARIA/apg/practices/read-me-first/) | `skills/ux/accessibility.md` (UX-A36) | web page | "A role is a promise" of the keyboard interactions, as read 2026-11-13 | 2026-11-13 |
| [APG: Sortable Table example](https://www.w3.org/WAI/ARIA/apg/patterns/table/examples/sortable-table/) | `skills/ux/accessibility.md` (UX-A21) | web page | `aria-sort` on the sorted column's header, ascending or descending, as read 2026-11-13 | 2026-11-13 |
| [WAI Tables Tutorial](https://www.w3.org/WAI/tutorials/tables/) | `skills/ux/accessibility.md` (UX-A21) | web page | header cells `th`, `scope` where the header direction is unclear, as read 2026-11-13 | 2026-11-13 |
| [Understanding WCAG 2.2: 1.3.2 Meaningful Sequence](https://www.w3.org/WAI/WCAG22/Understanding/meaningful-sequence.html) | `skills/ux/accessibility.md` (UX-A03) | web page | technique C27 (DOM order matches visual order), failure F1 (CSS positioning), as read 2026-11-13 | 2026-11-13 |
| [ACT rule b4f0c3: Meta viewport allows for zoom](https://www.w3.org/WAI/standards-guidelines/act/rules/b4f0c3/) | `skills/ux/accessibility.md` (UX-A11) | web page | no `user-scalable=no`, no `maximum-scale` below 2; maps to 1.4.4, as read 2026-11-13 | 2026-11-13 |
| [WCAG technique ARIA21](https://www.w3.org/WAI/WCAG22/Techniques/aria/ARIA21) | `skills/ux/forms.md` (UX-F16) | web page | `aria-invalid` not set to true before validation; error tied by `aria-describedby`, as read 2026-11-13 | 2026-11-13 |
| [GOV.UK Design System: Error summary](https://design-system.service.gov.uk/components/error-summary/) | `skills/ux/forms.md` (UX-F16) | web page | summary messages worded as those beside the inputs, linked to each, focus moved to it, as read 2026-11-13 | 2026-11-13 |
| [GOV.UK Design System: Validation](https://design-system.service.gov.uk/patterns/validation/) | `skills/ux/forms.md` (UX-F18) | web page | do not validate on leaving a field; wait until the user moves on, as read 2026-11-13 | 2026-11-13 |
| [web.dev: Optimize Cumulative Layout Shift](https://web.dev/articles/optimize-cls) | `skills/ux/states.md` (UX-S06) | web page | sized images, space reserved for injected content; last updated 2025-02-07, as read 2026-11-13 | 2026-11-13 |
| [NN/g: 10 Usability Heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/) | `skills/ux/principles.md` (UX-P20) | web page | heuristic 2, match between the system and the real world; last reviewed 2024-01-30, as read 2026-11-13 | 2026-11-13 |
| [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/diagnose/` (structure and several disciplines — see ATTRIBUTIONS) | git repo | `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` | 2026-11-12 |

> **`v1r3n/dinesh-gilfoyle` baseline review done (2026-10-17).** Its `dg/SKILL.md`,
> `dinesh-agent.md`, `gilfoyle-agent.md` and `comic-template.html` at `48d2f642` — still
> upstream HEAD — were read against `skills/dg/`. Taken: no finding quota, research-only
> persona briefs, file:line and fix per finding, the wider review domains, the dependency
> CVE scan, the banter score and the comic strip. Not taken: the "continue?" prompt at the round
> cap (owner's call). What changed in the taking is in `ATTRIBUTIONS.md`. The pin stays.

> **Baseline note:** pins were initialised on 2026-07-22 to each source's then-current
> state. The existing adaptations predate this pin, so a one-time manual review of each
> source is recommended before trusting a future "up to date" — after that first review,
> re-pin and subsequent `/upstream-check` runs are precise. Reviewed and re-pinned since:
> `mattpocock/skills` (2026-08-15, from `694fa303`; 2026-11-12, from `8b78b531`; both
> recorded in `ATTRIBUTIONS.md`).
