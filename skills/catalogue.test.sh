#!/usr/bin/env bash
# The skills catalogue must agree with itself: every skill directory has a
# SKILL.md whose frontmatter name matches, every .claude/skills pointer names a
# real skill and nothing is unregistered, and README's table lists exactly the
# shipped set. This is the docs-currency rule for the one place drift is
# mechanical. Run: ./catalogue.test.sh (from anywhere; no args).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

SKILLS=$(find skills -mindepth 1 -maxdepth 1 -type d | sed 's|skills/||' | sort)

echo "Each skill: frontmatter name matches its directory, description present:"
for s in $SKILLS; do
  f="skills/$s/SKILL.md"
  [ -f "$f" ] || { bad "$s has no SKILL.md"; continue; }
  name=$(sed -n '2,6p' "$f" | sed -n -E 's/^name: (.*)$/\1/p' | head -1)
  desc=$(sed -n '2,8p' "$f" | sed -n -E 's/^description: (.*)$/\1/p' | head -1)
  [ "$name" = "$s" ] || { bad "$f: name '$name' ≠ directory '$s'"; continue; }
  [ -n "$desc" ]    || { bad "$f: no description"; continue; }
  [ ${#desc} -le 250 ] || { bad "$f: description is ${#desc} chars — pickers truncate"; continue; }
  ok "$s"
done

echo "Pointer files in .claude/skills/ match the shipped set one-to-one:"
POINTERS=$(find .claude/skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|.claude/skills/||' | sort)
# A skill that maintains this repo only (/upstream-check) lives whole in .claude/skills/
# and does not ship; anything else there is a pointer at a shipped skill.
for p in $POINTERS; do
  if ! grep -q "^$p\$" <<<"$SKILLS"; then
    grep -q "skills/$p/SKILL.md" ".claude/skills/$p/SKILL.md" 2>/dev/null \
      && bad ".claude/skills/$p points at a skill that does not exist"
    REPO_ONLY="${REPO_ONLY-}$p "
  else
    grep -q "skills/$p/SKILL.md" ".claude/skills/$p/SKILL.md" 2>/dev/null || bad ".claude/skills/$p/SKILL.md does not reference skills/$p/SKILL.md"
  fi
  pn=$(sed -n -E 's/^name: (.*)$/\1/p' ".claude/skills/$p/SKILL.md" | head -1)
  [ "$pn" = "$p" ] || bad ".claude/skills/$p: frontmatter name '$pn' ≠ '$p'"
done
for s in $SKILLS; do
  grep -q "^$s\$" <<<"$POINTERS" || bad "skills/$s has no pointer in .claude/skills/ — not runnable in this repo"
done
ok "$(wc -w <<<"$SKILLS" | tr -d ' ') shipped skills, each with a pointer; this repo's own: ${REPO_ONLY:-none}"

echo "README catalogue lists exactly the shipped skills:"
LISTED=$(sed -n -E 's/^\| \[`\/([a-z-]+)`\]\(skills\/[a-z-]+\/SKILL\.md\).*/\1/p' README.md | sort)
for s in $SKILLS; do grep -q "^$s\$" <<<"$LISTED" || bad "README table is missing /$s"; done
for l in $LISTED; do grep -q "^$l\$" <<<"$SKILLS" || bad "README table lists /$l, which does not ship"; done
[ "$SKILLS" = "$LISTED" ] && ok "README table matches"

# /pre-merge-check carries a copy of the guard's secret patterns, because a plugin
# consumer's shell has no CLAUDE_PLUGIN_ROOT and no repo copy of the guard to read them
# from. A copy that drifts is worse than none: the skill would report a clean scan it
# ran with last year's patterns. This is the check that makes the copy safe to keep.
echo "/pre-merge-check's fallback patterns match the guard's:"
GUARD=hooks/agent/pre-commit-check.sh
SKILL=skills/pre-merge-check/SKILL.md
GUARD_PATS=$(sed -n -E "s/^[[:space:]]*if hit '(.*)'; then\$/\1/p" "$GUARD")
[ -n "$GUARD_PATS" ] || bad "$GUARD: no \`hit '…'\` patterns found — this test is reading the wrong thing"
N=0
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  N=$((N+1))
  grep -qF -- "$pat" "$SKILL" || bad "$SKILL is missing the guard's pattern: $pat"
done <<EOF
$GUARD_PATS
EOF
# …and nothing in the skill's list that the guard no longer has. An extraction that finds
# nothing would pass this half on its own, so it is checked first (review, 2026-10-29).
SKILL_PATS=$(awk '/^   ```$/{n++; next} n==1' "$SKILL" | sed -n -E 's/^   ([^ #][^#]*[^ #])[[:space:]]+#.*/\1/p')
[ -n "$SKILL_PATS" ] || bad "$SKILL: no fenced pattern list found — this test is reading the wrong thing"
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  grep -qF -- "$pat" "$GUARD" || bad "$SKILL lists a pattern the guard does not have: $pat"
done <<<"$SKILL_PATS"
[ "$FAIL" -eq 0 ] && ok "$N guard patterns, all present in the skill and none extra"

# The git pre-commit hook runs the same six on what the commit records (#71). A key the
# agent guard knows and the git hook does not is a key that leaks through `git add && commit`.
echo "The git pre-commit hook's patterns match the guard's:"
GITHOOK=hooks/git/pre-commit
HOOK_PATS=$(sed -n -E "s/^[[:space:]]*if hit '(.*)'; then\$/\1/p" "$GITHOOK")
[ -n "$HOOK_PATS" ] || bad "$GITHOOK: no \`hit '…'\` patterns found — this test is reading the wrong thing"
if [ "$(sort <<<"$GUARD_PATS")" = "$(sort <<<"$HOOK_PATS")" ]; then
  ok "$(wc -l <<<"$HOOK_PATS" | tr -d ' ') patterns, same set in both"
else
  bad "$GITHOOK and $GUARD disagree on the secret patterns: $(diff <(sort <<<"$GUARD_PATS") <(sort <<<"$HOOK_PATS") | grep '^[<>]' | tr '\n' ' ')"
fi

echo "Every file a skill names beside itself is there, and every file there is named:"
# Steps that only some runs need keep their rule and point at a file beside SKILL.md
# (#119). A missing file leaves the step pointing at nothing; a file no step names is
# a contract nothing reads. The convention is the phrase "`<file>` beside this file",
# in SKILL.md or in a file it names.
MISS=0; NREF=0
for s in $SKILLS; do
  d="skills/$s"
  # Lines joined first: prose wraps the phrase anywhere.
  refs=$(cat "$d"/*.md | tr '\n' ' ' | grep -oE '`[A-Za-z0-9._-]+`[[:space:]]+beside[[:space:]]+this[[:space:]]+file' \
    | sed -E 's/^`([^`]*)`.*/\1/' | sort -u)
  for r in $refs; do
    NREF=$((NREF+1))
    [ -f "$d/$r" ] || { MISS=$((MISS+1)); bad "$d names \`$r\` beside it; there is no $d/$r"; }
  done
  for f in $(find "$d" -mindepth 1 -maxdepth 1 -type f ! -name SKILL.md -exec basename {} \; | sort); do
    grep -qxF -- "$f" <<<"$refs" || { MISS=$((MISS+1)); bad "$d/$f is named nowhere in $d as \`$f\` beside this file"; }
  done
done
[ "$MISS" -eq 0 ] && ok "$NREF named, all present; no file unnamed"

echo "Plugin description names every skill that has a slash command in it:"
for s in $(grep -oE '/[a-z-]+' .claude-plugin/plugin.json | tr -d / | sort -u); do
  grep -q "^$s\$" <<<"$SKILLS" || bad "plugin.json mentions /$s, which does not ship"
done
ok "plugin.json mentions only shipped skills"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
