# Dependency Lockfile Convention

**What you tested is what you ship.** Every deployable project uses a two-file
dependency pattern: a human-edited *intent* file with flexible ranges, and a
machine-generated *lockfile* with every package — transitives included — pinned exactly.
Production installs the lockfile.

| Ecosystem | Intent (edit this) | Lockfile (never hand-edit) | Install in prod |
|---|---|---|---|
| Node | `package.json` | `package-lock.json` | `npm ci` |
| Python (pip) | `requirements.in` | `requirements.txt` (via `pip-compile`) | `pip install -r requirements.txt` |

## Before a new dependency enters the intent file (agent-aware)

An agent — or a rushed human — reaches for a package from memory. But training data goes
stale, and models **hallucinate package names, fall for typosquats, and default to
deprecated libraries**. There is no gate between "decide to use X" and "X is installed"
unless you make one. Before adding a new direct dependency, verify:

- **It exists** — on the real registry (npm / PyPI), spelled exactly. A plausible-looking
  name you didn't confirm is a typosquat/hallucination risk, not a dependency.
- **It's alive** — recent releases, not archived or deprecated; prefer the maintained
  successor if one exists (see the PyPDF2 → pypdf note below).
- **It's clean** — no known CVEs for the version you'd pin (`osv.dev`, `pip-audit`,
  `npm audit`).
- **It's worth it** — a direct dependency is a permanent liability and drags in a
  transitive tree; a few lines of your own often beat it.

Treat this as an enforced checkpoint, not a judgment call — the same instinct as the
lockfile: nothing enters the tree that you didn't deliberately admit.

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
