# dotfiles

Hassan's whole machine setup: macOS (main, Apple Silicon) and Ubuntu (older). Each top-level folder with dotfiles inside is a GNU Stow package linked into `~`. `setup.yml` (Ansible) installs tools and runs the stows; `Justfile` has the daily commands. The repo must live at `~/dotfiles` (many paths are hardcoded).
This file is the map: read it instead of exploring. Facts were checked on 2026-11-08; "to check" marks what was not.

## Rules for working here
- Edit the file here, never the linked copy's place. After any app saves its config, check the link is still a link (`ls -la`): Claude Code and Herdr can replace links with plain files; `just sync` repairs those two.
- Commits: no Co-Authored-By line, no AI footer, no long dashes (U+2014, U+2013) anywhere. Strip long dashes in any file you touch.
- Commit only what the task changed (`git add <files>`), never `git add -A`. `just sync` does add everything, so do not run it on someone's behalf.
- Never commit secrets: they live in `~/.secrets` (ignored, not present on this Mac). `~/.config/cmux/projects.local.json` stays local.
- New stow package: add it to `just link`, to `setup.yml`, to the README table and to this file.
- `claude/.claude/settings.json` is guarded: a PreToolUse hook (`register-protect.py`) blocks edits to it without Hassan's explicit approval. Ask first.
- Do not loosen security: keep `core.hooksPath=~/.git-hooks`, npm `ignore-scripts=true`, the shellrc line in `zsh/.zshrc`, and malscan failing closed (see Security).

## Pushing
- Remote: `https://github.com/hassanjan1841/dotfiles.git`, branch `main`, commits go straight to `main` (no PRs).
- GitHub only accepts `hassanjan1841`. The active gh account is usually `hassanjanext` (403). SSH has no key on GitHub (fails).
- Claude cannot switch accounts itself (blocked). Commit, then give Hassan this to run:
  `! gh auth switch -u hassanjan1841 && git -C ~/dotfiles push origin main; gh auth switch -u hassanjanext`
- Every push to `main` runs CI (below).

## just commands (`Justfile`)
- `just install`: Ansible playbook (asks for sudo once). `just update`: `git pull`, then install.
- `just link`: restows every package; Ubuntu-only ones run on Linux only; ends with a list of packages a real file blocked.
- `just herdr`: links the Herdr package (backs up real files first) and switches to the cmux-style layout.
- `just cmux`: installs cmux, links ghostty and cmux, builds `glow` and `human`, adds the cmux Stop hook to Claude settings.
- `just sync`: pulls back replaced Claude/Herdr links, then `git add -A`, timestamp commit, push (push fails as `hassanjanext`).
- `just status`, `just dry-run`, `just backup` (restic to `~/backups`, needs `RESTIC_PASSWORD`), `just dashboard`, `just zsh-profile`.
- Old: `just keys` (WezTerm bindings), `just tasks` (taskwarrior, not installed here). The `project` variable is unused.
- The zsh `just()` wrapper (`aliases/.aliases`) runs `~/dotfiles/Justfile` from any folder.

## New machine
1. `bash <(curl -fsSL https://raw.githubusercontent.com/hassanjan1841/dotfiles/main/bootstrap.sh)`: sudo once, Homebrew (macOS) or apt, git/ansible/just, clones to `~/dotfiles`, runs `just install` then `just link`.
2. Create `~/.secrets` (TAVILY_API_KEY, RESTIC_PASSWORD, NTFY_TOPIC).
3. macOS: install the Herdr app by hand, open it once, run `just herdr`. Grant `human` its permissions (docs/cmux.md).
4. Run `bash ~/dotfiles/security/install.sh` (malscan; not part of `just install`).
- `setup.yml`: brew formulae and casks (macOS) or apt repos (Ubuntu), NVM + Node LTS, global npm (claude-code, vercel, typescript, pnpm, biome, lighthouse, opencode-ai, bitwarden cli, tldr), Bun, uv, Oh My Zsh + plugins + powerlevel10k, pre-commit, `~/notes` folders, stows, the daily job. Most tasks have `ignore_errors: true`, so a green run can hide failures.

## Packages (folder: where it lands, state on this Mac)
- `zsh`: `~/.zshrc` (linked). Oh My Zsh + p10k; PATH adds `~/dotfiles/bin`, `~/.local/bin`, `~/.atuin/bin`; lazy nvm; sources `~/.secrets`, `~/.devrc`, `~/.aliases`, atuin, `~/.security/shellrc`; `killport`, `killdev`; daily dashboard once per day; runs `cmux-autocolor` inside cmux.
- `aliases`: `~/.aliases` (linked): eza/bat/fd/rg/duf aliases, git shortcuts, `dots`, `just()` wrapper, `notify()`, `proj()`.
- `git`: `~/.gitconfig` (linked): user Hassan Jan, gh credential helper, `core.hooksPath=~/.git-hooks`, includeIf for `~/ehtisham-all-projects/`.
- `p10k`: `~/.p10k.zsh` (linked, generated; use `p10k configure`). `bash`: `~/.bashrc` (blocked, real file here).
- `dev`: `~/.devrc` (not linked here): `PROJECT_PATH` (old speaklogic project), `NOTES_DIR`.
- `claude`: `~/.claude` (CLAUDE.md, settings.json, statusline, session recipes, skills) and `~/.leader` (register guard). File-level links (`--no-folding`). Details below.
- `herdr`: `~/.config/herdr-app` (linked): `layouts/cmux-style.json`, `mods/spaces-tree/{main.js,mod.json}`, `settings.json`. See docs/herdr.md. Herdr does not hot-reload an edit made here: `touch -h` the linked file in `~/.config/herdr-app`, then `herdr-app check` the mod.
- `cmux`: `~/.config/cmux/cmux.json` + `projects.example.json` (linked). `ghostty`: `~/.config/ghostty/config` (linked, read by cmux).
- `wezterm`: `~/.wezterm.lua` (linked, older fallback). `zed`: target `~/.config/zed` (blocked, real `settings.json` there).
- `taskwarrior`, `notes` (Obsidian settings and templates for `~/notes/hassanjan`): not linked here, tools not installed.
- Ubuntu only: `startup` (`~/startup.sh`), `autostart` (GNOME), `systemd` (daily timer).

## Claude Code setup (`claude/`)
- `.claude/CLAUDE.md`: Hassan's global rules for every project (git, no long dashes, GUI driving, comments, Sonnet for research, response style, docs shape, fast checks, machine health, workers).
- `.claude/settings.json` hooks: atuin on Bash; malscan on SessionStart (warns if a project is flagged); `register-protect.py` on Edit/Write/Bash; `cmux-stop-settle` on Stop; a UserPromptSubmit reply-style note. Also plugins, marketplaces, statusline, `effortLevel` high, `CLAUDE_CODE_PLUGIN_DIRS` (local dev-mods).
- `.claude/skills/`: `go`, `proof`, `simple`, `stories` (Passenger), `verify`, `workers` (cw-new/cw-board). Other skills in `~/.claude/skills` are not from this repo.
- `.claude/statusline-command.sh`: branch, model + effort, ctx/5h/7d percentages.
- `.claude/cmux-sessions.md`, `.claude/wezterm-sessions.md`: how to drive those terminals.
- `.leader/Passenger-development/`: the Passenger daily register guard (`register_lib.py` shared; `register-protect.py` global hook; `register-review.py` and `register-published.py` wired in `~/Passenger-development/.claude/settings.local.json`; `register-daily.py` via launchd `com.passenger.register-daily` at 18:00; `register-guard-test.sh` tests).

## Terminals
- Herdr: main since 2026-11-08. Drive it with `herdr-app` and `hc` (see global CLAUDE.md). The app and `~/.local/bin/{hc,herdr-app}` are installed by hand, not by this repo.
- cmux: fallback (main 2026-10-03 to 2026-11-08). Its CLI only works from shells started inside cmux. docs/cmux.md.
- WezTerm: older fallback, still linked.

## Tools (`bin/` is on PATH; not stowed)
- `cw-new`, `cw-board`: start and watch Claude workers; Herdr or cmux, picked automatically, `CW_BACKEND=herdr|cmux` forces one. Herdr workers open as background tabs.
- `human`: wrapper that pings `glow`, then runs `human-input/human` (Swift binary, built by `just cmux` or `human-input/build.sh`; gitignored). `human-do` and `wa-send` link into `human-input/`. Read `human-input/HANDOFF.md` before changing it; its push and machine notes are old.
- `glow`: screen-edge "Claude is using your Mac" overlay; `glow on|off|status|test`; source `glow/glow.swift`, binary gitignored.
- `cmux-autocolor`, `cmux-tidy`, `cmux-stop-settle`: cmux-only helpers (project colours and groups, Stop-hook fix).
- `desktop-tidy`: keeps `~/Desktop` empty (launchd `com.hassan.desktop-tidy`; `install` restarts Finder).
- `hass`: older personal CLI (dashboard, notes, `new` makes WezTerm projects).
- Other `com.hassan.*` launchd jobs on this Mac (upwork, leads, chrome-backup...) are not defined in this repo.

## Security (`security/`)
- malscan guards against the PolinRider supply-chain payload (incidents 2026-08-04 and 2026-09-07). `security/install.sh` installs `~/.security/`, global git hooks in `~/.git-hooks`, the shellrc line, launchd `com.malscan.watch` and `com.malscan.daily`, and hardening (npm ignore-scripts, osxkeychain).
- Commands: `scan`, `scan-all`, `scan-procs`, `gclone`, `safe-install`, `malscan --selftest`. Exit 2 means the scanner is broken, not clean.
- IOC strings in the scanners use a `[x]` character class on purpose so they do not flag themselves: do not "clean" them.
- A pre-commit hit is real until proven otherwise; never reach for `--no-verify` by habit.
- `HARDENING-PLAN.md` is a plan only; `files/ci/*` are templates not wired into CI.

## Daily jobs
- `scripts/daily.sh`: pull dotfiles, `npm update -g`, restic backup, clean `~/.cache`, ntfy message. Ubuntu: systemd timer at 09:00. macOS: launchd `com.hassan.daily` written by setup.yml (not installed on this Mac).
- `scripts/dashboard.sh`: system and repo summary, shown once a day by zsh.

## CI and pre-commit
- `.github/workflows/test.yml` on push to `main`: Ansible `--check` on Ubuntu and macOS, and a stow dry run for aliases, autostart, bash, claude, dev, git, p10k, startup, taskwarrior, wezterm, zed (not cmux, ghostty, herdr, notes, systemd).
- `.pre-commit-config.yaml`: whitespace, end-of-file, JSON/YAML checks, 1 MB file limit, no `.secrets`, no hardcoded secrets. Installed by setup.yml; not installed on this Mac.

## Known issues (not fixed yet)
- Not installed on this Mac: ansible, restic, pre-commit, taskwarrior; `~/.secrets`, `~/.devrc`, `~/notes` missing, so backups and the daily job cannot run.
- `~/.bashrc` and `~/.config/zed/settings.json` are real files, so `bash` and `zed` are not linked.
- Global CLAUDE.md still has a `graphify` section, but that skill is not installed.
- `zsh/.zshrc:370` adds `/Users/macbookair/.opencode/bin` (another machine's path).
- setup.yml installs atuin from a Linux tarball with no OS check (to check on a fresh Mac).
- `startup-mac.sh` Dev Mode opens Terminal.app, not Herdr; `CONTEXT.md` and `CHEATSHEET.md` are mostly the old Ubuntu/WezTerm setup.
- README and the `backup` comment mention backing up a project folder; the code backs up dotfiles and notes only.
