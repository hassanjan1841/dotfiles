# Dev Environment Cheatsheet

## hass CLI
```bash
hass status       # personal dashboard
hass sync         # push dotfiles to GitHub
hass backup       # run restic backup
hass note "idea"  # quick note to obsidian inbox
hass find "term"  # search notes + projects
hass new myapp    # create new project in ~/projects
hass setup        # full ansible install (fresh machine)
hass update       # pull + apply dotfiles updates
hass tasks        # open taskwarrior
```

## Dotfiles
```bash
just sync         # commit + push dotfiles
just backup       # restic backup
just dashboard    # show dashboard
just install      # run full ansible playbook
just update       # pull + re-run ansible
just link         # re-apply all stow symlinks
just status       # git status + last backup
```

## Navigation
```bash
proj              # fuzzy project switcher (~/projects)
gco               # fuzzy git branch switch
fh                # fuzzy command history search
dots              # cd ~/dotfiles
```

## Obsidian (inside Obsidian window)
```
Alt+D             # open today's daily note
Alt+Q             # quick capture to inbox
Alt+T             # insert template
Alt+G             # open git panel
Ctrl+P            # command palette
```

## Notes flow
```
Alt+Q             # dump raw idea → inbox/inbox.md
Alt+D             # open daily note → fill focus/tasks/journal
Ctrl+N            # new permanent note → add [[links]]
Graph view        # see all connections visually
```

## Aliases
```bash
find              # fd (fast find)
grep              # rg (ripgrep)
cat               # bat (syntax highlight)
ls                # eza (icons)
df                # duf
top               # btop
notify "msg"      # send ntfy.sh + desktop notification
```

## Fresh Machine Setup
```bash
git clone https://github.com/hassanjan1841/dotfiles.git ~/dotfiles
cd ~/dotfiles && bash bootstrap.sh
```

## Secrets (~/.secrets)
```bash
RESTIC_PASSWORD   # restic backup encryption
NTFY_TOPIC        # ntfy.sh topic name
```

## Backups
- **Restic** → `~/backups` (local, runs 9am daily)
- **Dotfiles** → github.com/hassanjan1841/dotfiles
- **Notes** → github.com/hassanjan1841/notes-vault (auto every 10min)
- **Projects** → their own GitHub repos
