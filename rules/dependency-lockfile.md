# Dependency Lockfile Convention

**What you tested is what you ship.** Every deployable project uses a two-file
dependency pattern: a human-edited *intent* file with flexible ranges, and a
machine-generated *lockfile* with every package — transitives included — pinned exactly.
Production installs the lockfile.

| Ecosystem | Intent (edit this) | Lockfile (never hand-edit) | Install in prod |
|---|---|---|---|
| Node | `package.json` | `package-lock.json` | `npm ci` |
| Python (pip) | `requirements.in` | `requirements.txt` (via `pip-compile`) | `pip install -r requirements.txt` |

## Why floors/ranges alone fail

- `pkg>=1.5` lets a major version arrive as a side effect of an unrelated install.
- Exact-pinning only *direct* deps still leaves ~100 transitives floating.
- With ranges, redeploying the same commit weeks apart produces a different tree —
  "tested" stops meaning anything, and rollbacks don't roll back dependencies.

## Python workflow (pip-tools)

```bash
# requirements.in holds direct deps + annotated security floors (CVE comments live here)
pip-compile requirements.in -o requirements.txt --strip-extras
pip install -r requirements.txt
<run the full test suite>
# commit BOTH files together
```

Deliberate full refresh: add `--upgrade`, then rerun everything including any
live-integration suites before committing.

## Security updates

Audit finding (`pip-audit` / `npm audit`) → raise the floor in the intent file with a
comment naming the advisory → recompile → install → test → ship. Never let a fix
arrive silently.

Rules of thumb learned in practice:
- A renamed package (e.g. PyPDF2 → pypdf) can hide behind an advisory's "fix version" —
  check whether the fix lives in a successor package.
- If `--upgrade` moves a major version you didn't ask for (e.g. an AI SDK), validate it
  against live integration tests before accepting it, or pin it back.
- Document accepted risks (no-fix-available advisories) in the project's dependency
  doc with the reason and a re-check trigger.
