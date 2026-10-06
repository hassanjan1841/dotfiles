#!/usr/bin/env python3
"""Stop hook: the leader cannot end a reply while the daily register is behind or broken.

Blocks (once per reply) when
  1. work happened after the register was last updated. Small work (file edits,
     publishing another page) can instead be skipped with one line in register.ack;
     Passenger commits, pushes, PRs and worker status changes cannot,
  2. the page fails its content checks (lib.lint) or shows a PR as waiting that
     GitHub says is merged or closed,
  3. the register file differs from the last published version, or
  4. the guard itself fails (it reports the error instead of passing silently).
Every session counts as the leader unless it is a known worker.
"""
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import register_lib as lib  # noqa: E402

# Edits here are bookkeeping, not register-worthy work.
IGNORE_PREFIXES = tuple(os.path.realpath(p) for p in (
    lib.LEADER, lib.BRIEFS, lib.REG, f"{lib.HOME}/.claude", "/private/tmp", "/tmp",
    f"{lib.HOME}/Passenger-development/.claude",
))
# Only real commands count: quoted text and heredoc bodies are stripped first, then the
# command must start a line or follow ; & | ( so test data mentioning "git push" is ignored.
WORK_BASH = re.compile(r"(^|[;&|(])\s*(git\s+(-c\s+\S+\s+)*(commit|push)|gh\s+pr\s+(create|merge|edit|ready))(?![\w-])", re.M)
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?.*?\n.*?^\s*\1\s*$", re.S | re.M)
QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"")
TARGET_DIR = re.compile(r"(?:\bcd\s+|\bgit\s+-C\s+)(\S+)")


def real_commands(cmd):
    return QUOTED.sub("''", HEREDOC.sub("", cmd))


def is_worker(cwd=""):
    if os.environ.get("PASSENGER_ROLE") == "worker":
        return True
    try:
        panes = open(f"{lib.LEADER}/worker-panes").read().split()
    except OSError:
        panes = []
    if any(os.environ.get(k, "") in panes for k in ("WEZTERM_PANE", "CMUX_SURFACE_ID")):
        return True
    # Workers build in a linked worktree of the leader's repo; WEZTERM_PANE does not exist under cmux.
    here = os.path.realpath(cwd or os.getcwd())
    repo = os.path.realpath(lib.REPO_DIR)
    if here == repo or here.startswith(repo + os.sep):
        return False
    git = lambda *a: subprocess.run(["git", "-C", here, *a], capture_output=True, text=True).stdout.strip()
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
    return bool(common) and os.path.realpath(common) == os.path.join(repo, ".git")


def ts(entry, fallback=0.0):
    try:
        return dt.datetime.fromisoformat(entry["timestamp"].replace("Z", "+00:00")).timestamp()
    except (KeyError, ValueError, AttributeError):
        return fallback


def is_prompt(entry):
    if entry.get("type") != "user" or entry.get("isMeta"):
        return False
    content = entry.get("message", {}).get("content")
    if isinstance(content, str):
        return True
    return isinstance(content, list) and bool(content) and content[0].get("type") != "tool_result"


def passenger_git(cmd, cwd):
    """True when the git/gh command runs inside the Passenger repo: the last cd or git -C
    before it, else the session's folder, must have the Passenger repo as its origin."""
    m = WORK_BASH.search(cmd)
    dirs = TARGET_DIR.findall(cmd[:m.start()] if m else cmd)
    where = os.path.expanduser(dirs[-1]) if dirs else (cwd or lib.REPO_DIR)
    if not os.path.isabs(where):
        where = os.path.join(cwd or lib.REPO_DIR, where)
    slug = lib.repo_slug().lower()
    try:
        url = lib.subprocess.run(["git", "-C", where, "remote", "get-url", "origin"],
                                 capture_output=True, text=True, timeout=10).stdout.strip().lower()
    except (OSError, lib.subprocess.TimeoutExpired):
        return True  # cannot tell: treat as Passenger work so it is never missed
    return bool(slug) and slug in url


def work_in_reply(transcript, cwd=""):
    """(soft_at, soft_what, hard_at, hard_what) for this reply's tool calls."""
    try:
        with open(transcript) as f:
            entries = [json.loads(line) for line in f if line.strip()]
    except (OSError, ValueError):
        return 0.0, "", 0.0, ""
    start = max((i for i, e in enumerate(entries) if is_prompt(e)), default=-1)
    # An unreadable tool timestamp falls back to the reply's start: still counted as
    # work, and still cleared by a register update made during the reply.
    reply_start = ts(entries[start], time.time() - 1) if start >= 0 else time.time() - 1
    soft, soft_what, hard, hard_what = 0.0, "", 0.0, ""
    for e in entries[start + 1:]:
        if e.get("type") != "assistant":
            continue
        for part in e.get("message", {}).get("content", []) or []:
            if part.get("type") != "tool_use":
                continue
            name, inp = part.get("name", ""), part.get("input", {}) or {}
            at = ts(e, reply_start)
            if name in ("Edit", "Write", "NotebookEdit"):
                path = os.path.realpath(os.path.expanduser(inp.get("file_path", "")))
                if path and not path.startswith(IGNORE_PREFIXES) and at >= soft:
                    soft, soft_what = at, f"edited {path}"
            elif name == "Bash":
                cmd = real_commands(inp.get("command", ""))
                if WORK_BASH.search(cmd):
                    if passenger_git(cmd, cwd) and at >= hard:
                        hard, hard_what = at, "a Passenger commit, push or PR"
                    elif at >= soft:
                        soft, soft_what = at, "a commit or push outside Passenger"
            elif name == "Artifact" and inp.get("action", "publish") == "publish" and not inp.get("asset"):
                target = os.path.realpath(os.path.expanduser(inp.get("file_path", "") or ""))
                if target != os.path.realpath(lib.REG) and at >= soft:
                    soft, soft_what = at, "published another page"
    return soft, soft_what, hard, hard_what


def reasons_for(data):
    if os.environ.get("REG_TEST_RAISE"):
        raise RuntimeError("test failure")
    reasons = []
    reg_at = lib.mtime(lib.REG)
    soft, soft_what, hard, hard_what = work_in_reply(data.get("transcript_path", ""), data.get("cwd", ""))
    for name in ("A-status.txt", "B-status.txt", "C-status.txt"):
        t = lib.mtime(f"{lib.BRIEFS}/{name}")
        if t > hard:
            hard, hard_what = t, f"worker {name[0]} status changed"
    update = (f"Update {lib.REG}: move rows Next, In progress, Done; plain English a non-developer "
              "understands; no long dashes; then test it and republish.")
    if hard > reg_at:
        reasons.append(f"Work happened after the last register update ({hard_what}). This kind of work "
                       f"must go on the register; a skip note does not clear it. {update}")
    elif soft > max(reg_at, lib.mtime(lib.ACK)):
        reasons.append(f"Work happened after the last register update ({soft_what}). {update} "
                       f"If it does not belong on the register, write one line saying why to {lib.ACK}.")
    problems = lib.lint()
    stale, note = lib.stale_prs()
    if note:
        lib.log("note: " + note)
    if problems or stale:
        reasons.append("The register needs fixing: " + "; ".join(problems + stale) + ".")
    try:
        published = open(lib.PUBLISHED).read().strip()
    except OSError:
        published = ""
    if lib.sha(lib.REG) != published:
        reasons.append("The register file differs from the published page. Test it, then republish it "
                       "with the Artifact tool (same file path, same URL).")
    return reasons


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except ValueError:
        data = {}
    if is_worker(data.get("cwd", "")):
        return
    if data.get("stop_hook_active"):
        lib.log("allow: already blocked once this reply")
        return
    try:
        reasons = reasons_for(data)
    except Exception as e:  # noqa: BLE001  a broken guard must say so, never pass silently
        reasons = [f"The register guard itself failed ({type(e).__name__}: {e}). Fix "
                   f"{os.path.realpath(__file__)} and run register-guard-test.sh."]
    if reasons:
        lib.log("block: " + " | ".join(r.split(".")[0] for r in reasons))
        print(json.dumps({"decision": "block", "reason": "Daily register guard: " + " ".join(reasons)}))
    else:
        lib.log("allow: register up to date")


if __name__ == "__main__":
    main()
