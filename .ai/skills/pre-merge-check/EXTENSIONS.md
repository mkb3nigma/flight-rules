# /pre-merge-check — flight-rules' own extensions

Item 18's rules files include `MISSION.md`: `CLAUDE.md` and `GEMINI.md` import it, and
`AGENTS.md` sends every other assistant to it first, so it reaches every session that
changes this repo, and a line added to it is checked as a rules line is.
The shipped list leaves it out because an adopting project's own `MISSION.md`, if it has
one, is that project's business.
