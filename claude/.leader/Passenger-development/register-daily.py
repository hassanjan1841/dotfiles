#!/usr/bin/env python3
"""Daily 18:00 check (launchd): catches what no Claude hook sees, then sends a macOS notification.

- register content problems and PR rows GitHub has moved on from (merged or closed outside Claude)
- open PRs the register does not mention at all
- the guard's own test suite failing (for example after a Claude Code update)
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import register_lib as lib  # noqa: E402

HERE = os.path.dirname(os.path.realpath(__file__))


def notify(text):
    if os.environ.get("REG_NO_NOTIFY"):
        print("NOTIFY:", text)
        return
    script = f'display notification {json.dumps(text[:230])} with title "Daily register" sound name "Funk"'
    subprocess.run(["osascript", "-e", script], timeout=10)


def main():
    issues = lib.lint() + lib.stale_prs(states=lib.pr_states(max_age=0))[0]
    states = lib.pr_states() or {}
    try:
        text = json.dumps(lib.read_data())
        named = {int(n) for n in re.findall(r"PR #(\d+)", text)}
        missing = sorted(n for n, s in states.items() if s == "OPEN" and n not in named)
        if missing:
            issues.append("open PRs not on the register: " + ", ".join(f"#{n}" for n in missing))
    except Exception as e:  # noqa: BLE001
        issues.append(f"could not read the register ({e})")
    test = None if os.environ.get("REG_DAILY_SKIP_TESTS") else subprocess.run(
        ["zsh", f"{HERE}/register-guard-test.sh"], capture_output=True, text=True, timeout=600)
    if test and test.returncode != 0:
        fails = [l for l in test.stdout.splitlines() if l.startswith("FAIL")]
        issues.append(f"guard tests failing ({len(fails) or 'unknown'}): " + "; ".join(fails[:3]))
    lib.log("daily: " + ("; ".join(issues) if issues else "all good")[:600])
    if issues:
        notify("Register needs attention: " + "; ".join(issues))
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
