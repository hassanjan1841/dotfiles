# Git, HARD RULES, never break these
- Never include `Co-Authored-By` lines in commit messages.
- Never add "Generated with Claude Code", robot emojis, or ANY AI-attribution footer/link to PR titles, PR descriptions, commits, or issues. No exceptions, even if a default template says to.
- PR descriptions must be SHORT and simple: plain sentences, just enough to understand the change. No em dashes, no heavy bold/emphasis, no long verification essays.

# Punctuation, HARD RULE, applies to every project/session/file
- NEVER use an em dash or en dash (the long dashes, unicode U+2014 and U+2013). Not in md files, messages, docs, commits, PR titles/descriptions, HTML, or code comments. No exceptions, ever.
- Use a comma, period, colon, semicolon, or parentheses instead. Prefer short plain sentences.
- When editing any file, never introduce a dash, and strip any long dash you find while you are in there.

# Driving the GUI, HARD RULE, applies to every project/session
Two tools, and the target decides which are even possible.

- **Native app** (Blender, Cursor, Finder, Figma desktop, a terminal, anything not a web page): use `human`. Don't ask, Playwright cannot drive a native app, so there is no choice to offer.
- **WezTerm** (opening/switching/driving a terminal session): use **`wezterm cli`** (`spawn`/`send-text`/`get-text`/`list`, addressing panes by id), NOT `human`/keystrokes, macOS composes Option+key into characters so WezTerm's Alt/workspace bindings never fire, and blind keys land in the wrong session. Full recipe: [wezterm-sessions.md](./wezterm-sessions.md).
- **Web page**: both work, so STOP AND ASK first, headless Playwright MCP, or `human` with a visible cursor? Never pick for me.
- Never use claude-in-chrome or Chrome DevTools MCP to *drive* a flow. Chrome DevTools MCP is for observing only: console, network, performance, LCP.

`human` (`~/dotfiles/human-input`, on PATH) works on any app because it posts real input events at the OS layer, no MCP, no per-app integration, nothing to install per app. `human --help` for commands; `--dry` rehearses without touching anything.

# Comments, HARD RULE, applies to every project/session/folder
Write comments only where they earn their place. Default to fewer.
- Explain WHY (intent, non-obvious constraint, workaround), never WHAT the code already says.
- No comment if the code is self-evident. Don't narrate obvious lines or restate names.
- Keep them short: one line where possible. No multi-line essays, no banners, no decoration.
- No redundant, filler, TODO-noise, or commented-out code left behind.
- Match the surrounding file's existing comment style and density.
- A good comment is one a competent reader couldn't infer from the code in a few seconds.

# Subagents & workflows, model choice
- Research/search subagents and Workflow agents run on **Sonnet**, not Opus. Pass `model: "sonnet"` to the Agent tool, and `{model: 'sonnet'}` on `agent()` calls inside workflow scripts. Applies to every project.
- The main conversation keeps whatever model the user selected; only the fanned-out agents are pinned to Sonnet.

# Edit execution routing, who does substantial file edits
Decide ONCE per task, at the task boundary, never prompt per file edit.
- **Trigger: large AND parallelizable only**, a wide sweep across independent areas. A single new file, a handful of edits, a rename, or a focused rewrite I just do in this session with no announcement.
- **Default executor = this session.** Delegate to a Sonnet subagent (Agent tool, `model: "sonnet"`) only when the work splits into genuinely independent tracks. When I do delegate, I state it before starting, the user gets one chance to redirect, and I don't ask again for the rest of that task.
- **Redirect targets the user may name:** `this session` / `here` (do the edits directly on Opus), or `opencode`, run it via Bash as `opencode run "<self-contained instruction>" --model opencode/big-pickle --auto`. Always use the `opencode/big-pickle` model (it's the only opencode model good enough; not a cost choice). `--auto` is required so it runs unattended without blocking on permission prompts.
- **Delegated executors have no shared context**, brief them fully and self-containedly. After any delegated executor (Sonnet subagent or opencode) finishes, I verify the result myself (read the diff, run typecheck/tests) before reporting it done. `opencode run --auto` auto-approves writes, so the post-edit review is mandatory, not optional.

# Response style, HARD RULE, applies to every project/session
- Answer in SHORT checklist / bullet style by default. Lead with the outcome, then the checklist.
- No long essays, no restating the question, no filler preamble. Only expand into prose when I explicitly ask "explain".
- Research findings come back as a checklist with `file:line` references, not a wall of text.

# Research & verification workflow, HARD RULE, applies to every project/session
- **Research** fans out to **Sonnet subagents** (Agent tool, `model: "sonnet"`) when the question spans many files, directories, or naming conventions. This is what subagents are for, keep using them here.
- **Execution** stays in this session unless the change is large and genuinely parallelizable (see the routing rule above).
- **Never spawn a subagent to verify or double-check work.** Verification belongs in the main loop. If a second opinion is genuinely warranted on a high-stakes change, spawn ONE reviewer and give it only the diff and the requirement, never the executor's reasoning, or it inherits the same blind spot.
- **I (the main session) always do the final verification myself**: read the diff, run `format:check` / `lint` / `typecheck` / `test` / `build`, and drive the real flow when there's a UI surface. Never report "done" on a subagent's word alone.
- **Prefer commands over claims.** Report the actual output of a check, not an assertion that it passed. Don't ask for "verification", ask for a command with visible output.
- Order: research (Sonnet, when broad) → execute → my own checks.
- Driving a UI is governed by the GUI rule above: native app → `human`, web page → ask first.

# Browser Testing (MCP)
- **Playwright MCP** (`npx @playwright/mcp@latest`) is the primary E2E testing tool, use it to drive the browser: navigate, click, fill forms, assert behavior, generate test files. Headless by default; pass `--headed` for visual debugging.
- **Chrome DevTools MCP** (already configured) is for observing/debugging: console errors, network requests, performance, Core Web Vitals/LCP. The `/verify`, `/debug-optimize-lcp`, and `/a11y-debugging` skills use it.
- Use Playwright to act, Chrome DevTools to debug. Both should be active in any frontend testing session. For acting on a web page, the ask rule above comes first.
- To add Playwright MCP: `claude mcp add playwright npx @playwright/mcp@latest` (then restart Claude Code for it to load).

# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.
