# Mac hardening plan (new-system + ongoing)

Status of this doc: PLAN / TODO. The `harden.sh` script that automates the
"automatable" half is not built yet. Come back to this when ready.

Goal: not "bulletproof" (nothing is), but make a break-in hard, keep untrusted
code away from real credentials, and detect + contain fast. Written after two
supply-chain compromises (2026-08-04 and 2026-09-07, PolinRider npm campaign).

Already in place (from the incident cleanup):
- `malscan` scanner + 180s watch + daily sweep (`~/.security/`, in dotfiles)
- `install-guard.sh` quiet auto-block on malicious npm/npx/pip installs
- npm `ignore-scripts=true`, git `credential.helper=osxkeychain`

The biggest single win for this user's threat model: NEVER run client / unknown
code on the real machine. Sandbox it (see `sandbox-run` below).

---

## Automatable (to be built into `harden.sh`, idempotent + self-verifying)

- [ ] FileVault: check status, prompt to enable (user still saves recovery key)
- [ ] Application Firewall ON + stealth mode ON
- [ ] Turn OFF Remote Login (SSH), File Sharing, Remote Management (were ON)
- [ ] Screen lock: require password immediately, 1-minute auto-lock
- [ ] Gatekeeper ON (App Store + identified developers)
- [ ] Automatic security updates + Rapid Security Responses ON
- [ ] Safari: uncheck "open safe files after downloading"
- [ ] npm `ignore-scripts=true` (done), lockfile defaults, prefer `npm ci`
- [ ] Git: signed commits (SSH signing) + keychain credential helper
- [ ] Secret scanning (gitleaks) wired into pre-commit + the `gclone` clone hook
- [ ] File-integrity watch on high-value paths: global npm, `~/Library/LaunchAgents`,
      `/Library/LaunchDaemons`, `~/.ssh`, crontab, shell rc files (alert on change)
- [ ] `sandbox-run <cmd/repo>`: run untrusted code in a throwaway OrbStack
      container with NO access to home, SSH keys, or credentials
- [ ] SSH-key-without-passphrase detector: flag which private keys to fix
- [ ] Verify SIP + Secure Boot status
- [ ] Emit / update `SECURITY-CHECKLIST.md` for the manual items below

## Manual (cannot be scripted, do once per machine)

- [ ] Objective-See tools (free, quiet, alert-only):
      - BlockBlock  = alerts the instant something installs a persistence item
        (would have caught the VSCodeUpdater LaunchAgent + cron live)
      - KnockKnock  = audit everything persistently installed
      - OverSight   = mic/camera access alerts
      - ReiKey      = keylogger (event-tap) detection
      https://objective-see.org/products.html
- [ ] Add passphrases to SSH private keys (script flags them; you type them)
- [ ] Hardware security key (YubiKey) or passkeys for GitHub / Google / Apple 2FA
      (phishing-proof; beats the fake-client social engineering that hit twice)
- [ ] Password manager (1Password / Bitwarden) + unique password per site
- [ ] Little Snitch outbound firewall, tuned quiet (silent-allow for signed apps,
      alert only on unsigned/unknown outbound). Or accept NextDNS-only if the
      prompts are unbearable. NextDNS with malware/phishing blocklists is quiet.
- [ ] Daily-use account = standard (non-admin); separate admin account for installs
- [ ] Encrypted Time Machine + one offsite/cloud backup (3-2-1)
- [ ] FileVault: click enable and store the recovery key somewhere safe

## Ongoing habits

- Treat every client "test task" / take-home repo as hostile -> `sandbox-run` it
- Never pipe `curl ... | sh`; use `webrun <url>` (fetch -> scan -> show -> confirm)
- Slow down on urgency/pressure; that is the social-engineering tell
- Rotate credentials after any suspected exposure; keep 2FA on everywhere

## Also outstanding from the 2026-09-07 incident

- [ ] Remove leftover cron: give WezTerm Full Disk Access, then `crontab -r`
- [ ] Rotate all credentials from a clean device (a remote shell had run)
