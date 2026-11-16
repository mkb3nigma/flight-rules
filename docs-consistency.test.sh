#!/usr/bin/env bash
# Do this repo's DOCUMENTS agree with each other, with .flight-rules/conf, and with CI?
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
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hooks/test-lib.sh" || exit 2

CONF=.flight-rules/conf
[ -r "$CONF" ] || { printf '  ❌ harness: %s is not readable — nothing below was tested\n' "$CONF" >&2; exit 2; }
conf() { sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"[:space:]#]+)\"?.*$/\1/p" "$CONF" | tail -1; }

PROTECTED=$(conf PROTECTED_BRANCHES)
PR_ONLY=$(conf PR_ONLY_BRANCHES)
NOTE_GATED=$(conf NOTE_GATED_BRANCHES)
INTEGRATION=$(conf INTEGRATION_BRANCH)
WORKTREE=$(conf WORKTREE_DIR)
[ -n "$INTEGRATION" ] || { printf '  ❌ harness: no INTEGRATION_BRANCH in %s\n' "$CONF" >&2; exit 2; }

echo "AGENTS.md's parameter table states the values the hooks actually read:"
# The table is the first thing an assistant reads about this repo, and it is a COPY of the
# conf. A copy that drifts sends every session down the wrong workflow while every hook
# enforces the right one.
tablerow() { sed -n -E "s/^\| \`\{$1\}\` \| (.*) \|$/\1/p" AGENTS.md | head -1; }
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
    bad "AGENTS.md's table has no row for {$key}, which the conf sets to $val"
    continue
  fi
  # The row is prose. Every branch name in the regex must appear somewhere in it.
  missing=""
  for b in $(printf '%s' "$val" | tr -d '^$()' | tr '|' ' '); do
    case "$b" in ""|"*") continue ;; esac
    grep -qF -- "$b" <<<"$row" || missing="$missing $b"
  done
  if [ -n "$missing" ]; then
    bad "AGENTS.md's {$key} row does not mention:$missing (conf says $val)"
  else
    ok "{$key} — table and conf agree on:$(printf '%s' "$val" | tr -d '^$()' | tr '|' ' ' | sed 's/^/ /')"
  fi
done

echo "The worktree directory in the table is the one the hooks use:"
if grep -qF -- "$WORKTREE" <<<"$(tablerow WORKTREE_DIR)"; then
  ok "{WORKTREE_DIR} — $WORKTREE"
else
  bad "AGENTS.md's {WORKTREE_DIR} row does not mention $WORKTREE"
fi

echo "{TEST_COMMANDS} lists every suite that exists, and only those:"
# session-start.test.sh was written on 2026-09-12 and had to be added here, to CI and to
# hooks/README.md by hand. A suite nobody runs is a suite that rots. Not a worktree's
# copies: the worktrees moved to .flight-rules/ in 0.29.0 and only .ai/ was left out, so
# from a main checkout holding a worktree every suite in it read as unlisted (found at
# the release's full run, 2026-11-11).
ON_DISK=$(find . -name '*.test.sh' -not -path './.ai/*' -not -path './.flight-rules/*' | sed 's|^\./||' | sort)
LISTED=$(sed -n -E 's/^\| `\{TEST_COMMANDS\}` \| (.*)$/\1/p' AGENTS.md \
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
  if grep -qiE 'chore/release|release branch' AGENTS.md; then
    ok "AGENTS.md documents where the version bump is committed"
  else
    bad "$INTEGRATION is protected, so the bump cannot be committed on it — and AGENTS.md names no release branch"
  fi
else
  ok "the bump can be committed on the integration branch directly"
fi

echo "The release review check the docs describe exists, and re-runs on a body edit:"
# AGENTS.md, pr-create and the CHANGELOG name a `release review` check (step 2b); a doc
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
  # The first awk program only: the upstream-check step that follows has one too.
  PROG=$(sed -n "/| awk '\$/,/END {/{p;/END {/q;}" "$RR" | sed -e '1d' -e "\$s/').*\$//")
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
  RUN=$(awk '/run: \|/ { f = 1; next } f && /^      - name:/ { exit } f' "$RR" | sed -e 's/^          //')
  FX=$(mktemp -d "${TMPDIR:-/tmp}/rr.XXXXXX"); printf '#!/bin/sh\nexit 2\n' > "$FX/awk"; chmod +x "$FX/awk"
  step() { BODY="$1" PATH="${2:+$2:}$PATH" bash -e -c "$RUN" 2>&1; }
  OUT=$(step "$FULL"); RC=$?
  [ "$RC" -eq 0 ] && grep -q '^ok ' <<<"$OUT" && ok "the step passes a filled section" || bad "the step fails a filled section (exit $RC: $OUT)"
  OUT=$(step "$BARE"); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && ok "…fails a bare ### Verdict (exit $RC)" || bad "the step passes a bare ### Verdict (exit $RC: $OUT)"
  OUT=$(step "$FENCED"); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && ok "…fails a verdict that is only inside a code fence (exit $RC)" || bad "the step passes a fenced-only verdict (exit $RC: $OUT)"
  OUT=$(step "$FULL" "$FX"); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && ok "…and fails when its awk dies (exit $RC)" || bad "the step passes when its awk dies (exit $RC: $OUT)"
  # The upstream-check step (owner, 2026-11-01): no section, or a heading with nothing
  # under it, fails; a filled one passes; a dead awk fails.
  URUN=$(awk '/run: \|/ { n++; f = (n == 2); next } f && /^      - name:/ { exit } f' "$RR" | sed -e 's/^          //')
  ustep() { BODY="$1" PATH="${2:+$2:}$PATH" bash -e -c "$URUN" 2>&1; }
  UP=$(printf '## Upstream check\nAll three sources up to date.\n## Testing\n')
  OUT=$(ustep "$FULL"); RC=$?
  # Every refusal prints its way through too, here the owner's admin merge (V21).
  [ "$RC" -ne 0 ] && grep -q "The way past this check is the owner's admin merge" <<<"$OUT" && ok "the upstream step fails a body with no Upstream check section, printing the way past" || bad "the upstream step passes a body with no section, or prints no way past (exit $RC: $OUT)"
  OUT=$(ustep "$(printf '## Upstream check\n## Testing\nx\n')"); RC=$?
  [ "$RC" -ne 0 ] && ok "…fails an empty section" || bad "the upstream step passes an empty section (exit $RC: $OUT)"
  OUT=$(ustep "$UP"); RC=$?
  [ "$RC" -eq 0 ] && grep -q '^ok ' <<<"$OUT" && ok "…passes a filled one" || bad "the upstream step fails a filled section (exit $RC: $OUT)"
  OUT=$(ustep "$UP" "$FX"); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && ok "…and fails when its awk dies (exit $RC)" || bad "the upstream step passes when its awk dies (exit $RC: $OUT)"
  # The mutation stamp (owner, 2026-11-04 and -05): the release's head commit carries the
  # git note mutation/run.sh writes after a clean run of the whole kit, and it holds row
  # by row against the kit at that commit. First the verifier, on the kit as this tree
  # has it: a stamp built from the list passes; each way a stamp can be short of a clean
  # whole-kit run of this commit fails, naming what.
  H=0123456789abcdef0123456789abcdef01234567
  MK=mutation/mutants.py
  NM=$(python3 -I "$MK" list | wc -l | tr -d ' ')
  # stamp <summary> [<sed applied to the rows>]
  stamp() {
    printf 'flight-rules mutation stamp\n%s\n' "$1"
    python3 -I "$MK" list | awk -F '\t' '{ print $1 "\t" ($4 == "killed" ? "killed" : "survived") "\tsuite" }' | sed -e "${2:-}"
  }
  clean() { printf 'mutation: all %s run from %s — 1 killed (0 aborts, 0 timeouts), 1 survived (1 expected), 0 failed to apply; 0 unexpected survivor(s)' "$NM" "$1"; }
  SD=$(mktemp -d "${TMPDIR:-/tmp}/stamp.XXXXXX")
  vpasses() { stamp "$2" "${3:-}" >"$SD/s"; OUT=$(python3 -I "$MK" verify "$H" "$SD/s" 2>&1); RC=$?
    [ "$RC" -eq 0 ] && ok "mutants.py verify passes $1" || bad "mutants.py verify fails $1 (exit $RC: $OUT)"; }
  vfails() { stamp "$2" "${3:-}" >"$SD/s"; OUT=$(python3 -I "$MK" verify "$H" "$SD/s" 2>&1); RC=$?
    [ "$RC" -ne 0 ] && grep -q -- "$4" <<<"$OUT" && ok "…fails $1" || bad "mutants.py verify passes $1, or not naming '$4' (exit $RC: $OUT)"; }
  FIRST=$(python3 -I "$MK" list | awk -F '\t' '$4 == "killed" { print $1; exit }')
  SURV=$(python3 -I "$MK" list | awk -F '\t' '$4 != "killed" { print $1; exit }')
  vpasses "a clean stamp of the whole kit on the commit" "$(clean "$H")"
  vfails "a stamp missing a mutant's row"     "$(clean "$H")" "/^$FIRST	/d"        "$FIRST: no row"
  vfails "one with a row for no such mutant" "$(clean "$H")" "\$a\\
NOPE	killed	suite"                                                                  "NOPE is not a mutant"
  vfails "a row twice"                       "$(clean "$H")" "/^$FIRST	/p"        "$FIRST: 2 rows"
  vfails "a mutant expected killed that survived" "$(clean "$H")" "s/^$FIRST	killed/$FIRST	survived/" "$FIRST: survived, expected killed"
  # Only the values run.sh writes: read by prefix, any 'killed…' passed as a kill (V4).
  vfails "a row whose result run.sh never writes" "$(clean "$H")" "s/^$FIRST	killed/$FIRST	killed-bogus/" "$FIRST: 'killed-bogus' is not a result run.sh writes"
  vfails "…an expected survivor's too"       "$(clean "$H")" "s/^$SURV	survived/$SURV	killedx/" "$SURV: 'killedx' is not a result run.sh writes"
  # A known gap now killed is the kit grown stronger, not a regression: it passes, and
  # the line the check prints names it, to have its expect updated (owner, 2026-11-05).
  stamp "$(clean "$H")" "s/^$SURV	survived/$SURV	killed/" >"$SD/s"; OUT=$(python3 -I "$MK" verify "$H" "$SD/s" 2>&1); RC=$?
  [ "$RC" -eq 0 ] && grep -q "1 expected survivor(s) now killed ($SURV): update their expect" <<<"$OUT" && ok "…passes a known gap now killed, naming it" || bad "mutants.py verify refuses, or does not name, a known gap now killed (exit $RC: $OUT)"
  # Killed only by an abort or a timeout is no proof a suite noticed it: it passes, named
  # apart, to be run alone first — never offered as a gap closed (/dg of 6fe5aeb, F1).
  SURV2=$(python3 -I "$MK" list | awk -F '\t' '$4 != "killed" { n++ } n == 2 { print $1; exit }')
  stamp "$(clean "$H")" "s/^$SURV	survived/$SURV	killed-abort/;s/^$SURV2	survived/$SURV2	killed-timeout/" >"$SD/s"; OUT=$(python3 -I "$MK" verify "$H" "$SD/s" 2>&1); RC=$?
  [ "$RC" -eq 0 ] && grep -q "2 expected survivor(s) killed only by an abort or a timeout (.*): run each alone" <<<"$OUT" && grep -q "$SURV killed-abort" <<<"$OUT" && grep -q "$SURV2 killed-timeout" <<<"$OUT" && ! grep -q 'now killed' <<<"$OUT" && ok "…passes one killed only by an abort or a timeout, named apart, not as a gap closed" || bad "mutants.py verify refuses, misnames or calls closed an abort or timeout kill (exit $RC: $OUT)"
  vfails "another commit's run"              "$(clean "${H%7}8")" ""                "not of $H"
  vfails "a dirty tree's run"                "$(clean "$H + uncommitted changes")" "" "not of $H"
  vfails "a selection"                       "mutation: 5 of $NM run from $H — 5 killed (0 aborts, 0 timeouts), 0 survived (0 expected), 0 failed to apply; 0 unexpected survivor(s)" "" "not of the whole kit"
  vfails "a run that did not pass"           "$(clean "$H" | sed 's/0 unexpected/1 unexpected/')" "" "not clean"
  printf '%s\n' "$(clean "$H")" >"$SD/s"; OUT=$(python3 -I "$MK" verify "$H" "$SD/s" 2>&1); RC=$?
  [ "$RC" -ne 0 ] && grep -q 'not a stamp run.sh wrote' <<<"$OUT" && ok "…and a summary line alone, typed" || bad "mutants.py verify passes a typed summary line (exit $RC: $OUT)"
  # Then the step, as GitHub runs it in a checkout of the head: the note is fetched from
  # origin, so one not pushed, one on another commit, and one that does not hold each
  # fail and print the push and run commands; a pushed clean stamp passes.
  MRUN=$(awk '/run: \|/ { n++; f = (n == 3); next } f && /^      - name:/ { exit } f' "$RR" | sed -e 's/^          //')
  G=(git -c user.name=t -c user.email=t@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null)
  ORG="$SD/origin"; CO="$SD/co"
  mkdir -p "$ORG/mutation" && cp "$MK" "$ORG/mutation/" && "${G[@]}" -C "$ORG" init -q && "${G[@]}" -C "$ORG" add -A && "${G[@]}" -C "$ORG" commit -qm head \
    && "${G[@]}" clone -q "$ORG" "$CO" || die "could not build the stamp step's repositories"
  HS=$(git -C "$CO" rev-parse HEAD)
  mstep() { (cd "$CO" && HEAD_SHA=$HS bash -e -c "$MRUN" 2>&1); }
  OUT=$(mstep); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && grep -q 'git push origin refs/notes/mutation' <<<"$OUT" && grep -q 're-run this one' <<<"$OUT" && grep -q "The way past this check is the owner's admin merge" <<<"$OUT" && ok "the stamp step fails when no stamp was pushed, printing the push, the re-run and the way past" || bad "the stamp step passes, or prints no push or way past, with no stamp pushed (exit $RC: $OUT)"
  H=$HS; stamp "$(clean "$HS")" >"$SD/good"; stamp "$(clean "$HS")" "/^$FIRST	/d" >"$SD/short"
  "${G[@]}" -C "$ORG" commit -q --allow-empty -m later && "${G[@]}" -C "$ORG" notes --ref=mutation add -F "$SD/good" HEAD || die "could not stamp the later commit"
  OUT=$(mstep); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && grep -q "worktree add --detach .flight-rules/worktrees/mutation $HS" <<<"$OUT" && ok "…fails when only another commit is stamped, printing the run" || bad "the stamp step passes another commit's stamp (exit $RC: $OUT)"
  "${G[@]}" -C "$ORG" notes --ref=mutation add -f -F "$SD/short" "$HS" || die "could not stamp the head"
  OUT=$(mstep); RC=$?
  [ "$RC" -ne 0 ] && ! grep -q '^ok ' <<<"$OUT" && grep -q "$FIRST: no row" <<<"$OUT" && ok "…fails a stamp that does not hold, naming why" || bad "the stamp step passes a short stamp (exit $RC: $OUT)"
  "${G[@]}" -C "$ORG" notes --ref=mutation add -f -F "$SD/good" "$HS" 2>/dev/null || die "could not stamp the head"
  OUT=$(mstep); RC=$?
  [ "$RC" -eq 0 ] && grep -q "^ok  Mutation stamp on $HS: mutation: all $NM run from $HS" <<<"$OUT" && ok "…and passes a pushed clean stamp of the head, printing its summary" || bad "the stamp step fails a clean stamp (exit $RC: $OUT)"
  rm -rf "$SD"
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
pre-merge-check 21 checks started'
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

echo "CLAUDE.md and GEMINI.md import MISSION.md and AGENTS.md:"
# AGENTS.md holds how work is done here; the other two only import it (2026-11-01).
# Drop an import and that assistant's sessions lose the rules with nothing else noticing.
for f in "CLAUDE.md @MISSION.md" "CLAUDE.md @AGENTS.md" "GEMINI.md @./MISSION.md" "GEMINI.md @./AGENTS.md"; do
  set -- $f
  if grep -qxF "$2" "$1"; then ok "$1 imports ${2#@}"; else bad "$1 has no line '$2'"; fi
done

echo "The commit prefixes are one list, in the commit skill, pre-merge-check 8 and the rule:"
# Three copies of one list: `ci:` reached commits that pre-merge-check 8 then refused,
# because the list there and the commit skill's both lacked it (test/mutation-kit,
# 2026-11-07), and a copy that changes alone leaves a commit allowed by one and refused
# by the next. The rule's list is the branch prefixes', so it names the one addition.
# Each copy's own list only, not its notes, which name `fix:` and `ci:` again: the
# bullet joined into a line and cut — at its first " (", or item 8's ";" — first.
prefixes() {   # <file> <first line> <last line> <sed: what to keep>
  awk -v from="$2" -v to="$3" 'index($0, from) { f = 1 } f { printf "%s ", $0 } f && index($0, to) { exit }' "$1" \
    | sed -E "$4" | grep -oE '`[a-z]+:`' | tr -d '`' | sort -u | tr '\n' ' '; }
PC=$(prefixes skills/commit/SKILL.md '- Message starts with' 'there is no' 's/ \(.*//')
PM=$(prefixes skills/pre-merge-check/SKILL.md '8. **Conventional commits**' 'branch prefix' 's/.*allowed prefix//; s/;.*//')
PR=$(prefixes rules/git-worktree-workflow.md '3. Conventional commit messages' 'ci/' 's/ \(.*//')
# And the list they copy: the branch prefixes (feature-start's), less hotfix/, which
# commits as fix:, plus ci: — so a branch prefix added alone fails here too (/dg D-1).
# The bullet is joined through its last prefix, as the others are, so a reflow keeps it.
BL=$(awk 'index($0, "- Branch name must start with an allowed prefix") { f = 1 } f { printf "%s ", $0 } f && index($0, "`hotfix/`") { exit }' skills/feature-start/SKILL.md)
PB=$(printf '%s\n' "$BL" | grep -oE '`[a-z]+/`' | tr -d '`' | grep -vx 'hotfix/' | sed 's|/$|:|' | sort -u | tr '\n' ' ')
[ -n "$PC" ] && [ "$PC" = "$PM" ] && ok "commit and pre-merge-check 8 allow the same prefixes ($PC)" || bad "commit allows '$PC', pre-merge-check 8 '$PM'"
if [ -z "$PB" ]; then bad "feature-start's 'Branch name must start with an allowed prefix' bullet was not found, or lists no prefix"
else
  PB=$(printf '%s ci: ' "$PB" | tr ' ' '\n' | grep . | sort -u | tr '\n' ' ')
  [ "$PC" = "$PB" ] && ok "…which are feature-start's branch prefixes, less hotfix/, plus ci:" || bad "the commit prefixes '$PC' are not feature-start's branch prefixes less hotfix/ plus ci: ('$PB')"
fi
case " $PC" in *" ci: "*) ok "…and ci: is among them" ;; *) bad "ci: is not an allowed prefix ($PC)" ;; esac
[ "$PR" = "ci: " ] && ok "…and the rule names ci:, the one prefix that is not a branch's" || bad "rules/git-worktree-workflow.md Required 3 adds '$PR' to the branch prefixes, want 'ci: '"
# Each copy also says what else passes: a scope, `fix(hooks):`, and git's own `Revert "…"`.
# Read bare, item 8 refused 283 scoped subjects already on main (#139) and the commit the
# rule's own revert route makes (#136); the remedy at the merge is a history rewrite.
for c in "skills/commit/SKILL.md|- Message starts with|- Commits happen on" \
         "skills/pre-merge-check/SKILL.md|8. **Conventional commits**|9. **Single-purpose" \
         "rules/git-worktree-workflow.md|3. Conventional commit messages|4. Review the full diff"; do
  f=${c%%|*}; r=${c#*|}; from=${r%%|*}; to=${r#*|}
  T=$(awk -v from="$from" -v to="$to" 'index($0, to) { exit } index($0, from) { f = 1 } f { printf "%s ", $0 }' "$f")
  if [ -z "$T" ]; then bad "$f: the prefix bullet ('$from') was not found"; continue; fi
  case $T in *'`<type>(<scope>):`'*) ok "$f allows a scoped prefix" ;; *) bad "$f's prefix bullet does not allow \`<type>(<scope>):\`" ;; esac
  case $T in *'`Revert "'*) ok "$f lets git's own Revert subject pass" ;; *) bad "$f's prefix bullet does not let git's \`Revert \"…\"\` subject pass" ;; esac
done
# The rule's branch prefixes are feature-start's, which step 3 checks a name against: a
# prefix added to or dropped from Required 2 alone passed every suite (#137). Its list
# only: the bullet joined and cut at its first " — ".
RL=$(awk 'index($0, "2. Branch names prefixed") { f = 1 } f { printf "%s ", $0 } f && index($0, " — ") { exit }' rules/git-worktree-workflow.md \
  | sed 's/ — .*//' | grep -oE '`[a-z]+/`' | tr -d '`' | sort -u | tr '\n' ' ')
FL=$(printf '%s\n' "$BL" | grep -oE '`[a-z]+/`' | tr -d '`' | sort -u | tr '\n' ' ')
[ -n "$RL" ] && [ "$RL" = "$FL" ] && ok "the rule's Required 2 lists feature-start's branch prefixes ($RL)" || bad "Required 2 lists '$RL', feature-start '$FL'"

echo "Shipped rules and skills cite no issue of this repo's:"
# They are read in adopters' projects, where `#125` reads as the adopter's own issue
# (owner, 2026-11-11, 0.29.0 release review D7). The date and the event stay; code and
# test comments keep their numbers. Two lines are not this repo's: `#123` is an example
# of a tracker reference, and AppliHawk's release PR #191 names its project.
N=$(grep -rln . rules skills --include='*.md' | wc -l | tr -d ' ')
HITS=$(grep -rnE '#[0-9]{2,}\b' rules skills --include='*.md' | grep -vF '(`#123`, a key, a URL)' | grep -vF "AppliHawk's" | grep -vF 'release PR #191')
[ "$N" -gt 10 ] || bad "read $N Markdown files under rules/ and skills/ — the check below read nothing"
[ -z "$HITS" ] && ok "none in $N files" || bad "issue numbers in shipped text: $(head -3 <<<"$HITS" | tr '\n' ' ')"

echo "The mutation run proves the path a mutant takes before any mutant:"
# A kill is any non-zero suite exit under a mutant, and the baseline ran another path (no
# MUTATION_UNDER_TEST, another TMPDIR): a fault in the mutant path alone read as every
# mutant killed, and a whole-kit run stamped clean (0.29.0 release review, second pass,
# V4). A one-mutant kit on a fixture: its suite passes the tree, mutated or not, but
# fails wherever MUTATION_UNDER_TEST is set — a fault in that path and nowhere else.
MF=$(mktemp -d "${TMPDIR:-/tmp}/mctl.XXXXXX") && MF=$(cd -P "$MF" && pwd -P) || die "could not make the control fixture"
mkdir -p "$MF/mutation" "$MF/tmp" && cp mutation/run.sh mutation/status.py "$MF/mutation/" || die "could not copy run.sh into $MF"
cat >"$MF/mutation/mutants.py" <<'PY' || die "could not write the fixture's mutants.py"
import sys
if sys.argv[1] == 'list': print('X1\tf.txt\tt.sh\tkilled'); sys.exit(0)
if sys.argv[1] == 'apply': open(sys.argv[3] + '/f.txt', 'w').write('mutated\n'); sys.exit(0)
if sys.argv[1] == 'check': print('1 mutants, 0 not anchored'); sys.exit(0)
sys.exit(2)
PY
printf 'ok\n' >"$MF/f.txt"
printf '#!/bin/sh\n[ -z "${MUTATION_UNDER_TEST:-}" ]\n' >"$MF/t.sh"
GF=(git -C "$MF" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@invalid -c commit.gpgsign=false)
{ "${GF[@]}" init -q && "${GF[@]}" add -A && "${GF[@]}" commit -qm fixture; } >/dev/null 2>&1 || die "could not commit the control fixture"
# Unset here: under a mutation run of this suite, it is set in this suite's own environment.
mrun() { (cd "$MF" && env -u MUTATION_UNDER_TEST TMPDIR="$MF/tmp" bash mutation/run.sh X1 2>&1); }
OUT=$(mrun); RC=$?
[ "$RC" -eq 2 ] && grep -q '❌ control: with nothing mutated, t.sh failed down the path a mutant takes .* — its log: .*/logs/control/t.sh.log' <<<"$OUT" && ! grep -q '^killed, by the suite' <<<"$OUT" \
  && ok "a suite failing down the mutant path with nothing mutated: exit 2, named, before any mutant" || bad "run.sh judged mutants down a path that fails unmutated (exit $RC: $(tail -3 <<<"$OUT" | tr '\n' ' '))"
# And a sound path: the control passes, and the mutant is judged as before.
printf '#!/bin/sh\ngrep -qx ok f.txt\n' >"$MF/t.sh" && "${GF[@]}" commit -qam 'a sound suite' >/dev/null 2>&1 || die "could not commit the sound suite"
OUT=$(mrun); RC=$?
[ "$RC" -eq 0 ] && grep -q '^control: 1 suite(s) pass down the path a mutant takes' <<<"$OUT" && grep -q '— 1 killed' <<<"$OUT" \
  && ok "…while a sound path passes the control, and the mutant is killed" || bad "the control refuses a sound mutant path, or the mutant was not judged (exit $RC: $(tail -3 <<<"$OUT" | tr '\n' ' '))"

echo "A mutation run says how far it has got (--status, read-only, and a line every few minutes):"
# A release run takes hours and said nothing between its control and its summary; the
# only way to see progress was to count result files by hand (owner, 2026-11-15).
snap() { (cd "$MF/tmp" && find . -type f -exec cksum {} + | sort); }
BEFORE=$(snap)
OUT=$(cd "$MF" && TMPDIR="$MF/tmp" bash mutation/run.sh --status 2>&1); RC=$?
[ "$RC" -eq 0 ] && grep -qE '^  state +finished, exit 0$' <<<"$OUT" && grep -qF ' 1 of 1 mutants (100%)' <<<"$OUT" \
  && grep -qE '^  results +killed 1 ' <<<"$OUT" && grep -qE '^  system +.* CPUs · bash ' <<<"$OUT" && grep -qF 'unexpected survivors so far: none' <<<"$OUT" \
  && ok "a finished run, found as the newest under TMPDIR: its state, progress, results and system" || bad "--status on a finished run (exit $RC: $(head -12 <<<"$OUT" | tr '\n' ' '))"
[ "$(snap)" = "$BEFORE" ] && ok "…and it writes nothing" || bad "--status changed a file in the work directory"
# A run in progress, as its files stand mid-run: one killed, one survived that should
# have been killed, one running, its process alive; then gone with no summary.
LW="$MF/tmp/mutation.live"; mkdir -p "$LW/res" "$LW/m/X3" || die "could not make the live fixture"
printf 'X1\tf.txt\tt.sh\tkilled\nX2\tg.txt\tt.sh\tkilled\nX3\tg.txt\tt.sh\tsurvives: not held\n' >"$LW/list"
printf 'X1\tkilled\tt\t❌ x\n' >"$LW/res/X1"; printf 'X2\tsurvived\tt\t-\n' >"$LW/res/X2"
sleep 300 >/dev/null 2>&1 & LP=$!
T0=$(( $(date +%s) - 600 ))
printf 'from=abc\nj=4\nn=3\npid=%s\nscope=all\nstarted=%s\ntimeout=1200\nos=TestOS 1\ncpus=8\n' "$LP" "$T0" >"$LW/run.info"
printf 'baseline\t%s\t\ncontrol\t%s\t\nmutants\t%s\t\n' "$T0" "$((T0 + 60))" "$((T0 + 120))" >"$LW/phases"
OUT=$(cd "$MF" && bash mutation/run.sh --status "$LW" 2>&1); RC=$?
[ "$RC" -eq 0 ] && grep -qE '^  state +running$' <<<"$OUT" && grep -qF ' 2 of 3 mutants' <<<"$OUT" && grep -qE '^  running +X3 \(' <<<"$OUT" \
  && grep -qF '❌ survived, expected killed: X2 (g.txt)' <<<"$OUT" && grep -qE '^    g.txt +1 of 2 ' <<<"$OUT" \
  && ok "a run in progress: running, what is done and running now, an unexpected survivor named, by file" || bad "--status mid-run (exit $RC: $(head -14 <<<"$OUT" | tr '\n' ' '))"
OUT=$(python3 -I "$MF/mutation/status.py" line "$LW" 2>&1); RC=$?
[ "$RC" -eq 0 ] && grep -qF 'mutation: mutants 2/3 (66%) · killed 1 · survived 1 (1 unexpected) · 1 running' <<<"$OUT" \
  && ok "…and in one line, as the run prints it" || bad "the progress line (exit $RC: $OUT)"
kill "$LP" 2>/dev/null; wait "$LP" 2>/dev/null
OUT=$(cd "$MF" && bash mutation/run.sh --status "$LW" 2>&1)
grep -qE "^  state +stopped: its process \($LP\) is gone and it wrote no summary$" <<<"$OUT" \
  && ok "…and a run whose process is gone, with no summary, is said to have stopped" || bad "--status on a stopped run: $(head -3 <<<"$OUT" | tr '\n' ' ')"
OUT=$(cd "$MF" && bash mutation/run.sh --status "$MF/f.txt" 2>&1); RC=$?
[ "$RC" -eq 1 ] && grep -qF 'is not a mutation run' <<<"$OUT" && ok "…and a path that is not a run's work directory is refused, named" || bad "--status on a non-run (exit $RC: $OUT)"
rm -rf "$LW"
# The line in the run's own output: a suite slow enough for a one-second tick to land.
printf '#!/bin/sh\nsleep 3; grep -qx ok f.txt\n' >"$MF/t.sh" && "${GF[@]}" commit -qam 'a slow suite' >/dev/null 2>&1 || die "could not commit the slow suite"
OUT=$(cd "$MF" && env -u MUTATION_UNDER_TEST TMPDIR="$MF/tmp" MUTATION_PROGRESS=1 bash mutation/run.sh X1 2>&1); RC=$?
[ "$RC" -eq 0 ] && grep -qE '^mutation: mutants [01]/1 \(' <<<"$OUT" && grep -qF 'progress, any time: mutation/run.sh --status ' <<<"$OUT" \
  && ok "…and a run prints a progress line every MUTATION_PROGRESS seconds, and how to ask for more" || bad "no progress line in the run's output (exit $RC: $(grep -v '^ ' <<<"$OUT" | head -8 | tr '\n' ' '))"

echo "A whole-kit mutation run checks the suites on Linux before any mutant:"
# The leg shipped unable to pass (the container re-committed a committed tree), and no
# case reached it: every run above is a selection, which skips it (release /dg, F1-F2).
# A docker stand-in on PATH drives each way it decides, and keeps what it was handed,
# so the flags and the container script are checked too. The release run is the only
# run of the real container (mutation/README.md). No network here, as {TEST_COMMANDS}
# need. The run's own MUTATION_* settings are cleared: this suite runs inside a release
# run, and MUTATION_LINUX=skip inherited here turned these cases, and so the run's
# baseline, red; the skip every stop prints led to a stop of its own (its /dg, F1).
printf '#!/bin/sh\ngrep -qx ok f.txt\n' >"$MF/t.sh" && "${GF[@]}" commit -qam 'a sound suite again' >/dev/null 2>&1 || die "could not commit the sound suite"
mkdir -p "$MF/shim" && cat >"$MF/shim/docker" <<'SH' || die "could not write the docker stand-in"
#!/bin/sh
# DOCKER_SHIM: noinfo | infowarn | pullfail | setup | setupquiet | fail | t124 | t137 | pass.
# After "_": the timeout, then the suites. A healthy info says what a real one says.
if [ "$1" = info ]; then
  [ "$DOCKER_SHIM" = noinfo ] && { echo "Cannot connect to the Docker daemon"; exit 1; }
  [ "$DOCKER_SHIM" = infowarn ] && echo "WARNING: Plugin /x/docker-y is not valid: failed to fetch metadata"
  printf ' Server Version: 29.0.0\n Live Restore Enabled: false\n'; exit 0
fi
for a in "$@"; do printf '%s\n' "$a"; done >"$(dirname "$0")/argv"
case "$DOCKER_SHIM" in pullfail|infowarn) printf 'Status: pulling\ndocker: Error response from daemon: pull access denied for nosuch\nRun '"'"'docker run --help'"'"' for more information\n' >&2; exit 125 ;; esac
[ "$DOCKER_SHIM" = setup ] && { echo "E: Could not resolve archive.ubuntu.com"; echo "linux-setup-failed: apt-get (offline?)"; exit 3; }
[ "$DOCKER_SHIM" = setupquiet ] && { echo "linux-setup-failed: useradd"; exit 3; }
while [ "$#" -gt 0 ] && [ "$1" != _ ]; do shift; done; shift 2
echo "linux-image: Shim OS 1 x86_64, bash 5.3"
for s in "$@"; do
  case "$DOCKER_SHIM" in fail) echo "linux-suite: 1 $s" ;; t124) echo "linux-suite: 124 $s" ;; t137) echo "linux-suite: 137 $s" ;; *) echo "linux-suite: 0 $s" ;; esac
done
SH
chmod +x "$MF/shim/docker"
MENV=(env -u MUTATION_UNDER_TEST -u MUTATION_LINUX -u MUTATION_LINUX_IMAGE -u MUTATION_TIMEOUT -u MUTATION_PROGRESS)
krun() { (cd "$MF" && "${MENV[@]}" TMPDIR="$MF/tmp" PATH="$MF/shim:$PATH" MUTATION_PROGRESS=0 MUTATION_TIMEOUT=77 DOCKER_SHIM="$1" ${2:+MUTATION_LINUX=$2} bash mutation/run.sh 2>&1); }
SKIPCMD='to go on without the Linux leg (the release PR'"'"'s CI is then the first Linux run): MUTATION_LINUX=skip mutation/run.sh -j 1'
for c in "noinfo|Docker is not running, or not installed" \
         "pullfail|the container did not start or was not set up on ubuntu:latest (docker exited 125): docker: Error response from daemon: pull access denied for nosuch — its log" \
         "infowarn|the container did not start or was not set up on ubuntu:latest (docker exited 125): docker: Error response from daemon: pull access denied for nosuch — its log" \
         "setup|(docker exited 3): linux-setup-failed: apt-get (offline?) — its log" \
         "setupquiet|(docker exited 3): linux-setup-failed: useradd — its log" "fail|❌ linux: exited 1 — t.sh" \
         "t124|❌ linux: timed out after 77s (exit 124) — t.sh" "t137|❌ linux: timed out after 77s (exit 137) — t.sh"; do
  OUT=$(krun "${c%%|*}"); RC=$?
  [ "$RC" -eq 2 ] && grep -qF "${c#*|}" <<<"$OUT" && grep -qF "$SKIPCMD" <<<"$OUT" && ! grep -q '^control:' <<<"$OUT" && ! grep -q '✅ stamped' <<<"$OUT" \
    && ok "${c%%|*}: stops before the control, exit 2, says why and prints the skip" || bad "the Linux leg on ${c%%|*} (exit $RC: $(tail -4 <<<"$OUT" | tr '\n' ' '))"
done
# docker info's output is in a log of its own, which the no-Docker stop names; a line
# of a healthy one is never given as the cause of a failure after it (its third /dg, F1).
OUT=$(krun noinfo); IL=$(sed -n 's/.*— its log: \(.*docker-info\.log\)\. No mutant.*/\1/p' <<<"$OUT")
[ -n "$IL" ] && grep -qF 'Cannot connect to the Docker daemon' "$IL" && ok "…the no-Docker stop names docker info's own log, which holds what Docker said" || bad "the no-Docker stop's log: '$IL'"
OUT=$( { krun infowarn; krun setupquiet; krun pullfail; } ); [ "$(grep -c 'the container did not start or was not set up' <<<"$OUT")" -ne 3 ] || grep -qE 'Plugin|Live Restore|Server Version' <<<"$OUT" \
  && bad "a line of a healthy docker info was named as a cause: $(grep -E 'Plugin|Live Restore|Server Version' <<<"$OUT" | head -1)" || ok "…and no line of a healthy docker info is named as a cause"
OUT=$(krun fail); grep -qF '❌ linux: 0 of 1 suite(s) passed on ubuntu:latest — its log' <<<"$OUT" && ! grep -qF '(docker exited' <<<"$OUT" \
  && ok "…and a suite failing names no docker exit, which was 0" || bad "a suite failing in a container that exited 0: $(grep '❌ linux: 0 of' <<<"$OUT")"
# The same stop with the skip and another image set in the environment this suite runs
# in, as a release run's baseline runs it: the cases hold.
OUT=$(MUTATION_LINUX=skip MUTATION_LINUX_IMAGE=elsewhere:1 krun fail); RC=$?
[ "$RC" -eq 2 ] && grep -qF '❌ linux: exited 1 — t.sh' <<<"$OUT" && ! grep -q 'skipped' <<<"$OUT" \
  && ok "…and with MUTATION_LINUX=skip and another image in the suite's own environment, as a skipped release run's baseline has them" || bad "the leg's cases took the suite's environment (exit $RC: $(tail -3 <<<"$OUT" | tr '\n' ' '))"
OUT=$(krun pass); RC=$?
A=$(cat "$MF/shim/argv")
[ "$RC" -eq 0 ] && grep -qF 'linux: 1 suite(s) pass on ubuntu:latest (Shim OS 1 x86_64, bash 5.3)' <<<"$OUT" && grep -q '^control: ' <<<"$OUT" && grep -q '— 1 killed' <<<"$OUT" \
  && [ "$(grep -n 'linux: 1 suite(s) passed on' <<<"$OUT" | cut -d: -f1)" -gt "$(grep -n '^mutation: all 1 run' <<<"$OUT" | cut -d: -f1)" ] \
  && ok "every suite passing: the run goes on, and its closing lines say the leg passed" || bad "the Linux leg on pass (exit $RC: $(tail -6 <<<"$OUT" | tr '\n' ' '))"
# What Docker is handed: pulled fresh (a cached tag never moves), an init that passes
# Ctrl-C to the suites' group, the host's .git dropped before the fresh commit, each
# suite under timeout, and the timeout then the suites after "_".
grep -qx -- '--pull' <<<"$A" && grep -qx 'always' <<<"$A" && grep -qx -- '--init' <<<"$A" && grep -qx 'TINI_KILL_PROCESS_GROUP=1' <<<"$A" \
  && grep -qF 'cd ~/w && rm -rf .git' <<<"$A" && grep -qF 'timeout --kill-after=10' <<<"$A" && [ "$(sed -n '/^_$/{n;p;q;}' <<<"$A")" = 77 ] && [ "$(tail -1 <<<"$A")" = t.sh ] \
  && ok "…handed --pull always, --init with the group kill, a fresh .git, each suite under the timeout, then the timeout and the suites" || bad "docker was handed something else: $(tr '\n' ' ' <<<"$A" | cut -c1-300)"
OUT=$(krun noinfo skip); RC=$?
[ "$RC" -eq 0 ] && [ "$(grep -c 'linux: skipped (MUTATION_LINUX=skip)' <<<"$OUT")" -eq 2 ] && grep -q '— 1 killed' <<<"$OUT" \
  && ok "MUTATION_LINUX=skip: no Docker needed, the run goes on, and the skip is said at the start and the end" || bad "the skip (exit $RC: $(tail -6 <<<"$OUT" | tr '\n' ' '))"
OUT=$(cd "$MF" && "${MENV[@]}" TMPDIR="$MF/tmp" PATH="$MF/shim:$PATH" MUTATION_PROGRESS=0 DOCKER_SHIM=noinfo bash mutation/run.sh X1 2>&1); RC=$?
[ "$RC" -eq 0 ] && grep -q '— 1 killed' <<<"$OUT" && ! grep -q 'linux' <<<"$OUT" && ok "a selection skips the leg, and says nothing of it" || bad "a selection ran or named the Linux leg (exit $RC: $(grep linux <<<"$OUT" | head -2 | tr '\n' ' '))"
rm -rf "$MF"

echo "Every mutation mutant's anchor occurs exactly once:"
# A hook edit that moved an anchor and not its mutant passed every suite, and surfaced
# only hours into the release's mutation run, unstamped (0.29.0 release review, R-2). In
# that run a mutant is applied, so its own anchor is gone: run.sh names it, and the case
# stands aside rather than kill it for that.
if [ -n "${MUTATION_UNDER_TEST:-}" ]; then
  ok "…not checked while mutant $MUTATION_UNDER_TEST is applied (its own anchor is gone)"
else
  OUT=$(python3 -I mutation/mutants.py check . 2>&1); RC=$?
  [ "$RC" -eq 0 ] && ok "$(tail -1 <<<"$OUT")" || bad "mutants.py check exited $RC — update the mutant in the change that moved its anchor (mutation/README.md → Upkeep): $(grep -v ' not anchored$' <<<"$OUT" | head -3 | tr '\n' ' ')"
fi

finish
