#!/usr/bin/env python3
"""PreToolUse hook: any change to the register guard needs Hassan's explicit approval.

Covers Edit/Write/NotebookEdit on the guard files and shell commands that would modify
them (redirects, sed -i, mv, rm, cp, tee, chmod, ln, inline python). Running the
scripts or reading them stays free.
"""
import json
import os
import re
import sys

HOME = os.path.expanduser("~")
L = f"{HOME}/.leader/Passenger-development/"
PROTECTED = [
    f"{HOME}/dotfiles/claude/.leader/Passenger-development/",
    L + "register_lib.py", L + "register-guard.py", L + "register-review.py", L + "register-published.py",
    L + "register-daily.py", L + "register-protect.py", L + "register-guard-test.sh",
    L + "register.published", L + "register.last-published.html", L + "worker-panes",
    f"{HOME}/Passenger-development/.claude/settings.local.json",
    f"{HOME}/Library/LaunchAgents/com.passenger.register-daily.plist",
    f"{HOME}/.claude/settings.json", f"{HOME}/dotfiles/claude/.claude/settings.json",
]
TARGET = r"(register[-_](guard|lib|review|published|daily|protect)\S*|register\.(published|last-published)\S*|worker-panes|settings\.local\.json|com\.passenger\.register-daily\S*|claude/\.leader\S*|\.claude/settings\.json)"
NAMES = re.compile(TARGET)
# A redirect INTO a protected file, or a command that changes files while naming one.
REDIRECT = re.compile(r">>?\s*['\"]?[^\s'\"]*" + TARGET)
MUTATE = re.compile(r"\bsed\s+-i|\bmv\s|\brm\s|\bcp\s|\btee\s|\bchmod\s|\bln\s|\btruncate\s|\bpython3?\s+-\s|\.write\(|\bperl\s+-[pi]|\bunlink\b")


def protected_path(path):
    if not path:
        return False
    real = os.path.realpath(os.path.expanduser(path))
    candidates = {real, os.path.abspath(os.path.expanduser(path))}
    return any(c.startswith(p) for c in candidates for p in PROTECTED)


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    name, inp = data.get("tool_name", ""), data.get("tool_input", {}) or {}
    hit = ""
    if name in ("Edit", "Write", "NotebookEdit") and protected_path(inp.get("file_path") or inp.get("notebook_path")):
        hit = inp.get("file_path") or inp.get("notebook_path")
    elif name == "Bash":
        cmd = inp.get("command", "")
        if REDIRECT.search(cmd) or (NAMES.search(cmd) and MUTATE.search(cmd)):
            hit = "a shell command that changes the register guard"
    if hit:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "ask",
            "permissionDecisionReason": f"Register guard is protected: Claude wants to change {hit}. Approve only if you asked for it."}}))


if __name__ == "__main__":
    main()
