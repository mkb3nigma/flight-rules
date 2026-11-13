# Basic principles

The long-established findings behind most interface advice, each with its limit. Several
are popularly called "laws"; few are laws. The kind tells you how far to trust one: a
`[finding]` was measured, a `[rule of thumb]` is practice. For what to build first: a
few features usually carry most of the use (the Pareto principle, a rough regularity),
so make those fast and obvious before polishing the rest — a note on priorities, not a
rule a finding cites.

## Choice

- **UX-P01** [finding] The time to choose grows with the number of options (Hick 1952,
  Hyman 1953): show fewer at once, put rare options behind an "advanced" step, and
  break a hard decision into steps. The limit: it holds for picking among similar,
  unfamiliar options, not for scanning a familiar or ordered list — a long
  alphabetical list of countries is fine.
- **UX-P02** [rule of thumb] Each screen has one purpose and one primary action, made
  visibly the most prominent; secondary actions look secondary. With two that look
  primary, the person has to stop and work out which one moves them on.
- **UX-P03** [finding] The item that differs is the one noticed (the isolation, or Von
  Restorff, effect, 1933): use emphasis for the one thing that matters on a screen.
  Emphasise everything and nothing stands out.
- **UX-P04** [rule of thumb] Where the person may not know which option to pick, recommend
  one and say why.
- **UX-P05** [rule of thumb] Complexity that cannot be removed is carried by the system,
  not handed to the person — compute it, default it, infer it (Tesler's law of
  conservation of complexity).

## Familiarity

- **UX-P06** [rule of thumb] People spend most of their time on other products, and expect
  yours to work the same way (Jakob's law, Nielsen 2000): a logo that links home, a
  search box with a magnifying glass, a cart top right, standard form controls. Depart
  from a convention only for a reason worth the relearning.
- **UX-P21** [rule of thumb] The browser's Back returns to the view the person took to be
  the previous one: it closes an overlay that looked like a page, undoes a filter or
  sort, goes back one step. A view worth returning to or sending to someone — a record,
  a tab, a filtered or sorted list, a page of results — has its own URL, and a reload or
  a pasted link restores it. State held only in memory is where this breaks. People
  take an overlay for a new page and press Back to close it (Nielsen Norman Group,
  *User Control and Freedom*); 59% of e-commerce sites in Baymard's benchmark got at
  least one such Back expectation wrong (measured on shops).
- **UX-P07** [rule of thumb] Within the product, the same thing looks and behaves the same
  everywhere: the project's design record decides how. Where it differs, a person
  carries what they learned on one screen to another and is wrong.
- **UX-P20** [rule of thumb] What a person reads is in their terms, not the system's: a
  label, not an enum or column name (`PENDING_REVIEW`); a name, not an ID; dates, times
  and numbers in the person's format, not ISO strings or raw `true` and `false`
  (Nielsen's heuristic 2, *match between the system and the real world*).

## Grouping and layout

From Gestalt psychology (Wertheimer 1923, and later work):

- **UX-P08** [finding] Things close together are seen as related (proximity): space
  between groups larger than space within them. Spacing is the cheapest grouping there
  is.
- **UX-P09** [finding] Things that look alike are taken to work alike (similarity): give
  things that behave the same the same look, and things that behave differently a
  different one. A link styled like a heading is a finding.
- **UX-P10** [finding] A shared background or border binds what is inside it into a group
  (common region, Palmer 1992).
- **UX-P11** [finding] Things joined by a line or connector are seen as one group, often
  overriding closeness or likeness (uniform connectedness, Palmer and Rock 1994):
  steps in a progress bar, a label linked to its value.
- **UX-P12** [finding] People read a layout in the simplest shape it can have
  (Prägnanz): aligned edges, a few consistent sizes and a clear grid read as order;
  near-misses — 13 px here, 15 px there — read as mistakes.

## Pointing

- **UX-P13** [finding] The time to hit a target grows with its distance and shrinks with
  its size (Fitts 1954): make frequent and primary targets
  large, and put them near where the pointer or thumb already is. The edges and corners
  of a screen are easy targets for a mouse, hard ones for a thumb.

## Memory and attention

- **UX-P15** [finding] Working memory holds a few chunks at once — about three to five
  for young adults (Cowan 2001), revising the "seven, plus or minus two" often quoted
  from Miller 1956. Design for recognition over recall: show what the person chose on
  one screen when they need it on the next, and group long numbers and lists into
  chunks. Never use this number to size a menu.
- **UX-P16** [rule of thumb] People remember the first and last items of a sequence best
  (the serial position effect): put the most important navigation items first and
  last. Applying it to menus is an extrapolation from list recall; treat it as a
  tiebreaker.

## Judging your own work

- **UX-P18** [finding] An attractive interface is judged easier to use than it is (the
  aesthetic-usability effect, Kurosu and Kashimura 1995): when a design looks good, check
  it against these rules anyway — looking good is when problems are missed.
