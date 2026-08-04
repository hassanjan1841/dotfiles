#!/usr/bin/env bash
# Supply-chain payload scanner. Runs in CI on every PR and locally via the
# global pre-commit hook. Catches the injection family that hit this repo on
# 2026-08-02: a loader hidden on one line behind ~280 spaces in postcss.config.js.
#
#   scripts/scan-payload.sh [PATH]   scan PATH (default: repo root)
#   scripts/scan-payload.sh --selftest
#
# Exit 0 clean, 1 findings, 2 scanner broken (NOT clean — never treat as pass).

set -uo pipefail

MODE=scan; TARGET=""
for a in "$@"; do
  case "$a" in
    --selftest) MODE=selftest ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
    *) TARGET="$a" ;;
  esac
done
TARGET="${TARGET:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"

command -v grep >/dev/null 2>&1 || { echo "scan: grep missing — scan did NOT run"; exit 2; }

# Executable code hidden after whitespace padding. The tail must start with a
# non-space (else it re-matches the padding) and reach a runtime token (else
# padded comment banners and markdown tables in .d.ts files trip it).
# Bound stays under 255: POSIX RE_DUP_MAX makes BSD grep reject anything larger,
# and both observed variants put the token immediately after the padding anyway.
R_HIDDEN='[[:blank:]]{100,}[^[:blank:]*].{0,200}(require\(|global\[|global\.[a-z]|eval\(|Function\(|child_process|process\.env)'
# A module name written as \uXXXX escapes. Bare escape density is NOT usable —
# emoji-regex, iconv-lite and date-fns locales are legitimately full of them.
R_UNIESC='require\(["'"'"'](\\u[0-9a-fA-F]{4}){3,}'
# Known literals and build stamps from this campaign.
R_IOC='166\.88\.134\.62|a322[eE]5[fF]3[dD]311[dD]3080e6f0121063e9a[dD][cC]2490[eE]f1a|"Sec[-]V"|/0x/(clb|cls)|/\*M[0-9]{6}[A-Z]?\*/'

EXCLUDES=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.next
          --exclude-dir=coverage --exclude-dir=dist --exclude-dir=build
          --exclude='*.map' --exclude='*.min.js' --exclude='*.lock'
          # This file carries the IOC literals as detection patterns, so it
          # matches itself. Excluding by name keeps the signal honest.
          --exclude='scan-payload.sh')

scan() {
  local root="$1" found=0 out
  for rule in "HIDDEN:$R_HIDDEN" "UNIESC:$R_UNIESC" "IOC:$R_IOC"; do
    local name="${rule%%:*}" pat="${rule#*:}"
    out=$(grep -rlE "${EXCLUDES[@]}" -- "$pat" "$root" 2>/dev/null)
    local rc=$?
    [ "$rc" -le 1 ] || { echo "scan: grep failed (exit $rc) — scan did NOT complete"; exit 2; }
    if [ -n "$out" ]; then
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        echo "::error file=${f#"$root"/}::Possible injected payload ($name)"
        echo "  CRITICAL [$name] $f"
        found=1
      done <<< "$out"
    fi
  done
  return $found
}

selftest() {
  local t; t=$(mktemp -d) ok=1
  # Sample deliberately avoids literal campaign IOC strings — this file must not
  # trip the scanners that read it (the pre-commit hook scans the repo it lives in).
  printf 'module.exports={};%srequire("\\u0068\\u0074\\u0074\\u0070");\n' \
    "$(printf ' %.0s' $(seq 1 300))" > "$t/bad.js"
  printf '/**\n *%s@author Someone\n */\nmodule.exports={};\n' \
    "$(printf ' %.0s' $(seq 1 300))" > "$t/benign.js"
  printf 'export const a = 1;\n' > "$t/clean.ts"
  local out; out=$(scan "$t")
  grep -q "bad.js"    <<<"$out" || { echo "FAIL: missed known-bad sample"; ok=0; }
  grep -q "benign.js" <<<"$out" && { echo "FAIL: false positive on padded JSDoc"; ok=0; }
  grep -q "clean.ts"  <<<"$out" && { echo "FAIL: false positive on clean file"; ok=0; }
  rm -rf "$t"
  [ "$ok" = 1 ] && { echo "selftest PASSED"; return 0; }
  echo "selftest FAILED — scanner cannot be trusted"; return 2
}

if [ "$MODE" = selftest ]; then selftest; exit $?; fi

echo "Scanning $TARGET for injected payloads..."
if scan "$TARGET"; then
  echo "✓ clean — no injected payload found"
  exit 0
fi
echo
echo "Injected payload detected. This is how the 2026-08-02 compromise reached main."
echo "Inspect the file(s) above; do NOT install or build until resolved."
exit 1
