# /dg pre-review — the command a project wires

Read by `/dg` step 2 when a project runs a CLI as its pre-reviewer: what the command
must do, why, and an example from each side. The completion check, the header forms and
the same-family fallback stay in step 2 — they apply to every pre-review, wired or not.

The preference is symmetric and names no vendor: whichever model drives the personas,
the pre-reviewer should be a different one — the roles swap freely depending on which
assistant a project runs as its main. A project wires the concrete command for
whichever CLI it has in its extensions. The command:
- **names no model.** Which model a CLI runs is the user's choice, made in that CLI's
  own config, and with none there the CLI's default follows its releases. A pin
  anywhere can go stale, the config included — when a configured model is refused, the
  run fails and step 2's warning names the config line: a `model = "gpt-5.5"` pin in
  `~/.codex/config.toml` failed Codex pre-reviews on 2026-09-09 (*"does not exist or
  you do not have access to it"*) and 2026-10-16 (*"not supported"*),
  `gpt-5.2-codex` the same way on 2026-05-20;
- **sets effort to `high`** with the CLI's own flag where it has one, so a review
  never runs at a `medium` default. Where it has none, say so in the header. An
  unknown level failed loudly in `codex` and `agy` (2026-10-16), which is step 2's
  warning; a CLI that may ignore it silently is treated as having none;
- **runs read-only, or tells the reviewer to use no tools** where the CLI has no
  read-only mode — a denied tool call in headless mode is a dead turn. No tools means
  none from MCP servers or plugins either: `claude -p --tools ""` still loaded
  every connected MCP server's tools until `--strict-mcp-config` (2026-10-16);
- **feeds the brief and subject the way the CLI reads them** — `agy -p` ignored
  piped stdin and answered nothing (agy 1.4.0, 2026-10-16). A CLI that takes the
  prompt only as an argument gets a large range split by subsystem, as in `/dg` step 1;
- **keeps the final message and stderr apart**, for the completion check;
- **reports the model that actually ran** in the header, read from the CLI's output
  or log, else `model unreported`. A CLI is not a family: `agy` also serves Claude
  models. A run whose model is the same family as the one running this skill, or
  unreported, counts but not as cross-family: `✅ <reviewer> (<model>, not
  cross-family)`.

E.g. from Claude Code:
`out=$(mktemp) err=$(mktemp);`
`cat <brief> <subject> | codex exec -s read-only -c model_reasoning_effort=high -o "$out" - 2>"$err"`
(stdin, so a large diff is not squeezed through one argument; `$out`, fresh each run,
holds the final message the completion check reads, `$err` the reason it failed, and
its `model:` line the model that ran). From Codex:
`cat <brief> <subject> | claude -p --effort high --tools "" --strict-mcp-config --output-format json > "$out" 2>"$err"`
(`.result` is the final message, the keys of `.modelUsage` the model that ran).
