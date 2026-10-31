# /dg comic — the page and the PNG, on request only

Read by `/dg` step 6 only when the person asks for the comic as a page or a PNG. The
ASCII comic, its panels and its tags are step 6's.

If the person asks for the comic as a page, fill `comic-template.html` beside this
file with the same panels as the ASCII comic; a copy of this skill without it says so.
- `{{REVIEW_TARGET}}`, `{{ROUND_COUNT}}`, `{{GILFOYLE_SCORE}}`, `{{DINESH_SCORE}}`,
  `{{DATE}}` from the review.
- `{{PANELS}}`: the text comic's panels, from the banter — back-and-forth pairs, a rare Gilfoyle
  concession, the most technically devastating lines — 1–3 sentences each:
  `<div class="panel gilfoyle|dinesh [full-width]"><span class="panel-number">N</span><div class="panel-header"><div class="avatar"><svg><use href="#gilfoyle-avatar|#dinesh-avatar"/></svg></div>GILFOYLE|DINESH</div><div class="panel-body"><div class="speech">…</div></div></div>`.
- `{{VERDICT_ITEMS}}`: one per verdict finding, tagged by its verdict section —
  AGREED (both flagged), CONTESTED (severity disputed, or a defence held), DISMISSED:
  `<div class="verdict-item"><span class="tag tag-agreed|tag-contested|tag-dismissed">AGREED|CONTESTED|DISMISSED</span> …</div>`.
  Nothing is FIXED when the comic is drawn: the reviewers are read-only.

HTML-escape every piece of text before it goes in (`&`, `<`, `>`, `"`) — the target,
the date and scores, each quote inside a `speech` div, each verdict item's text after
its tag — and never the wrapper markup above, which is the template's own and would
print as tags. All of that text comes from the subject under review, and an unescaped
`<script>` in a diff would run when the page opens. The template's
Content-Security-Policy stops scripts, forms and a `<base>` as a second line, but not
a `<meta http-equiv="refresh">`, which still navigates the page (headless Edge,
2026-10-17): escaping is the control, not the CSP. Write
it to a fresh file (`mktemp -t dg-comic.XXXXXX`, renamed `.html`), give the path, and
open it (`open`, or `xdg-open`). Asked for a PNG, render one with a headless browser
already installed — any Chromium (Chrome, Chromium, Edge; on macOS the binary inside
its `.app/Contents/MacOS/`) with `--headless --screenshot=<png> --window-size=1200,2400
file://<html>`, or `wkhtmltoimage`; never `npx --yes` — and give its path. The page
and the PNG stay local: a PR gets the ASCII comic, under `DG_COMIC_PR`.
