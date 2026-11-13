# Sources

Every source the topic files rest on, and the rules that depend on each. This file is
for maintaining the guide, not for building with it: when a source changes, its row says
which rules to re-read.

**Living** sources can change under the same URL, and are pinned in `UPSTREAMS.md`, so
`/upstream-check` notices when they move. **Fixed** sources are published papers, or a
law's enacted text: they do not change, but newer work can supersede them, which no step checks: whoever changes
a rule resting on one asks it (advisory).

`skills/catalogue.test.sh` checks this file: every rule ID named here exists, and every
`[standard]` and `[finding]` rule is named in at least one row.

| Source | Kind | Rules |
|---|---|---|
| WCAG 2.2, W3C Recommendation, 12 December 2024 — https://www.w3.org/TR/WCAG22/ | living | UX-A01 UX-A02 UX-A03 UX-A04 UX-A05 UX-A06 UX-A07 UX-A08 UX-A09 UX-A10 UX-A11 UX-A12 UX-A13 UX-A14 UX-A15 UX-A16 UX-A17 UX-A18 UX-A19 UX-A20 UX-A21 UX-A22 UX-A23 UX-A24 UX-A25 UX-A26 UX-A27 UX-A28 UX-A29 UX-A30 UX-A31 UX-A33 UX-A34 UX-A35 UX-A37 UX-A38 UX-F01 UX-F02 UX-F04 UX-F09 UX-F13 UX-F14 UX-F15 UX-F20 |
| WAI-ARIA Authoring Practices, Dialog (Modal) pattern — https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/ | living | UX-A02 UX-A06 |
| WAI-ARIA Authoring Practices, Developing a Keyboard Interface (persistence of focus) — https://www.w3.org/WAI/ARIA/apg/practices/keyboard-interface/ | living | UX-A06 |
| MDN, `<dialog>`: the Dialog element (`showModal()`) — https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog | living | UX-A06 |
| WAI-ARIA Authoring Practices, Read Me First (a role is a promise) — https://www.w3.org/WAI/ARIA/apg/practices/read-me-first/ | living | UX-A36 |
| WAI-ARIA Authoring Practices, Sortable Table example (`aria-sort`) — https://www.w3.org/WAI/ARIA/apg/patterns/table/examples/sortable-table/ | living | UX-A21 |
| W3C WAI Tables Tutorial — https://www.w3.org/WAI/tutorials/tables/ | living | UX-A21 |
| Understanding WCAG 2.2, 1.3.2 Meaningful Sequence (technique C27, failure F1) — https://www.w3.org/WAI/WCAG22/Understanding/meaningful-sequence.html | living | UX-A03 |
| W3C ACT rule b4f0c3, Meta viewport allows for zoom — https://www.w3.org/WAI/standards-guidelines/act/rules/b4f0c3/ | living | UX-A11 |
| WCAG 2.2 technique ARIA21, Using `aria-invalid` to indicate an error field — https://www.w3.org/WAI/WCAG22/Techniques/aria/ARIA21 | living | UX-F16 |
| GOV.UK Design System, Error summary — https://design-system.service.gov.uk/components/error-summary/ | living | UX-F16 |
| GOV.UK Design System, Validation pattern (disputes UX-F18's validating on leaving a field) — https://design-system.service.gov.uk/patterns/validation/ | living | UX-F18 |
| GDPR (Regulation (EU) 2016/679), recital 32 — https://gdpr-info.eu/recitals/no-32/ | fixed | UX-F07 |
| web.dev, *Optimize Cumulative Layout Shift* — https://web.dev/articles/optimize-cls | living | UX-S06 |
| Nielsen Norman Group, *10 Usability Heuristics for User Interface Design*, heuristic 2 — https://www.nngroup.com/articles/ten-usability-heuristics/ | living | UX-P20 |
| Core Web Vitals thresholds (Interaction to Next Paint) — https://web.dev/articles/defining-core-web-vitals-thresholds | living | UX-S10 |
| Nielsen Norman Group, *Response Times: The 3 Important Limits* — https://www.nngroup.com/articles/response-times-3-important-limits/ | living | UX-S07 UX-S08 UX-S09 |
| Ghibellini and Meier (2025), Zeigarnik and Ovsiankina meta-analysis, *Humanities and Social Sciences Communications* 12 — https://ideas.repec.org/a/pal/palcom/v12y2025i1d10.1057_s41599-025-05000-w.html | fixed | UX-S19 |
| Kahneman et al., the peak-end rule (1993) | fixed | UX-S18 |
| Kivetz, Urminsky and Zheng (2006), the goal-gradient effect | fixed | UX-F27 |
| Hick (1952); Hyman (1953) | fixed | UX-P01 |
| von Restorff (1933), the isolation effect | fixed | UX-P03 |
| Wertheimer (1923), Gestalt principles | fixed | UX-P08 UX-P09 UX-P12 |
| Palmer (1992), common region | fixed | UX-P10 |
| Palmer and Rock (1994), uniform connectedness | fixed | UX-P11 |
| Fitts (1954) | fixed | UX-P13 |
| Cowan (2001), working-memory capacity — https://www.cambridge.org/core/journals/behavioral-and-brain-sciences/article/magical-number-4-in-shortterm-memory-a-reconsideration-of-mental-storage-capacity/44023F1147D4A1D44BDC0AD226838496 | fixed | UX-P15 |
| Murdock (1962) and earlier list-recall work, the serial position effect | fixed | UX-P16 |
| Kurosu and Kashimura (1995), the aesthetic-usability effect | fixed | UX-P18 |
| Nielsen (2000), Jakob's law | fixed | UX-P06 |
| RFC 761 (1980), Postel's robustness principle | fixed | UX-F11 |
| The UX laws in my CLAUDE.md, Adam Hayes, 2026-09-01 — the starting list, concept only | living | UX-P01 UX-P03 UX-P06 UX-P08 UX-P09 UX-P11 UX-P12 UX-P13 UX-P15 UX-P16 UX-S18 UX-S19 UX-F11 UX-F27 |
