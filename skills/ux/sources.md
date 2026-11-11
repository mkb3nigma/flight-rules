# Sources

Every source the topic files rest on, and the rules that depend on each. This file is
for maintaining the guide, not for building with it: when a source changes, its row says
which rules to re-read.

**Living** sources can change under the same URL, and are pinned in `UPSTREAMS.md`, so
`/upstream-check` notices when they move. **Fixed** sources are published papers: they
do not change, but newer work can supersede them, which a release review asks.

`skills/catalogue.test.sh` checks this file: every rule ID named here exists, and every
`[standard]` and `[finding]` rule is named in at least one row.

| Source | Kind | Rules |
|---|---|---|
| WCAG 2.2, W3C Recommendation, 12 December 2024 — https://www.w3.org/TR/WCAG22/ | living | A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 A11 A12 A13 A14 A15 A16 A17 A18 A19 A20 A21 A22 A23 A24 A25 A26 A27 A28 A29 A30 A31 A33 A34 A35 F1 F2 F4 F9 F13 F14 F15 F20 |
| Core Web Vitals thresholds (Interaction to Next Paint) — https://web.dev/articles/defining-core-web-vitals-thresholds | living | S10 |
| Nielsen Norman Group, *Response Times: The 3 Important Limits* — https://www.nngroup.com/articles/response-times-3-important-limits/ | living | S7 S8 S9 |
| Ghibellini and Meier (2025), Zeigarnik and Ovsiankina meta-analysis, *Humanities and Social Sciences Communications* 12 — https://ideas.repec.org/a/pal/palcom/v12y2025i1d10.1057_s41599-025-05000-w.html | fixed | S19 |
| Kahneman et al., the peak-end rule (1993) | fixed | S18 |
| Kivetz, Urminsky and Zheng (2006), the goal-gradient effect | fixed | F24 |
| Hick (1952); Hyman (1953) | fixed | P1 |
| von Restorff (1933), the isolation effect | fixed | P3 |
| Wertheimer (1923), Gestalt principles | fixed | P8 P9 P12 |
| Palmer (1992), common region | fixed | P10 |
| Palmer and Rock (1994), uniform connectedness | fixed | P11 |
| Fitts (1954); ISO 9241-411 | fixed | P13 |
| Cowan (2001), working-memory capacity — https://www.cambridge.org/core/journals/behavioral-and-brain-sciences/article/magical-number-4-in-shortterm-memory-a-reconsideration-of-mental-storage-capacity/44023F1147D4A1D44BDC0AD226838496 | fixed | P15 |
| Murdock (1962) and earlier list-recall work, the serial position effect | fixed | P16 |
| Kurosu and Kashimura (1995), the aesthetic-usability effect | fixed | P18 |
| Nielsen (2000), Jakob's law | fixed | P6 |
| RFC 761 (1980), Postel's robustness principle | fixed | P17 |
| The UX laws in my CLAUDE.md, Adam Hayes, 2026-09-01 — the starting list, concept only | living | P1 P3 P6 P8 P9 P11 P12 P13 P15 P16 P17 S18 S19 F24 |
