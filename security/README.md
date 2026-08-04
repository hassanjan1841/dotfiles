# malscan — supply-chain payload guard

Built after a real compromise on 2026-08-04. A cloned client repo carried an
obfuscated loader hidden in `postcss.config.js`; it stole GitHub credentials,
which were then used to force-push the payload into two more repos, and it
eventually rewrote `npm`'s own `cli.js`.

Attributed to **PolinRider**, a DPRK-linked campaign that has hit 1,900+ GitHub
repositories. Notably, **every published variant-specific IOC matched none of the
samples found here** — the variant seen was newer and used Ethereum rather than
TRON/Aptos. That is why this scanner leads with structural detection, not IOC lists.

## Install

```bash
bash ~/dotfiles/security/install.sh
```

Idempotent. Ends with a self-test and exits non-zero if the scanner cannot prove
it detects a known-bad sample.

## Use

| Command | Does |
|---|---|
| `scan` | scan current directory |
| `scan-all` | whole home + global npm tooling, including `node_modules` |
| `scan-procs` | live payload processes and C2 connections |
| `gclone <url>` | clone, then scan **before** you `cd` in or install |
| `safe-install` | refuses `npm install` until the tree passes |
| `malscan --selftest` | prove the scanner still works |

**Exit codes: `0` clean, `1` findings, `2` scanner broken — which is NOT clean.**
The first version of this tool silently reported "clean" because ripgrep was
missing and `--no-messages` hid the error. It now fails closed.

## Where it hooks in

| Point | Mechanism | Catches |
|---|---|---|
| Every repo, existing and future | `core.hooksPath=~/.git-hooks` | `pre-commit` blocks; `post-merge` warns — **`git pull` is how the payload actually arrived** |
| Every clone | `gclone` in `~/.security/shellrc` | poisoned repo before `npm install` |
| Every Claude Code session | `SessionStart` hook | scans the project on open |
| Every 180s | `com.malscan.watch` | kills live payload processes (stands in for an outbound firewall, which needs sudo) |
| Daily 13:00 | `com.malscan.daily` | deep sweep, macOS notification on findings |
| CI | `scripts/scan-payload.sh` | blocks it reaching `main` |

Repos using husky set `core.hooksPath` locally, which overrides the global value.
Those stay covered by the clone wrapper, the Claude hook and the daily sweep.

## Detection rules, and why they are shaped this way

Each of these was wrong on the first attempt and fixed against real samples.

- **Hidden code after whitespace padding** — the tail must start with a non-space
  (otherwise `.{199,}` just re-matches the padding), must not start with `*`
  (JSDoc continuation lines), and must reach a runtime token like `require(` or
  `global[`. Padding alone flags minified Flow parsers and markdown tables in `.d.ts`.
- **`\uXXXX`-escaped module names only.** Bare escape density is unusable —
  `emoji-regex`, `iconv-lite`, `date-fns` locales and eslint's own
  `no-irregular-whitespace` rule are legitimately full of them.
- **Family invariant: `global.r = require` / `global.m = module`.** The loader
  stashes these so its obfuscated body can reach them. This matched **all three**
  samples across **two different variants**, while published IOCs matched none.
  This is the durable rule.
- **Published PolinRider markers** — obfuscator seeds, XOR keys, C2 domains,
  blockchain dead-drop addresses, `temp_auto_push.bat`. Bonus coverage only.
- **`.vscode/tasks.json` with `runOn: folderOpen`** — executes on opening the
  folder, which is why cloning alone can infect you.

Scans run with `--hidden --no-ignore-vcs`: nested dotdirs and `.gitignore`d paths
are exactly where a payload would hide, and both are skipped by default.

IOC literals in the scanners carry a `[x]` char class so the tools do not flag
themselves.

## Not covered by this repo

Needs a human: FileVault, macOS firewall, [LuLu](https://objective-see.org/products/lulu.html)
outbound firewall, SSH key passphrases, GitHub 2FA and branch protection.

An outbound firewall is the single highest-value addition — it would have
prompted the moment `node` dialled an unknown IP.
