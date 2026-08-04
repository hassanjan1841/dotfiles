# AI setup prompt

Paste into Claude Code (or any coding agent) on a Mac. Works on a fresh machine
or one you suspect is already infected.

---

## Prompt — copy everything below

```
Set up my supply-chain malware guard on this Mac, then check whether this machine
is already compromised. Work in this order and verify each step with real output —
do not tell me something passed unless you ran a command that shows it.

STEP 1 — INSTALL THE GUARD
If ~/dotfiles exists, run: bash ~/dotfiles/security/install.sh
Otherwise clone it first: git clone https://github.com/hassanjan1841/dotfiles.git ~/dotfiles
The installer is idempotent and ends with a self-test. If the self-test fails,
STOP and tell me — a scanner that cannot prove it detects a known-bad sample is
worthless. Then confirm:
  - malscan --selftest passes
  - git config --global core.hooksPath points at ~/.git-hooks
  - launchctl list | grep malscan shows com.malscan.watch and com.malscan.daily
  - `scan` works in any directory

STEP 2 — CHECK IF THIS MACHINE IS ALREADY INFECTED
Run `scan-all` (home + global npm tooling + node_modules) and `scan-procs`.
Then check these by hand, because they sit outside a normal scan:
  - ps -Ao pid,ppid,lstart,command | grep "node .*-e "   (legit tooling almost never runs this way)
  - /opt/homebrew/lib/node_modules/npm/lib/cli.js  — should be ~400 bytes of readable
    JS. If it is hundreds of KB on ONE line, npm itself is infected; fix with
    `brew reinstall node` after quarantining a copy.
  - ~/Library/LaunchAgents, crontab -l, login items — anything you do not recognise
  - find ~ -name "temp_auto_push.bat" -o -name "config.bat"
  - any .vscode/tasks.json containing "folderOpen" (executes on opening the folder)
For every hit, VERIFY before alarming me: check for a campaign tag — an assignment
of require onto global.r, an assignment onto global['e'], or a /*M######*/ build
stamp — and whether the file is a known benign bundle. (Written without the literal
"=" so this prompt does not trip the scanner it describes.)
Unicode escapes and whitespace padding alone are NOT proof —
emoji-regex, iconv-lite, date-fns and minified Flow parsers all trip naive rules.

STEP 3 — REPORT MY EXPOSURE (do not change anything yet)
  - fdesetup status                                   (FileVault)
  - /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
  - git config --global credential.helper             ("store" = plaintext tokens)
  - ls ~/.git-credentials
  - for each private key in ~/.ssh: does `ssh-keygen -y -P "" -f KEY` succeed?
    (success = NO passphrase = anyone reading the file becomes me)
  - count plaintext .env files: find ~ -name ".env*" -not -path "*/node_modules/*" | wc -l
  - npm config get ignore-scripts
Show me a table of what is exposed, then wait for my go-ahead.

STEP 4 — ONLY IF I SAY GO
Apply what is scriptable: npm ignore-scripts, credential.helper osxkeychain
(quarantine ~/.git-credentials, do not delete), and add the CI scanner
(scripts/scan-payload.sh + a supply-chain job) to my repos.
Tell me plainly what needs me in person: FileVault, macOS firewall, LuLu, SSH key
passphrases, GitHub 2FA and branch protection with force-push blocked.

RULES
- Never report "clean" from a scan that errored. Exit code 2 means UNKNOWN.
- Back up before touching anything: `git bundle create BACKUP --all` per repo,
  and copy any file to ~/.security/quarantine/ before modifying it.
- Do not delete repos or force-push without asking.
- If credentials were exposed, say clearly that rotation must happen from a
  DIFFERENT device, and that cleaning the machine does not un-steal them.
```

---

## If the machine turns out to be infected

Order matters — rotating keys while a C2 channel is live just hands over the new ones.

1. **Contain** — kill payload processes, quit editors/agents that respawn them
2. **Rotate every credential from another device** — GitHub tokens and SSH keys,
   cloud CLI tokens, `.env` secrets. This is the urgent part; a clean machine does
   not un-steal what already left
3. **Clean** — strip payloads (keep quarantined copies), `brew reinstall node` if
   npm was hit, delete the source repo
4. **Reboot, then re-check** — `scan-procs` and `scan-all` before opening anything.
   Nothing returns → disinfection held. Something returns → wipe
5. **Check your remotes** — a stolen token means commits you did not make. Look for
   an odd committer timezone, unsigned commits, and duplicate commit messages with
   different hashes (the signature of a force-pushed rewrite)

## Why the reboot test decides it

This family is loud but shallow: userland Node, no root, no kernel extension. It
survives by living in files that run on build, not by planting persistence. If a
reboot plus a clean scan turns up nothing, disinfection is genuinely sufficient.
If anything comes back, something persists that was not found — wipe.
