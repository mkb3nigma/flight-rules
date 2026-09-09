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
for p in $POINTERS; do
  grep -q "^$p\$" <<<"$SKILLS" || bad ".claude/skills/$p points at a skill that does not exist"
  grep -q "skills/$p/SKILL.md" ".claude/skills/$p/SKILL.md" 2>/dev/null || bad ".claude/skills/$p/SKILL.md does not reference skills/$p/SKILL.md"
  pn=$(sed -n -E 's/^name: (.*)$/\1/p' ".claude/skills/$p/SKILL.md" | head -1)
  [ "$pn" = "$p" ] || bad ".claude/skills/$p: frontmatter name '$pn' ≠ '$p'"
done
for s in $SKILLS; do
  grep -q "^$s\$" <<<"$POINTERS" || bad "skills/$s has no pointer in .claude/skills/ — not runnable in this repo"
done
[ "$SKILLS" = "$POINTERS" ] && ok "$(wc -w <<<"$SKILLS" | tr -d ' ') skills, $(wc -w <<<"$POINTERS" | tr -d ' ') pointers, same set"

echo "README catalogue lists exactly the shipped skills:"
LISTED=$(sed -n -E 's/^\| \[`\/([a-z-]+)`\]\(skills\/[a-z-]+\/SKILL\.md\).*/\1/p' README.md | sort)
for s in $SKILLS; do grep -q "^$s\$" <<<"$LISTED" || bad "README table is missing /$s"; done
for l in $LISTED; do grep -q "^$l\$" <<<"$SKILLS" || bad "README table lists /$l, which does not ship"; done
[ "$SKILLS" = "$LISTED" ] && ok "README table matches"

echo "Plugin description names every skill that has a slash command in it:"
for s in $(grep -oE '/[a-z-]+' .claude-plugin/plugin.json | tr -d / | sort -u); do
  grep -q "^$s\$" <<<"$SKILLS" || bad "plugin.json mentions /$s, which does not ship"
done
ok "plugin.json mentions only shipped skills"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
