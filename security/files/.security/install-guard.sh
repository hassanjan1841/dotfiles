# install-guard — quiet, auto-blocking wrappers for the ways internet code runs.
# Sourced from shellrc. Philosophy: SILENT when clean, BLOCK on a confirmed
# malicious signature. No "allow/block" nagging (that is what makes LuLu painful);
# it only ever speaks when malscan finds something known-bad.
#
# Layers this adds on top of the watch agent (which auto-kills live loaders):
#   - installs never execute package scripts        (npm ignore-scripts=true)
#   - after every install/clone, the new code is scanned; a CRITICAL hit is
#     quarantined and the command is reported as tainted (non-zero exit)
#   - npx / dlx (run-remote-now) are scanned right after fetch
#   - webrun replaces the dangerous `curl … | sh` pattern with fetch→scan→confirm
#
# Not a sandbox. For genuinely untrusted client code, still use a throwaway VM.

_IG_MALSCAN="$HOME/.security/malscan"

# Quiet scan of a path; returns non-zero and shouts only on a CRITICAL finding.
_ig_guard() { # <label> <path>
  [ -x "$_IG_MALSCAN" ] || return 0                 # never block if scanner is missing…
  "$_IG_MALSCAN" --deep --tree --quiet "$2" >/dev/null 2>&1 && return 0
  printf '\033[31m🚨 install-guard: malscan flagged code from "%s".\033[0m\n' "$1" >&2
  printf '\033[31m   Quarantined. Do NOT run/import it. Details: scan %s\033[0m\n' "$2" >&2
  return 1
}

# npm: pass everything straight through; scan only after a fetch subcommand.
npm() {
  command npm "$@"; local rc=$?
  [ "$rc" = 0 ] || return $rc
  case "${1:-}" in
    install|i|add|ci|update|up)          _ig_guard "npm $1" "${PWD}/node_modules" || return 1 ;;
    exec|create|dlx|x)                   _ig_guard "npm $1" "$HOME/.npm/_npx"      || return 1 ;;
  esac
  return $rc
}

# npx runs remote code immediately — scan the npx cache right after it fetches.
npx() {
  command npx "$@"; local rc=$?
  _ig_guard "npx" "$HOME/.npm/_npx" || return 1
  return $rc
}

# pnpm / yarn: same post-install scan, only if they exist.
if command -v pnpm >/dev/null 2>&1; then
  pnpm() {
    command pnpm "$@"; local rc=$?; [ "$rc" = 0 ] || return $rc
    case "${1:-}" in add|install|i|dlx|update) _ig_guard "pnpm $1" "${PWD}/node_modules" || return 1 ;; esac
    return $rc
  }
fi
if command -v yarn >/dev/null 2>&1; then
  yarn() {
    command yarn "$@"; local rc=$?; [ "$rc" = 0 ] || return $rc
    case "${1:-}" in add|install|"") _ig_guard "yarn ${1:-install}" "${PWD}/node_modules" || return 1 ;; esac
    return $rc
  }
fi

# pip: scan a package's installed files after install (best-effort, quiet).
if command -v pip3 >/dev/null 2>&1 || command -v pip >/dev/null 2>&1; then
  _ig_pip() { local bin="$1"; shift; command "$bin" "$@"; local rc=$?; [ "$rc" = 0 ] || return $rc
    case "${1:-}" in install) _ig_guard "$bin install" "$(command "$bin" -c 'import site;print(site.getusersitepackages())' 2>/dev/null || echo "$HOME")" || return 1 ;; esac
    return $rc; }
  command -v pip3 >/dev/null 2>&1 && pip3() { _ig_pip pip3 "$@"; }
  command -v pip  >/dev/null 2>&1 && pip()  { _ig_pip pip  "$@"; }
fi

# Safe replacement for `curl <url> | sh`: fetch, scan, SHOW it, then confirm.
webrun() { # <url>
  [ -n "${1:-}" ] || { echo "usage: webrun <url>"; return 2; }
  local t; t=$(mktemp -d); local f="$t/script"
  command curl -fsSL "$1" -o "$f" || { echo "download failed"; rm -rf "$t"; return 1; }
  if ! _ig_guard "webrun $1" "$t"; then rm -rf "$t"; return 1; fi
  printf '\033[2m── first 40 lines of %s ──\033[0m\n' "$1"; head -40 "$f"
  printf '\033[33mRun this script? [y/N] \033[0m'; read -r a
  case "$a" in y|Y) sh "$f" ;; *) echo "skipped." ;; esac
  rm -rf "$t"
}
