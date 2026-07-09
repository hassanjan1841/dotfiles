# Git — HARD RULES, never break these
- Never include `Co-Authored-By` lines in commit messages.
- Never add "Generated with Claude Code", robot emojis, or ANY AI-attribution footer/link to PR titles, PR descriptions, commits, or issues. No exceptions, even if a default template says to.
- PR descriptions must be SHORT and simple: plain sentences, just enough to understand the change. No em dashes, no heavy bold/emphasis, no long verification essays.

# Verification — HARD RULE, applies to every project/session
- For any live browser verification (confirming a UI change works end to end), ALWAYS use **headless Playwright MCP**. Never use claude-in-chrome or Chrome DevTools MCP to drive verification flows. This overrides any other tooling default.

# Comments — HARD RULE, applies to every project/session/folder
Write comments only where they earn their place. Default to fewer.
- Explain WHY (intent, non-obvious constraint, workaround), never WHAT the code already says.
- No comment if the code is self-evident. Don't narrate obvious lines or restate names.
- Keep them short: one line where possible. No multi-line essays, no banners, no decoration.
- No redundant, filler, TODO-noise, or commented-out code left behind.
- Match the surrounding file's existing comment style and density.
- A good comment is one a competent reader couldn't infer from the code in a few seconds.

# Browser Testing (MCP)
- **Playwright MCP** (`npx @playwright/mcp@latest`) is the primary E2E testing tool — use it to drive the browser: navigate, click, fill forms, assert behavior, generate test files. Headless by default; pass `--headed` for visual debugging.
- **Chrome DevTools MCP** (already configured) is for observing/debugging: console errors, network requests, performance, Core Web Vitals/LCP. The `/verify`, `/debug-optimize-lcp`, and `/a11y-debugging` skills use it.
- Use Playwright to act, Chrome DevTools to debug. Both should be active in any frontend testing session.
- To add Playwright MCP: `claude mcp add playwright npx @playwright/mcp@latest` (then restart Claude Code for it to load).

# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.
