#!/usr/bin/env bash
# Do this repo's DOCUMENTS agree with each other, with .ai/flight-rules.conf, and with CI?
#
# Every other suite tests code. Three findings in the 0.22.0 release candidate were not
# code — they were prose in CLAUDE.md, skills/pr-create/SKILL.md and
# rules/git-worktree-workflow.md, each individually written, contradicting each other only
# in combination. 861 test cases, a 810-verdict differential and a cross-family review on
# every PR could not see them, because nothing read two documents at once.
#
# Only what is MECHANICALLY checkable lives here. "Does this sentence still describe the
# behaviour" is judgement and stays with pre-merge-check item 17; pretending otherwise
# would give a green suite and a false sense of coverage. What is checkable is agreement
# between a value stated in one place and the same value stated in another.
#
# Run: ./docs-consistency.test.sh (no args, no network, reads only).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }

CONF=.ai/flight-rules.conf
[ -r "$CONF" ] || { printf '  ❌ harness: %s is not readable — nothing below was tested\n' "$CONF" >&2; exit 2; }
conf() { sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"[:space:]#]+)\"?.*$/\1/p" "$CONF" | tail -1; }

PROTECTED=$(conf PROTECTED_BRANCHES)
PR_ONLY=$(conf PR_ONLY_BRANCHES)
NOTE_GATED=$(conf NOTE_GATED_BRANCHES)
INTEGRATION=$(conf INTEGRATION_BRANCH)
WORKTREE=$(conf WORKTREE_DIR)
[ -n "$INTEGRATION" ] || { printf '  ❌ harness: no INTEGRATION_BRANCH in %s\n' "$CONF" >&2; exit 2; }

echo "CLAUDE.md's parameter table states the values the hooks actually read:"
# The table is the first thing an assistant reads about this repo, and it is a COPY of the
# conf. A copy that drifts sends every session down the wrong workflow while every hook
# enforces the right one.
tablerow() { sed -n -E "s/^\| \`\{$1\}\` \| (.*) \|$/\1/p" CLAUDE.md | head -1; }
# Keys and values in two index-aligned lists, NOT packed into one "key|value" string:
# every value here is a regex that CONTAINS `|`, so `${pair##*|}` strips to the last one
# and `^(main|dev)$` arrives as `dev`. That made this very check pass without ever looking
# at `main` — caught 2026-09-14 by reading its own output, before it was committed.
CKEY=(  PROTECTED_BRANCHES PR_ONLY_BRANCHES NOTE_GATED_BRANCHES INTEGRATION_BRANCH )
CVAL=( "$PROTECTED"       "$PR_ONLY"       "$NOTE_GATED"       "$INTEGRATION"      )
i=0
while [ $i -lt ${#CKEY[@]} ]; do
  key="${CKEY[$i]}"; val="${CVAL[$i]}"; i=$((i+1))
  row=$(tablerow "$key")
  [ -n "$val" ] || continue                     # key absent from the conf: nothing to agree with
  if [ -z "$row" ]; then
    bad "CLAUDE.md's table has no row for {$key}, which the conf sets to $val"
    continue
  fi
  # The row is prose. Every branch name in the regex must appear somewhere in it.
  missing=""
  for b in $(printf '%s' "$val" | tr -d '^$()' | tr '|' ' '); do
    case "$b" in ""|"*") continue ;; esac
    grep -qF -- "$b" <<<"$row" || missing="$missing $b"
  done
  if [ -n "$missing" ]; then
    bad "CLAUDE.md's {$key} row does not mention:$missing (conf says $val)"
  else
    ok "{$key} — table and conf agree on:$(printf '%s' "$val" | tr -d '^$()' | tr '|' ' ' | sed 's/^/ /')"
  fi
done

echo "The worktree directory in the table is the one the hooks use:"
if grep -qF -- "$WORKTREE" <<<"$(tablerow WORKTREE_DIR)"; then
  ok "{WORKTREE_DIR} — $WORKTREE"
else
  bad "CLAUDE.md's {WORKTREE_DIR} row does not mention $WORKTREE"
fi

echo "{TEST_COMMANDS} lists every suite that exists, and only those:"
# session-start.test.sh was written on 2026-09-12 and had to be added here, to CI and to
# hooks/README.md by hand. A suite nobody runs is a suite that rots.
ON_DISK=$(find . -name '*.test.sh' -not -path './.ai/*' | sed 's|^\./||' | sort)
LISTED=$(sed -n -E 's/^\| `\{TEST_COMMANDS\}` \| (.*)$/\1/p' CLAUDE.md \
         | grep -oE '[A-Za-z0-9_./-]+\.test\.sh' | sort -u)
for f in $ON_DISK; do
  grep -qxF "$f" <<<"$LISTED" || bad "$f exists but {TEST_COMMANDS} does not list it — nothing runs it"
done
for f in $LISTED; do
  [ -f "$f" ] || bad "{TEST_COMMANDS} lists $f, which is not there"
done
[ "$ON_DISK" = "$LISTED" ] && ok "$(printf '%s\n' "$ON_DISK" | grep -c .) suites, all listed, none missing"

echo "CI runs every suite in {TEST_COMMANDS}:"
CI=.github/workflows/tests.yml
if [ ! -r "$CI" ]; then
  bad "$CI is not readable"
else
  for f in $LISTED; do
    grep -qF -- "$f" "$CI" || bad "$f is in {TEST_COMMANDS} but CI never runs it"
  done
  ok "all $(printf '%s\n' "$LISTED" | grep -c .) listed suites appear in $CI"

  # A branch that moves by LOCAL merge is never covered by a pull_request event. dev was
  # pushed untested for two days under a CLAUDE.md that claimed CI on both branches.
  if grep -qE '^ *branches: \[.*\b'"$INTEGRATION"'\b.*\]' "$CI"; then
    ok "CI triggers on a push to the integration branch ($INTEGRATION)"
  else
    bad "CI has no push trigger for $INTEGRATION — it moves by local merge, which no pull_request event covers"
  fi
fi

echo "The skill that opens PRs can open the one this project needs:"
# pr-create forbids a PR whose head is protected. On a two-branch project the integration
# branch is usually protected too — so without an explicit exception the skill forbids the
# release PR it defines. Found on 2026-09-14, by trying to do the release.
SK=skills/pr-create/SKILL.md
if [ -n "$PROTECTED" ] && [ "$PROTECTED" != "off" ] && [ "$PROTECTED" != "none" ] \
   && ( [[ "$INTEGRATION" =~ $PROTECTED ]] ) 2>/dev/null; then
  if grep -q 'except the release PR' "$SK"; then
    ok "$INTEGRATION is protected, and pr-create names the release-PR exception"
  else
    bad "$INTEGRATION is protected and is the PR head for a release, but pr-create's protected-head rule has no exception — the skill forbids the release it describes"
  fi
else
  ok "the integration branch is not protected; no exception needed"
fi

echo "A release has somewhere to put the version bump:"
# The bump cannot land on a protected integration branch directly, and the promotion PR's
# head IS that branch — so unless a release branch is documented, there is no legal place
# for it. The first promotion attempt is what found this.
if [ -n "$PROTECTED" ] && [ "$PROTECTED" != "off" ] && [ "$PROTECTED" != "none" ] \
   && ( [[ "$INTEGRATION" =~ $PROTECTED ]] ) 2>/dev/null; then
  if grep -qiE 'chore/release|release branch' CLAUDE.md; then
    ok "CLAUDE.md documents where the version bump is committed"
  else
    bad "$INTEGRATION is protected, so the bump cannot be committed on it — and CLAUDE.md names no release branch"
  fi
else
  ok "the bump can be committed on the integration branch directly"
fi

echo "The release review check the docs describe exists, and re-runs on a body edit:"
# CLAUDE.md, pr-create and the CHANGELOG name a `release review` check (step 2b); a doc
# promising a check no file runs is the drift this suite is for (fix review, 2026-10-12).
RR=.github/workflows/release-review.yml
if [ ! -f "$RR" ]; then bad "$RR is missing — step 2b's check does not run"
else
  grep -q 'edited' "$RR" && ok "$RR re-runs when the PR body is edited" || bad "$RR does not trigger on edited"
  grep -q 'Adversarial review' "$RR" && ok "$RR checks the Adversarial review section" || bad "$RR does not look for the section"
  grep -qE '\$\{\{[^}]*body' <(sed -n '/run: |/,$p' "$RR") && bad "$RR interpolates the PR body into a script" || ok "$RR reads the PR body through env only"
  # The check's own awk, run on pr-create's template: an untouched template, or a
  # section holding only the comic, must count as empty (final release /dg,
  # 2026-10-17: the comic slot's placeholder lines passed an untouched template).
  PROG=$(sed -n "/| awk '\$/,/END {/p" "$RR" | sed -e '1d' -e "\$s/').*\$//")
  TPL=$(sed -n "/--body \"\$(cat <<'EOF'/,/^EOF\$/p" skills/pr-create/SKILL.md)
  # The awk prints three numbers: the section's filled lines, its verdict headings, and
  # the lines of text under a verdict heading.
  filled()  { printf '%s\n' "$1" | awk "$PROG" 2>/dev/null; }
  count()   { set -- $(filled "$1"); printf '%s' "${1:-}"; }
  verdict() { set -- $(filled "$1"); printf '%s' "${2:-}"; }
  under()   { set -- $(filled "$1"); printf '%s' "${3:-}"; }
  if [ -z "$PROG" ] || [ -z "$TPL" ]; then bad "could not extract $RR's awk or pr-create's template"
  else
    [ "$(count "$TPL")" = 0 ] && ok "$RR fails pr-create's untouched template" || bad "$RR passes pr-create's untouched template (counted $(count "$TPL"))"
    COMIC=$(printf '## Adversarial review\n### Comic\n````\n[1] DINESH\n````\n## Testing\n')
    [ "$(count "$COMIC")" = 0 ] && ok "…and a section holding only the comic" || bad "$RR passes a section holding only the comic"
    FULL=$(printf '## Adversarial review\n> Pre-review: ok\n### Verdict\n| V1 | x | minor | Applied |\n### Comic\n````\nx\n````\n## Testing\n')
    [ "$(count "$FULL")" = 3 ] && ok "…while a filled one counts, demoted headings and all" || bad "$RR miscounts a filled section ($(count "$FULL"), want 3)"
    # #83: the header lines alone are text, so they counted as filled — a section with
    # no verdict in it passed. The demoted `### Verdict` is what step 2b puts there.
    [ "$(verdict "$FULL")" = 1 ] && ok "…and finds its demoted ### Verdict" || bad "$RR does not find the ### Verdict in a filled section (got '$(verdict "$FULL")', want 1)"
    HDR=$(printf '## Adversarial review\n> Pre-review: ✅ codex\n> Dependency scan: n/a\n## Testing\n')
    [ "$(verdict "$HDR")" = 0 ] && ok "a section with the header lines and no verdict has no verdict heading" || bad "$RR finds a verdict in a section with only the header lines (got '$(verdict "$HDR")', want 0)"
    LATE=$(printf '## Adversarial review\n> Pre-review: ok\n### Comic\n### Verdict\n## Testing\n')
    [ "$(verdict "$LATE")" = 0 ] && ok "…nor one whose ### Verdict is inside the comic" || bad "$RR counts a ### Verdict after ### Comic (got '$(verdict "$LATE")', want 0)"
    # #84: only the template's own placeholders are skipped. A review written as one-line
    # HTML is a review, and used to count as empty.
    HTML=$(printf '## Adversarial review\n<p>Pre-review: ok</p>\n### Verdict\n<details><summary>V1</summary>applied in abc1234</details>\n## Testing\n')
    [ "$(count "$HTML")" = 3 ] && ok "a one-line HTML review counts as filled" || bad "$RR skips one-line HTML as a placeholder ($(count "$HTML"), want 3)"
    # A `### Verdict` with nothing under it, or only the demoted headings, is a heading
    # standing in for a review — the same hole #83 closed, one level down (0.26.0
    # release review, P1).
    [ "$(under "$FULL")" = 1 ] && ok "the filled section has its verdict's row under ### Verdict" || bad "$RR does not count the text under ### Verdict (got '$(under "$FULL")', want 1)"
    BARE=$(printf '## Adversarial review\n> Pre-review: ok\n### Verdict\n## Testing\n')
    SKEL=$(printf '## Adversarial review\n> Pre-review: ok\n### Verdict\n#### Agreed\n#### Recommended Actions\n### Comic\nx\n## Testing\n')
    [ "$(under "$BARE")" = 0 ] && ok "a bare ### Verdict has nothing under it" || bad "$RR counts text under a bare ### Verdict (got '$(under "$BARE")', want 0)"
    [ "$(under "$SKEL")" = 0 ] && ok "…nor does one holding only its demoted headings, the comic after it aside" || bad "$RR counts headings or the comic as a verdict (got '$(under "$SKEL")', want 0)"
    # A line is a heading only with a space (or nothing) after its hashes: `#83 applied`
    # is a paragraph, and this repo writes dispositions that way (0.26.0 fix review, W2).
    ISSUE=$(printf '## Adversarial review\n> Pre-review: ok\n### Verdict\n#83 applied in abc1234\n## Testing\n')
    [ "$(under "$ISSUE")" = 1 ] && ok "a verdict line starting #83 is text, not a heading" || bad "$RR reads '#83 applied' as a heading (got '$(under "$ISSUE")', want 1)"
    # A code fence is text, never structure (W3): a `### Verdict` inside one is an
    # example, not the verdict, and a `## ` inside one does not end the section.
    FENCED=$(printf '## Adversarial review\n> Pre-review: ok\n```md\n### Verdict\n| V1 | x |\n```\n## Testing\n')
    [ "$(verdict "$FENCED")" = 0 ] && ok "a ### Verdict inside a code fence is not the verdict" || bad "$RR counts a fenced ### Verdict (got '$(verdict "$FENCED")', want 0)"
    INNER=$(printf '## Adversarial review\n### Verdict\n~~~\n## not a heading\n~~~\n| V1 | applied |\n## Testing\n')
    [ "$(under "$INNER")" = 4 ] && ok "…and a ## inside a fence does not end the section" || bad "$RR ends the section at a fenced ## (under '$(under "$INNER")', want 4)"
    # A heading may be indented up to three spaces; four is an indented code block,
    # so text (CommonMark). Matched at column 1 only, ` ## Testing` did not end the
    # section and a bare verdict took the text after it (0.26.0 third review, X1).
    INDH2=$(printf '## Adversarial review\n> Pre-review: ok\n### Verdict\n ## Testing\nran the suites\n')
    INDCOMIC=$(printf '## Adversarial review\n> Pre-review: ok\n### Verdict\n   ### Comic\nx\n## Testing\n')
    CODE4=$(printf '## Adversarial review\n### Verdict\n    ## indented code, not a heading\n| V1 | applied |\n## Testing\n')
    [ "$(under "$INDH2")" = 0 ] && ok "an indented ## ends the section" || bad "$RR does not end the section at ' ## Testing' (under '$(under "$INDH2")', want 0)"
    [ "$(under "$INDCOMIC")" = 0 ] && ok "…and an indented ### Comic ends the verdict" || bad "$RR does not end the verdict at '   ### Comic' (under '$(under "$INDCOMIC")', want 0)"
    [ "$(under "$CODE4")" = 2 ] && ok "…while four spaces is code, so text" || bad "$RR reads a 4-space-indented ## as a heading (under '$(under "$CODE4")', want 2)"
    # The close rule, case by case: each of these passed with the rule broken — any
    # fence line closing, the backtick-in-info-string rule gone, or a run of one
    # opening a fence (0.26.0 third review, X3).
    LONG=$(printf '## Adversarial review\n### Verdict\n````\n```\n## inside\n```\n````\n| V1 | applied |\n## Testing\n')
    TILDE=$(printf '## Adversarial review\n### Verdict\n~~~\n```\n## inside\n~~~\n| V1 | applied |\n## Testing\n')
    INLINE3=$(printf '## Adversarial review\n### Verdict\n```x``` is inline code\n## Testing\nafter\n')
    INLINE1=$(printf '## Adversarial review\n### Verdict\n`x` applied\n## Testing\nafter\n')
    [ "$(under "$LONG")" = 6 ] && ok "a \`\`\` line does not close a \`\`\`\` fence" || bad "$RR closes a \`\`\`\` fence at \`\`\` (under '$(under "$LONG")', want 6)"
    [ "$(under "$TILDE")" = 5 ] && ok "…nor does it close a ~~~ fence" || bad "$RR closes a ~~~ fence at \`\`\` (under '$(under "$TILDE")', want 5)"
    [ "$(under "$INLINE3")" = 1 ] && ok "…a line of inline \`\`\`code\`\`\` opens no fence" || bad "$RR opens a fence at inline \`\`\`code\`\`\` (under '$(under "$INLINE3")', want 1)"
    # INLINE1 guards the backtick-later-on-the-line rule for a one-backtick run; with
    # a run of one allowed to open a fence, APPROX is the case that fails.
    [ "$(under "$INLINE1")" = 1 ] && ok "…nor does a line starting with \`code\`" || bad "$RR opens a fence at a line starting \`x\` (under '$(under "$INLINE1")', want 1)"
    APPROX=$(printf '## Adversarial review\n### Verdict\n~2 minutes of CI, applied\n## Testing\nafter\n')
    [ "$(under "$APPROX")" = 1 ] && ok "…nor one starting with a single ~" || bad "$RR opens a fence at a line starting '~2' (under '$(under "$APPROX")', want 1)"
    # Every structural rule reads the line with its indent stripped, each pinned by a
    # case of its own: with one reverted to the raw line, the suite stayed green, and
    # the `###` reset's revert let text under an indented heading pass as the verdict
    # (0.26.0 fourth review, Y3). A closing fence has nothing after its run, so
    # ```md inside a ``` fence is text, not its end (Y4).
    NOTES=$(printf '## Adversarial review\n### Verdict\n  ### Notes\ntext\n## Testing\n')
    INDVERD=$(printf '## Adversarial review\n  ### Verdict\n| V1 | applied |\n## Testing\n')
    H4ONLY=$(printf '## Adversarial review\n### Verdict\n #### Agreed\n## Testing\n')
    COMICFIRST=$(printf '## Adversarial review\n> Pre-review: ok\n  ### Comic\n### Verdict\n| V1 | applied |\n## Testing\n')
    INFOCLOSE=$(printf '## Adversarial review\n### Verdict\n```\n```md\n## inside\n```\n| V1 | applied |\n## Testing\nafter\n')
    [ "$(under "$NOTES")" = 0 ] && ok "an indented ### ends the verdict" || bad "$RR does not end the verdict at '  ### Notes' (under '$(under "$NOTES")', want 0)"
    [ "$(verdict "$INDVERD")" = 1 ] && ok "…an indented ### Verdict is the verdict" || bad "$RR misses '  ### Verdict' (verdict '$(verdict "$INDVERD")', want 1)"
    [ "$(under "$H4ONLY")" = 0 ] && ok "…an indented #### is a heading, not text" || bad "$RR counts ' #### Agreed' as verdict text (under '$(under "$H4ONLY")', want 0)"
    [ "$(verdict "$COMICFIRST")" = 0 ] && ok "…and an indented ### Comic ends the section" || bad "$RR does not end the section at '  ### Comic' (verdict '$(verdict "$COMICFIRST")', want 0)"
    [ "$(under "$INFOCLOSE")" = 5 ] && ok "a \`\`\`md line does not close a \`\`\` fence" || bad "$RR closes a fence at \`\`\`md (under '$(under "$INFOCLOSE")', want 5)"
    # An H1, a `##` followed by a tab, and an empty `##` are headings that end the
    # section; matched as `## ` only, a bare verdict before any of them took the text
    # after it (Y1). So is an empty `###`, which ends the verdict.
    H1=$(printf '## Adversarial review\n### Verdict\n# Testing\nran the suites\n')
    TABH2=$(printf '## Adversarial review\n### Verdict\n##\tTesting\nran the suites\n')
    EMPTYH2=$(printf '## Adversarial review\n### Verdict\n##\nran the suites\n')
    EMPTYH3=$(printf '## Adversarial review\n### Verdict\n###\nran the suites\n## Testing\n')
    for c in H1 TABH2 EMPTYH2 EMPTYH3; do
      eval "b=\$$c"
      [ "$(under "$b")" = 0 ] && ok "a bare verdict followed by $c has nothing under it" || bad "$RR takes the text after $c as the verdict (under '$(under "$b")', want 0)"
    done
  fi
  # The step itself, as GitHub runs it (`bash -e`): it passes a filled body, fails a bare
  # verdict, and fails when its awk dies. `set -- $(…)` exits 0 whatever the awk did, so
  # a dead awk left both numbers empty, every test errored inside its `if`, and the step
  # printed ok (0.26.0 release review, V1). The awk test above runs the program, never
  # the shell around it.
  RUN=$(sed -n '/run: |/,$p' "$RR" | sed -e '1d' -e 's/^          //')
  FX=$(mktemp -d "${TMPDIR:-/tmp}/rr.XXXXXX"); printf '#!/bin/sh\nexit 2\n' > "$FX/awk"; chmod +x "$FX/awk"
  step() { BODY="$1" PATH="${2:+$2:}$PATH" bash -e -c "$RUN" 2>&1; }
  OUT=$(step "$FULL"); RC=$?
  [ "$RC" -eq 0 ] && grep -q '^ok ' <<<"$OUT" && ok "the step passes a filled section" || bad "the step fails a filled section (exit $RC: $OUT)"
  OUT=$(step "$BARE"); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && ok "…fails a bare ### Verdict (exit $RC)" || bad "the step passes a bare ### Verdict (exit $RC: $OUT)"
  OUT=$(step "$ISSUE"); RC=$?
  [ "$RC" -eq 0 ] && grep -q '^ok ' <<<"$OUT" && ok "…passes a verdict whose line starts #83" || bad "the step fails a verdict whose line starts #83 (exit $RC: $OUT)"
  OUT=$(step "$FENCED"); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && ok "…fails a verdict that is only inside a code fence (exit $RC)" || bad "the step passes a fenced-only verdict (exit $RC: $OUT)"
  OUT=$(step "$INDH2"); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && ok "…fails a bare verdict followed by an indented ## (exit $RC)" || bad "the step passes a bare verdict followed by ' ## Testing' (exit $RC: $OUT)"
  OUT=$(step "$H1"); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && ok "…fails a bare verdict followed by an H1 (exit $RC)" || bad "the step passes a bare verdict followed by '# Testing' (exit $RC: $OUT)"
  OUT=$(step "$FULL" "$FX"); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && ok "…and fails when its awk dies (exit $RC)" || bad "the step passes when its awk dies (exit $RC: $OUT)"
  rm -rf "$FX"
fi

echo "Every code fence in a shipped markdown file is closed:"
# A /dg step 6 edit closed its block one line early, so the comic instruction rendered
# as loose text outside the template; every suite passed and a reviewer caught it (#86).
# CommonMark: a fence is 3+ backticks or tildes, and only the same character, at least
# as long, with nothing after it, closes it — so a ```` block holding ``` lines is one
# block. A backtick run with a backtick later on the line is inline code, not a fence.
# Indentation is ignored, since fences sit inside list items here. Prints "<line> <run>"
# for a fence still open at the end of the file, nothing when every fence is closed.
unclosed_fence() {
  awk '
    function run(s, c,   n) { n = 0; while (substr(s, n + 1, 1) == c) n++; return n }
    {
      l = $0; sub(/^[ \t]+/, "", l); c = substr(l, 1, 1)
      if (c != "`" && c != "~") next
      n = run(l, c); if (n < 3) next
      rest = substr(l, n + 1)
      if (!open) {
        if (c == "`" && index(rest, "`")) next
        open = 1; oc = c; on = n; ol = NR; next
      }
      if (c == oc && n >= on && rest ~ /^[ \t]*$/) open = 0
    }
    END { if (open) { s = ""; for (i = 0; i < on; i++) s = s oc; print ol " " s } }
  ' "$1"
}
# The checker is checked first: a dead awk prints nothing, which reads as "all closed".
FX=$(mktemp -d "${TMPDIR:-/tmp}/fence.XXXXXX")
printf 'a\n```sh\nx\n' > "$FX/open.md"
printf '````md\n```\ninner\n```\n````\n~~~\n```\n~~~\nuse ```x``` inline\n' > "$FX/nested.md"
OPEN_OUT=$(unclosed_fence "$FX/open.md"); OPEN_RC=$?
NEST_OUT=$(unclosed_fence "$FX/nested.md"); NEST_RC=$?
rm -rf "$FX"
if [ "$OPEN_RC" -ne 0 ] || [ "$OPEN_OUT" != '2 ```' ]; then
  bad "the fence check misses an unclosed fence (exit $OPEN_RC, said '$OPEN_OUT') — nothing below can be trusted"
elif [ "$NEST_RC" -ne 0 ] || [ -n "$NEST_OUT" ]; then
  bad "the fence check flags nested fences or inline code (exit $NEST_RC, said '$NEST_OUT')"
else
  ok "the check finds an unclosed fence, and passes \`\`\` inside \`\`\`\`, \`\`\` inside ~~~, and inline \`\`\`code\`\`\`"
  n=0; unbalanced=0
  for f in $(git ls-files '*.md'); do
    n=$((n+1)); out=$(unclosed_fence "$f"); rc=$?
    if [ "$rc" -ne 0 ]; then bad "$f: the fence check exited $rc"; unbalanced=1
    elif [ -n "$out" ]; then bad "$f:${out%% *}: the ${out#* } fence opened here is never closed"; unbalanced=1
    fi
  done
  [ "$n" -eq 0 ] && bad "git ls-files found no markdown — nothing was checked"
  [ "$n" -gt 0 ] && [ "$unbalanced" -eq 0 ] && ok "$n tracked .md files, every fence closed"
fi

echo "Every conf key doctor knows is documented, and every /dg key a skill reads is one doctor knows:"
# The /dg keys are read by an instruction, not a hook, so nothing fails when one is
# renamed in the skill and not in doctor: the project's setting stops being read, and
# doctor calls the old name unknown — or the new one (DG_WAIT_MINUTES, 2026-10-19).
DOC=hooks/flight-rules-doctor.sh
KNOWN=$(sed -n -E "s/^KNOWN='([^']*)'.*/\1/p" "$DOC")
if [ -z "$KNOWN" ]; then bad "could not read KNOWN from $DOC"
else
  undoc=0
  for k in $KNOWN; do
    grep -qE '^\|[^|]*\| `'"$k"'` \|' hooks/README.md \
      || { bad "$k is a key doctor knows, with no row in hooks/README.md's Configuration table"; undoc=1; }
  done
  [ "$undoc" -eq 0 ] && ok "$(printf '%s\n' $KNOWN | grep -c .) keys, each in the Configuration table"
  # An empty list asserts nothing, so it is a failure, not a pass (0.26.0 release review).
  DG_KEYS=$(grep -rohE 'DG_[A-Z_]+' skills | sort -u)
  [ -n "$DG_KEYS" ] || bad "found no DG_* key named in skills/ — nothing to check"
  for k in $DG_KEYS; do
    [[ " $KNOWN " == *" $k "* ]] && ok "$k (named in skills/) is a key doctor knows" \
                                 || bad "$k is named in skills/, but doctor's KNOWN lacks it — doctor would call it unknown"
  done
fi

echo "DG_WAIT_MINUTES has one default:"
# The skill falls back to it, doctor's warning names it, the table documents it.
W_SKILL=$(tr '\n' ' ' < skills/dg/SKILL.md | sed -n -E 's/.*`DG_WAIT_MINUTES`[^(]*\(default ([0-9]+).*/\1/p')
W_DOC=$(sed -n '/^ *DG_WAIT_MINUTES)/,/;;/p' "$DOC" | sed -n -E 's/.*treats it as ([0-9]+).*/\1/p' | head -1)
W_README=$(sed -n -E 's/^\|[^|]*\| `DG_WAIT_MINUTES` \|.*default `([0-9]+)`.*/\1/p' hooks/README.md)
if [ -z "$W_SKILL" ] || [ -z "$W_DOC" ] || [ -z "$W_README" ]; then
  bad "could not read the default from every place (skill '$W_SKILL', doctor '$W_DOC', README '$W_README')"
elif [ "$W_SKILL" = "$W_DOC" ] && [ "$W_DOC" = "$W_README" ]; then
  ok "skill, doctor and hooks/README.md all say $W_SKILL"
else
  bad "the default differs: skill $W_SKILL, doctor $W_DOC, hooks/README.md $W_README"
fi

echo "A rule's (\`skill\` N) reference names the step it means:"
# feature-start gained a step 5 (#108) and #109 rewrote Required 7 on the old numbering:
# merged as either side wrote it, Required 6 pointed at "Create the worktree", and every
# suite passed (fix review, 2026-10-24). Each reference is pinned to a word of its step's
# title, so a renumber that leaves a reference behind fails, and so does a new reference
# nobody pinned: add it here. <skill> <step> <a word of the title>
STEPS='commit 4 Validate
feature-start 3 branch name
feature-start 4 Sync the base
feature-start 5 open branches
feature-start 7 Symlink
pre-merge-check 1 test suite
pre-merge-check 3 E2E
pre-merge-check 8 Conventional
pre-merge-check 9 Single-purpose
pre-merge-check 16 Commit-count'
REFS=$(grep -o -E '`[a-z-]+` [0-9]+(–[0-9]+)?' rules/*.md | sed -E 's/^[^:]*://; s/`//g; s/–/ /' \
  | awk '{print $1, $2; if ($3 != "") print $1, $3}' | sort -u)
[ -n "$REFS" ] || bad "no (\`skill\` N) references found in rules/ — the extraction broke"
while read -r sk n; do
  [ -n "$sk" ] || continue
  want=$(printf '%s\n' "$STEPS" | awk -v s="$sk" -v n="$n" '$1==s && $2==n {$1=""; $2=""; sub(/^  /, ""); print}')
  if [ -z "$want" ]; then bad "rules/ cites \`$sk\` $n, which this test has not pinned — add it to STEPS"; continue; fi
  title=$(grep -E "^ {0,3}$n\. \*\*" "skills/$sk/SKILL.md" | head -1)
  if [ -z "$title" ]; then bad "rules/ cites \`$sk\` $n; skills/$sk/SKILL.md has no step $n"
  elif printf '%s' "$title" | grep -qiF -e "$want"; then ok "\`$sk\` $n is \"${want}…\""
  else bad "rules/ cites \`$sk\` $n for \"$want\"; step $n is now: $(printf '%s' "$title" | cut -c1-60)"; fi
done <<<"$REFS"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
