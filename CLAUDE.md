# dotfiles

Hassan's machine setup for macOS (main) and Ubuntu. Each top-level folder is a GNU Stow package that links into `~`; `setup.yml` (Ansible) installs tools and runs the stows; `Justfile` holds the daily commands.

## Rules
- Every change to a tracked config is made here, never in the linked copy's place. Check the link is still a link after an app saves (Claude Code and Herdr can replace links with plain files; `just sync` repairs both).
- Commits: no Co-Authored-By line, no AI footer, no long dashes anywhere.
- Push as `hassanjan1841` (the repo owner). The active gh account is usually `hassanjanext`, which GitHub refuses here; Hassan runs `gh auth switch -u hassanjan1841 && git push; gh auth switch -u hassanjanext`.
- Never commit secrets: they live in `~/.secrets` (ignored). `cmux/.config/cmux/projects.local.json` stays local.
- New package: add it to `just link`, to `setup.yml`, and to the README table.

## Commands
- `just install`: full Ansible run. `just update`: pull, then install.
- `just link`: restow every package. `just herdr`, `just cmux`: set up those terminals (safe to rerun).
- `just sync`: pull back replaced links, commit everything with a timestamp, push.
- `just dry-run`, `just status`, `just backup` (restic to `~/backups`).

## Packages (folder, then where it lands)
- `zsh`, `bash`, `git`, `p10k`, `aliases`, `dev`: shell files in `~`. `dev/.devrc` sets `PROJECT_PATH`.
- `claude`: `~/.claude` (global CLAUDE.md, settings.json, skills, session recipes, statusline) and `~/.leader` (Passenger register guard scripts).
- `herdr`: `~/.config/herdr-app` (cmux-style layout, spaces-tree sidebar, settings). Herdr is the main terminal since 2026-11-08; see `docs/herdr.md`.
- `cmux`, `ghostty`: cmux look and sidebar, the fallback terminal; see `docs/cmux.md`.
- `wezterm`: older fallback terminal. `zed`: editor settings.
- `taskwarrior`, `notes` (Obsidian settings and templates), `systemd` (Ubuntu daily timer), `startup`, `autostart` (Ubuntu login launcher).

## Not stowed
- `bin/`: scripts on PATH. `cw-new` and `cw-board` start and watch Claude workers (Herdr or cmux). `glow`, `human`, `human-do`: GUI driving with the screen glow. `wa-send`: WhatsApp send with a chat check. `desktop-tidy`, `hass` (dashboard CLI), `cmux-autocolor`, `cmux-tidy`, `cmux-stop-settle` (cmux helpers).
- `human-input/`: source of the `human` tool (Swift). Read `HANDOFF.md` before changing it.
- `glow/`: source of the glow overlay. Built files are ignored.
- `security/`: malscan, the supply-chain payload guard and its git hooks; `security/install.sh` sets it up.
- `scripts/`: `daily.sh` (pull, npm update, backup) and `dashboard.sh`.
- `bootstrap.sh`, `startup-mac.sh`, `.github/workflows/test.yml` (Ansible dry run on every push).
- `CONTEXT.md` and `CHEATSHEET.md`: older notes, mostly the Ubuntu and WezTerm setup.
