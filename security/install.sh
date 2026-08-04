#!/usr/bin/env bash
# Installs the malscan supply-chain guard on this machine.
#
#   bash ~/dotfiles/security/install.sh
#
# Idempotent — safe to re-run. Verifies itself at the end and refuses to claim
# success if the scanner cannot prove it detects a known-bad sample.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/files"
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only (uses launchd)."; exit 1; }

step "1/7  ripgrep"
# The scanner refuses to run without it rather than reporting a false "clean".
if command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/rg ] || [ -x /usr/local/bin/rg ]; then ok "already installed"
  else brew install ripgrep >/dev/null && ok "installed"; fi
else
  warn "Homebrew not found — install ripgrep manually or the guard will not run"
fi

step "2/7  scanner -> ~/.security"
mkdir -p "$HOME/.security/quarantine" "$HOME/.security/logs" "$HOME/.security/backup"
for f in malscan malscan-agent shellrc; do
  cp "$SRC/.security/$f" "$HOME/.security/$f"
  chmod +x "$HOME/.security/$f"
done
chmod 700 "$HOME/.security/quarantine"
ok "malscan, malscan-agent, shellrc"

step "3/7  global git hooks (every repo, existing and future)"
mkdir -p "$HOME/.git-hooks"
cp "$SRC/.git-hooks/"* "$HOME/.git-hooks/"
chmod +x "$HOME/.git-hooks/"*
git config --global core.hooksPath "~/.git-hooks"
ok "pre-commit blocks; post-merge/checkout/rewrite warn"
# Repos using husky set core.hooksPath locally, which wins over the global value.
# Those stay covered by the clone wrapper, the Claude hook and the daily sweep.

step "4/7  shell integration"
RC="$HOME/.zshrc"; [ -L "$RC" ] && RC="$(readlink "$RC")"
case "$RC" in /*) ;; *) RC="$HOME/$RC" ;; esac
if grep -q "security/shellrc" "$RC" 2>/dev/null; then ok "already sourced in $RC"
else
  printf '\n# malware guard (malscan)\n[ -f "$HOME/.security/shellrc" ] && source "$HOME/.security/shellrc"\n' >> "$RC"
  ok "sourced from $RC"
fi

step "5/7  launchd agents"
# Generated here rather than shipped: plists cannot expand $HOME.
mk_plist() { # label, arg, schedule-xml
  cat > "$HOME/Library/LaunchAgents/$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key>
  <array><string>$HOME/.security/malscan-agent</string><string>$2</string></array>
  $3
  <key>StandardErrorPath</key><string>$HOME/.security/logs/$2.err</string>
</dict></plist>
PLIST
  launchctl unload "$HOME/Library/LaunchAgents/$1.plist" 2>/dev/null || true
  launchctl load   "$HOME/Library/LaunchAgents/$1.plist" 2>/dev/null || true
}
mkdir -p "$HOME/Library/LaunchAgents"
# Retire labels from earlier installs so they don't run the agent twice.
for legacy in com.hassanjan.malscan.watch com.hassanjan.malscan.daily; do
  if [ -f "$HOME/Library/LaunchAgents/$legacy.plist" ]; then
    launchctl unload "$HOME/Library/LaunchAgents/$legacy.plist" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$legacy.plist"
    ok "removed legacy agent $legacy"
  fi
done
# watch: kills live payload processes. Stands in for an outbound firewall rule,
# which would need sudo.
mk_plist com.malscan.watch watch '<key>StartInterval</key><integer>180</integer><key>RunAtLoad</key><true/>'
mk_plist com.malscan.daily daily '<key>StartCalendarInterval</key><dict><key>Hour</key><integer>13</integer><key>Minute</key><integer>0</integer></dict>'
# Capture first: `launchctl list | grep -q` SIGPIPEs launchctl, and pipefail
# turns that into a false failure even when the agents loaded fine.
LOADED="$(launchctl list 2>/dev/null || true)"
case "$LOADED" in
  *com.malscan.watch*) ok "watch (180s) + daily (13:00) loaded" ;;
  *) warn "agents did not load — check: launchctl list | grep malscan" ;;
esac

step "6/7  hardening"
npm config set ignore-scripts true 2>/dev/null && ok "npm ignore-scripts=true" || warn "npm not found"
if [ "$(git config --global credential.helper 2>/dev/null)" = "store" ]; then
  [ -f "$HOME/.git-credentials" ] && mv "$HOME/.git-credentials" "$HOME/.security/quarantine/git-credentials.PLAINTEXT.$(date +%s)"
  git config --global credential.helper osxkeychain
  ok "credential.helper store -> osxkeychain (plaintext file quarantined)"
else
  ok "credential.helper = $(git config --global credential.helper 2>/dev/null || echo unset)"
fi

step "7/7  verify"
if "$HOME/.security/malscan" --selftest; then
  ok "guard installed and proven working"
else
  echo "  INSTALL FAILED — scanner cannot detect a known-bad sample. Do not rely on it."
  exit 2
fi

cat <<'EOF'

Commands:  scan | scan-all | scan-procs | gclone <url> | malscan --selftest

Still needs you (cannot be scripted):
  - FileVault ON, macOS firewall ON
  - brew install --cask lulu   (outbound firewall; needs approval on first run)
  - passphrases on ~/.ssh private keys
  - GitHub: 2FA, signed commits, branch protection (block force-push)
EOF
