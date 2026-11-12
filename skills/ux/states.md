# States and feedback

An interface built for the happy path shows nothing useful the moment data is slow,
empty, partial or wrong. Every screen, list and action is designed in each state it can
be in, not only the one with data.

Response-time sources: Nielsen Norman Group, *Response Times: The 3 Important Limits*
(after Miller 1968 and Card et al. 1991),
https://www.nngroup.com/articles/response-times-3-important-limits/ ; for the web,
the Core Web Vitals responsiveness threshold,
https://web.dev/articles/defining-core-web-vitals-thresholds

## Every state, drawn

- **UX-S01** [rule of thumb] Each screen or component that shows data is designed in five
  states: empty, loading, partial (some data, or some failed), error, and success. A
  review lists any state that was not built.
- **UX-S02** [rule of thumb] An empty state says what will appear there and how to make the
  first one — a button to create it, or a line on how it fills — not a blank area or a
  bare "No data".
- **UX-S03** [rule of thumb] An empty result from a search or filter says so in words,
  shows what was searched for, and offers a way out: clear the filter, check the
  spelling, broaden the search.
- **UX-S04** [rule of thumb] An error state says what failed, in the person's terms, and
  what they can do: retry, go back, or contact someone. A stack trace, an error code
  alone, or "Something went wrong" alone is a finding.
- **UX-S05** [rule of thumb] A partial failure is shown as partial: the items that loaded
  are shown, and the ones that did not are marked, with a retry for those alone.
- **UX-S06** [rule of thumb] Loading keeps the layout's shape — a skeleton or a reserved
  area — so content does not jump when it arrives.

## How fast, and what to show while waiting

- **UX-S07** [finding] A response within about 0.1 second feels instant and needs no
  feedback beyond the result.
- **UX-S08** [finding] Up to about 1 second, the person's flow of thought holds; past
  1 second, show that work is happening — a busy indicator on the control or the area.
- **UX-S09** [finding] Past about 10 seconds, attention is lost: show progress — a
  percent-done bar where the work can be measured, or what is being done now where it
  cannot — and a way to cancel.
- **UX-S10** [rule of thumb] On the web, Google's Core Web Vitals count an interaction's
  next paint within 200 ms as good responsiveness, and over 500 ms as poor (Interaction
  to Next Paint, at the 75th percentile of real visits). Google's threshold, not a
  standard: a page over it is slow, not non-conforming.
- **UX-S11** [rule of thumb] Show a busy indicator only after a short delay (a few hundred
  milliseconds), so fast responses do not flicker.

## Never leave the person unsure

- **UX-S12** [rule of thumb] Every action is acknowledged where the person is looking: a
  pressed state on the button, then the result or a message beside it. A save that
  succeeds silently is a finding.
- **UX-S13** [rule of thumb] A button that starts work is disabled, or shows it is busy,
  until the work ends, so a second click does not submit twice.
- **UX-S14** [rule of thumb] Success says what happened in specific terms — "Invoice 104
  sent to ana@example.com" — and, where it matters, what happens next.
- **UX-S15** [rule of thumb] An optimistic update (showing the result before the server
  confirms) is used only where a failure can still be shown and the change undone; on
  failure the interface rolls back and says so.
- **UX-S16** [rule of thumb] A message that matters is not shown only in a toast that
  vanishes: an error stays until dismissed or fixed; a toast suits only a confirmation
  the person can also see elsewhere.
- **UX-S17** [rule of thumb] Work in progress survives a reload or a lost connection where
  the platform allows — a draft saved as it goes — and the interface says when it is
  offline.

## Ending well

- **UX-S18** [finding] A flow ends on a clear completion: what was done, and what happens
  next. People judge an experience largely by its most intense moment and its end
  (Kahneman's peak-end rule, measured on experiences of pain and discomfort; applied
  to interface flows by extrapolation); an end that is a blank page or an unexplained
  redirect costs more than its size suggests.
- **UX-S19** [finding] An interrupted task is shown so it can be resumed — "You have an
  unfinished order" — because people tend to return to interrupted work (the Ovsiankina
  effect). It is not used to nag: the claimed memory advantage for unfinished tasks
  (the Zeigarnik effect) did not hold up in a 2025 meta-analysis (Ghibellini and Meier,
  *Humanities and Social Sciences Communications* 12).
