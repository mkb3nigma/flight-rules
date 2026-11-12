# Forms and input

Forms are where a person's work is most easily lost, and where most accessibility
failures sit. WCAG numbers in brackets: https://www.w3.org/TR/WCAG22/

## Labels and instructions

- **UX-F01** [standard] Every field has a visible label, tied to it in the markup
  (`<label for>`). (3.3.2, 1.3.1) Outside the field is the practice beyond the
  criterion: a placeholder is not a label, since it disappears as the person types.
- **UX-F02** [standard] A requirement is stated before the input, not only in the error
  after it: required fields, formats ("DD/MM/YYYY"), limits ("8 or more characters").
  (3.3.2)
- **UX-F03** [rule of thumb] Mark required fields — or, where most are required, mark the
  optional ones — and say once which convention the form uses.
- **UX-F04** [standard] Fields that collect personal data — name, email, address, phone,
  card details — declare their purpose (`autocomplete="email"` and the like), so the
  browser can fill them. (1.3.5)
- **UX-F05** [rule of thumb] Use the input type the value needs (`email`, `tel`, `number`
  only for quantities, `date` or a picker), so phones show the right keyboard.
- **UX-F06** [rule of thumb] Related fields are grouped with a heading or a `fieldset` and
  `legend`: an address, a set of radio buttons, a card's details. Ungrouped, a screen
  reader announces each radio button with no question it answers.

## Choices and defaults

- **UX-F07** [rule of thumb] A sensible default wherever one exists — the country from the
  locale, today's date, the most common option — so the person changes it only when it
  is wrong.
- **UX-F08** [rule of thumb] Up to about five mutually exclusive options are radio buttons,
  all visible; more is a select or a searchable list. A yes/no choice that applies at
  once is a switch; one submitted with a form is a checkbox.
- **UX-F09** [standard] Information already given in the same process is filled in or
  offered again, not asked for twice — "shipping address same as billing". (3.3.7)
- **UX-F10** [rule of thumb] Ask only for what is needed now. Every optional field is a
  question to the person: is it worth asking?

## Tolerant input

- **UX-F11** [rule of thumb] Accept the forms people actually type and normalise them:
  spaces or dashes in a card or phone number, a trailing space after a pasted email,
  upper or lower case in a code. Be strict in what is stored and shown back, not in what
  is accepted (Postel's robustness principle, RFC 761, from network protocols; scoped
  here to input from people — in protocol design it is now contested).
- **UX-F12** [rule of thumb] Do not block paste — into a password field, a code field or
  any other.
- **UX-F13** [standard] Signing in does not require remembering or transcribing something
  — solving a puzzle, retyping a code by hand — unless another way exists: paste,
  a password manager, a link sent by email. (3.3.8)

## Errors

- **UX-F14** [standard] An error names the field and describes the problem in text, not
  only by colour or an icon. (3.3.1, 1.4.1)
- **UX-F15** [standard] Where the fix is known, the error says it: "Enter a date after
  today", not "Invalid date". (3.3.3)
- **UX-F16** [rule of thumb] The error sits next to the field, and on submit a summary at
  the top lists every error with a link to each field; focus moves to the summary or to
  the first error.
- **UX-F17** [rule of thumb] An error keeps everything the person entered — every field,
  not only the valid ones. Losing input on an error is a Major finding.
- **UX-F18** [rule of thumb] Validate a field when the person leaves it or submits, not on
  every keystroke while they are still typing it; clear the error as soon as it is
  fixed.
- **UX-F19** [rule of thumb] A disabled submit button that never says why is a dead end:
  leave it enabled and show the errors on submit, or say beside it what is missing.

## Consequences

- **UX-F20** [standard] Where submitting creates a legal or financial commitment, or
  changes or deletes the person's data, it can be undone, or is checked with a chance to
  correct it, or the person reviews and confirms before it is final. (3.3.4)
- **UX-F21** [rule of thumb] Prefer undo to confirmation for a destructive action: delete,
  then offer "Undo" for some seconds. Where undo is not possible, the confirmation names
  what will be lost ("Delete project Atlas and its 12 files?") and its button repeats
  the action ("Delete project"), not "OK".
- **UX-F22** [rule of thumb] A destructive action is never the default button, does not
  sit where the safe action usually is, and is kept away from the control used most
  often: distance prevents the slip that a large target invites.
- **UX-F23** [rule of thumb] Leaving a form with unsaved changes warns the person, or the
  form saves a draft as it goes.

## Long forms

- **UX-F24** [rule of thumb] A long form is split into steps of related fields, each
  short enough to finish without scrolling far.
- **UX-F27** [finding] A form in steps shows the steps and marks the current one: people
  work faster as a visible goal gets nearer (the goal-gradient effect, Kivetz, Urminsky
  and Zheng 2006, measured on reward programmes; applied to forms by extrapolation).
- **UX-F25** [rule of thumb] Each step can be reviewed and changed before the final
  submit, and going back does not lose what was entered.
- **UX-F26** [rule of thumb] A single column of fields, read top to bottom, unless the
  fields are short and belong together on one line (city, postcode). Side by side, a
  field is skipped by an eye that reads down.
