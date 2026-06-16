# Git
- Never include `Co-Authored-By` lines in commit messages.

# Browser Testing (MCP)
- **Playwright MCP** (`npx @playwright/mcp@latest`) is the primary E2E testing tool — use it to drive the browser: navigate, click, fill forms, assert behavior, generate test files. Headless by default; pass `--headed` for visual debugging.
- **Chrome DevTools MCP** (already configured) is for observing/debugging: console errors, network requests, performance, Core Web Vitals/LCP. The `/verify`, `/debug-optimize-lcp`, and `/a11y-debugging` skills use it.
- Use Playwright to act, Chrome DevTools to debug. Both should be active in any frontend testing session.
- To add Playwright MCP: `claude mcp add playwright npx @playwright/mcp@latest` (then restart Claude Code for it to load).

# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.
