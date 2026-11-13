# Accessibility

The default target is WCAG 2.2, level AA (W3C Recommendation, 12 December 2024). A
project can raise it in its extension file. Numbers in brackets are the success
criteria; read the criterion itself when a case is unclear: https://www.w3.org/TR/WCAG22/

These rules are the ones an interface most often fails. They are not the whole standard:
no rule here covers 1.2.1–1.2.5 (audio and video), 1.4.2, 2.4.5, 2.5.4 or 3.1.2, and
1.3.5, 3.3.1–3.3.4, 3.3.7 and 3.3.8 are in `forms.md`. A report says AA was checked only
for the rules it loaded, and never that the interface meets WCAG AA.

## Keyboard and focus

- **UX-A01** [standard] Everything a pointer can do, the keyboard can do: every link,
  button, field, menu and custom control is reachable with Tab and operable with Enter,
  Space or the arrow keys its role expects; a control that hover reveals, focus reveals
  too. (2.1.1, failure F54) The practice beyond it: touch reveals that control too, as a
  touch screen cannot hover, or not conveniently (MDN, `hover`); other content hover
  reveals, focus (Understanding 1.4.13) and touch reveal as well, except a `title` tooltip.
- **UX-A02** [standard] Focus never gets stuck: a person can always Tab, or press Escape,
  out of a widget or an embedded frame, and leaves a dialog by closing it — Escape or its
  close control — not by tabbing out, which a modal dialog does not allow (UX-A06).
  (2.1.2)
- **UX-A03** [standard] The focus order preserves meaning and operation: in practice, the
  reading order of the layout. (2.4.3) A positive `tabindex` is where it usually breaks.
  Where order carries meaning, the markup order is the reading order, and CSS
  positioning that changes the meaning fails it. (1.3.2, failure F1) Practice beyond it:
  markup and screen order the same throughout (technique C27), which `order` or a
  reversed flex row breaks.
- **UX-A04** [standard] The focused element is always visibly marked; removing the focus
  outline without a replacement is a finding. (2.4.7)
- **UX-A05** [standard] A focused element is never wholly hidden behind a sticky header,
  footer or banner. (2.4.11)
- **UX-A06** [standard] A dialog moves focus into itself when it opens. (2.4.3) Practice
  beyond the criterion (ARIA Authoring Practices, modal dialog): while a modal dialog is
  open, Tab and Shift+Tab stay inside it, Escape closes it, the page behind cannot be
  operated, and it has a name — its title, through `aria-labelledby`. A native `dialog`
  opened with `showModal()` makes the page behind inert and closes on Escape; its name
  is still the author's to give. Also practice: when a dialog closes or the focused item
  is deleted, focus goes to the control that opened it or the next item, not the page
  body (Authoring Practices, keyboard interface); when the view changes without a page
  load, to the new view's heading (this guide's own practice).
- **UX-A07** [standard] A repeated block — the site navigation — can be skipped: a "skip to
  content" link, or landmarks a screen reader can jump between. (2.4.1)
- **UX-A38** [standard] A keyboard shortcut made only of printable characters — letters,
  digits, punctuation, symbols, with or without Shift — can be turned off, remapped to
  include a non-printable key (Ctrl, Alt; not Shift), or works only while its control
  has focus. (2.1.4)

## Seeing it

- **UX-A08** [standard] Text contrasts with its background at least 4.5:1; large text —
  at least 18 point, or 14 point bold — at least 3:1. Check the real colours with a
  contrast checker; do not judge by eye. (1.4.3)
- **UX-A09** [standard] The parts of a control needed to see it — a field's border, a
  checkbox, a focus ring — and meaningful graphics contrast with what is next to them at
  least 3:1. (1.4.11)
- **UX-A10** [standard] Colour is never the only signal: an error, a required field, a
  status, a link inside text also has text, an icon or an underline. (1.4.1) An
  instruction names the thing it points at, never only its colour, shape, size,
  position or sound: "press Save", not "the round button" or "the panel on the right".
  (1.3.3)
- **UX-A11** [standard] Text resizes to 200% without anything cut off or overlapping.
  (1.4.4) A viewport tag with `user-scalable=no`, or `maximum-scale` below 2, is a
  finding under 1.4.4, unless the page gives another way to enlarge its text (ACT rule
  b4f0c3, *Meta viewport allows for zoom*).
- **UX-A12** [standard] At 320 CSS pixels wide the page scrolls in one direction only:
  no sideways scrolling for text, except tables, maps and the like. (1.4.10) The practice
  beyond it: a wide table scrolls in its own container, so the content around it can
  still reflow (Understanding 1.4.10).
- **UX-A13** [standard] Layout survives a person's own text spacing: line height 1.5 times
  the font size, paragraph spacing 2 times, letter spacing 0.12 times, word spacing
  0.16 times. Fixed-height text boxes are where this breaks. (1.4.12)
- **UX-A14** [standard] Content shown on hover or focus — a tooltip, a submenu — can be
  dismissed without moving the pointer or focus (Escape), unless it reports an input
  error or covers nothing; stays while the pointer moves onto it; and stays until the
  pointer or focus leaves the trigger, the person dismisses it, or it is no longer
  valid. Content the browser draws and the page does not style — a `title` tooltip — is
  exempt. (1.4.13)
- **UX-A15** [standard] Text is text, not an image of text, except a logo. (1.4.5)
- **UX-A16** [standard] The layout works in both portrait and landscape; do not lock the
  orientation unless it is essential. (1.3.4)

## Names, roles and structure

- **UX-A17** [standard] Every image that carries meaning has a text alternative saying
  what it conveys; a decorative image has an empty one (`alt=""`). (1.1.1)
- **UX-A18** [standard] Every control has an accessible name a screen reader announces.
  An icon-only button gets one (`aria-label`, or visually hidden text). (4.1.2)
- **UX-A19** [standard] A control's visible label is part of its accessible name, so a
  person who speaks the label can operate it. (2.5.3)
- **UX-A20** [standard] A custom widget declares its role and states (expanded, selected,
  checked) and keeps them current. (4.1.2)
- **UX-A36** [rule of thumb] Use the native element for its job — `button`, `a`, `input`,
  `select`, `label` — before a `div` with a role: it brings its role, states and
  keyboard handling with it. A role promises its keyboard behaviour: a custom widget
  given a role — tabs, a menu, a combobox — is built to that role's pattern in the ARIA
  Authoring Practices, or is not given the role (Authoring Practices, *Read Me First*).
- **UX-A21** [standard] Headings, lists, tables and form groups are marked up as such, so
  structure seen on screen is structure a screen reader gets. (1.3.1) A data table's
  header cells are `th`, with `scope` set where a header's direction is not obvious, and
  a sortable column's sort state is in the markup — `aria-sort` on the sorted column's
  header, for example — or in the header's text, not only shown (WAI tables tutorial;
  Authoring Practices, sortable table).
- **UX-A22** [standard] Headings and labels say what follows them. (2.4.6)
- **UX-A23** [standard] Each page has a title saying what it is, and the page declares its
  language. (2.4.2, 3.1.1) The practice beyond them: where a view changes without a
  page load, as in a single-page app, the title changes with it (Understanding 2.4.2).
- **UX-A24** [standard] A link's purpose is clear from its text, or from its text and its
  sentence; "click here" alone is a finding. (2.4.4)
- **UX-A25** [standard] A status message — "Saved", "3 results", an error count — is
  announced without moving focus to it (`role="status"` or `role="alert"`). (4.1.3)

## Pointer, motion and time

- **UX-A26** [standard] A pointer target is at least 24 by 24 CSS pixels, except one spaced
  so that a 24-pixel-diameter circle centred on it meets no other target and no other
  small target's circle; one in a sentence, or whose size the line height of the text
  around it sets; one whose function another control on the same page offers at that
  size; one the browser sizes and the page does not style; and one whose size is
  essential or legally required. (2.5.8)
- **UX-A27** [standard] Anything done by dragging can also be done with single clicks or
  taps. (2.5.7)
- **UX-A28** [standard] Anything done with a multi-point or path gesture (pinch, swipe a
  shape) can also be done with a single pointer. (2.5.1)
- **UX-A37** [standard] A control acts when the pointer is released, not when it is
  pressed, so a person who presses the wrong one can slide off it: `click`, not
  `mousedown`, `pointerdown` or `touchstart` (failure F101; native controls already do
  this, G212). A drag may start on the press if it completes on release and can be
  abandoned — dropped back, or released outside a target — or undone; otherwise acting
  on the press is only for what the release reverses, or where it is essential. (2.5.2)
- **UX-A29** [standard] Moving, blinking or scrolling content that starts by itself and
  lasts more than five seconds can be paused, stopped or hidden; content that updates by
  itself can be paused, hidden, or slowed. (2.2.2)
- **UX-A30** [standard] Nothing flashes more than three times in any one second. (2.3.1)
- **UX-A31** [standard] A time limit can be turned off, or adjusted to at least ten times
  its default, or the person is warned before it runs out, given at least 20 seconds to
  extend it with a simple action, and can extend it at least ten times. (2.2.1)
- **UX-A32** [rule of thumb] Respect the person's reduced-motion setting
  (`prefers-reduced-motion`): replace movement with a fade or nothing.

## Predictable behaviour

- **UX-A33** [standard] Focusing a control, or changing a setting in it, does not by
  itself submit a form, open a new window or move the person elsewhere. (3.2.1, 3.2.2)
- **UX-A34** [standard] Navigation repeated across pages stays in the same order, and a
  component that does the same thing has the same name everywhere. (3.2.3, 3.2.4)
- **UX-A35** [standard] Help — contact details, a help link, a chat — that repeats across
  pages comes in the same order relative to the rest of the page on each. (3.2.6)
