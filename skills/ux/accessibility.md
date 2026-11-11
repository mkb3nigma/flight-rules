# Accessibility

The default target is WCAG 2.2, level AA (W3C Recommendation, 12 December 2024). A
project can raise it in its extension file. Numbers in brackets are the success
criteria; read the criterion itself when a case is unclear: https://www.w3.org/TR/WCAG22/

These rules are the ones an interface most often fails. They are not the whole standard:
audio and video captions (1.2.x), for one, are not repeated here.

## Keyboard and focus

- **A1** [standard] Everything a pointer can do, the keyboard can do: every link,
  button, field, menu and custom control is reachable with Tab and operable with Enter,
  Space or the arrow keys its role expects. (2.1.1)
- **A2** [standard] Focus never gets stuck: a person can always Tab, or press Escape,
  out of a widget, a dialog or an embedded frame. (2.1.2)
- **A3** [standard] The focus order follows the reading order of the layout; a
  positive `tabindex` is a finding. (2.4.3)
- **A4** [standard] The focused element is always visibly marked; removing the focus
  outline without a replacement is a finding. (2.4.7)
- **A5** [standard] A focused element is never wholly hidden behind a sticky header,
  footer or banner. (2.4.11)
- **A6** [standard] A dialog moves focus into itself when it opens and back to the
  control that opened it when it closes. (2.4.3)
- **A7** [standard] A repeated block — the site navigation — can be skipped: a "skip to
  content" link, or landmarks a screen reader can jump between. (2.4.1)

## Seeing it

- **A8** [standard] Text contrasts with its background at least 4.5:1; large text —
  at least 18 point, or 14 point bold — at least 3:1. Check the real colours with a
  contrast checker; do not judge by eye. (1.4.3)
- **A9** [standard] The parts of a control needed to see it — a field's border, a
  checkbox, a focus ring — and meaningful graphics contrast with what is next to them at
  least 3:1. (1.4.11)
- **A10** [standard] Colour is never the only signal: an error, a required field, a
  status, a link inside text also has text, an icon or an underline. (1.4.1)
- **A11** [standard] Text resizes to 200% without anything cut off or overlapping.
  (1.4.4)
- **A12** [standard] At 320 CSS pixels wide the page scrolls in one direction only:
  no sideways scrolling for text, except tables, maps and the like. (1.4.10)
- **A13** [standard] Layout survives a person's own text spacing: line height 1.5 times
  the font size, paragraph spacing 2 times, letter spacing 0.12 times, word spacing
  0.16 times. Fixed-height text boxes are where this breaks. (1.4.12)
- **A14** [standard] Content shown on hover or focus — a tooltip, a submenu — can be
  dismissed without moving the pointer (Escape), stays while the pointer moves onto it,
  and stays until dismissed or no longer relevant. (1.4.13)
- **A15** [standard] Text is text, not an image of text, except a logo. (1.4.5)
- **A16** [standard] The layout works in both portrait and landscape; do not lock the
  orientation unless it is essential. (1.3.4)

## Names, roles and structure

- **A17** [standard] Every image that carries meaning has a text alternative saying
  what it conveys; a decorative image has an empty one (`alt=""`). (1.1.1)
- **A18** [standard] Every control has an accessible name a screen reader announces.
  An icon-only button gets one (`aria-label`, or visually hidden text). (4.1.2)
- **A19** [standard] A control's visible label is part of its accessible name, so a
  person who speaks the label can operate it. (2.5.3)
- **A20** [standard] Use the native element for its job — `button`, `a`, `input`,
  `select`, `label` — before a `div` with a role. A custom widget declares its role and
  states (expanded, selected, checked) and keeps them current. (4.1.2)
- **A21** [standard] Headings, lists, tables and form groups are marked up as such, so
  structure seen on screen is structure a screen reader gets. (1.3.1)
- **A22** [standard] Headings and labels say what follows them. (2.4.6)
- **A23** [standard] Each page has a title saying what it is, and the page declares its
  language. (2.4.2, 3.1.1)
- **A24** [standard] A link's purpose is clear from its text, or from its text and its
  sentence; "click here" alone is a finding. (2.4.4)
- **A25** [standard] A status message — "Saved", "3 results", an error count — is
  announced without moving focus to it (`role="status"` or `role="alert"`). (4.1.3)

## Pointer, motion and time

- **A26** [standard] A pointer target is at least 24 by 24 CSS pixels, or has no other
  target within a 24-pixel circle centred on it. (2.5.8)
- **A27** [standard] Anything done by dragging can also be done with single clicks or
  taps. (2.5.7)
- **A28** [standard] Anything done with a multi-point or path gesture (pinch, swipe a
  shape) can also be done with a single pointer. (2.5.1)
- **A29** [standard] Moving, blinking or scrolling content that starts by itself and
  lasts more than five seconds can be paused, stopped or hidden. (2.2.2)
- **A30** [standard] Nothing flashes more than three times in any one second. (2.3.1)
- **A31** [standard] A time limit can be turned off, or adjusted to at least ten times
  its default, or the person is warned before it runs out, given at least 20 seconds to
  extend it with a simple action, and can extend it at least ten times. (2.2.1)
- **A32** [rule of thumb] Respect the person's reduced-motion setting
  (`prefers-reduced-motion`): replace movement with a fade or nothing.

## Predictable behaviour

- **A33** [standard] Focusing a control, or changing a setting in it, does not by
  itself submit a form, open a new window or move the person elsewhere. (3.2.1, 3.2.2)
- **A34** [standard] Navigation repeated across pages stays in the same order, and a
  component that does the same thing has the same name everywhere. (3.2.3, 3.2.4)
- **A35** [standard] Help — contact details, a help link, a chat — that repeats across
  pages comes in the same order relative to the rest of the page on each. (3.2.6)
