# Attributions

This playbook stands on other people's work. Original content here is MIT-licensed
(see LICENSE); the portions below are adaptations of third-party works and remain
subject to their upstream licenses.

The **sync state** for these sources — which upstream ref each adaptation was last
reviewed against — is tracked in [UPSTREAMS.md](UPSTREAMS.md); run `/upstream-check`
to see what has moved since.

## skills/dg/ — adversarial review

Derived from **[dinesh-gilfoyle](https://github.com/v1r3n/dinesh-gilfoyle)** by
**[@v1r3n](https://github.com/v1r3n)**, licensed under
**[Apache License 2.0](https://github.com/v1r3n/dinesh-gilfoyle/blob/main/LICENSE)**.

Modifications in this repo: condensed the persona definitions; generalized the review
domains beyond code (architecture, product/business, decisions); added the optional
independent pre-review stage, convergence handling, and the merged-verdict output
format; parameterized project-specific behavior into local-extension sections.

## rules/engineering-principles.md — principles 1–4

Adapted from **[andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)**
by **multica-ai**, licensed under
**[MIT](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/LICENSE)** —
itself derived from **Andrej Karpathy's** public observations on LLM coding pitfalls.

Modifications in this repo: restructured into the five-principle format, reworded
bullets, added principle 5 ("Suggest Better Ways") as original content.

## skills/docs-lint/ — concept credit

The lint operation is inspired by the *lint* step of **Andrej Karpathy's**
[LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern.
The skill text is original; the idea that knowledge bases need periodic
contradiction/staleness checks by the LLM that maintains them is his.

## skills/ format

The skill-file conventions echo Anthropic's Claude Code skill/plugin format so the
files double as plugin skills; the workflows themselves are original or attributed
above.
