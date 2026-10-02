#!/usr/bin/env python3
"""PreToolUse(Artifact) hook: an independent reviewer must approve every register publish.

First the deterministic checks (lib.lint, stale PRs). Then Sonnet, run headless with no
tools and no hooks, reads only the page, what changed since the last publish and the
facts (GitHub PRs, recent commits, worker status, the leader state), never the
leader's reasoning. Any failure, including the reviewer being unavailable, refuses the
publish with the reason.
"""
import difflib
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import register_lib as lib  # noqa: E402

CLAUDE = os.environ.get("REG_CLAUDE_BIN", "claude")

RULES = """You review a work register page before it is published. Readers: Zabih (the boss) and
Matt (operations, not a developer). The page is public to anyone with the link.

Reject the publish if ANY of these is true, naming each bad row:
1. Wording: a row uses developer jargon, file paths, code or function names, branch names,
   commands, or abbreviations a non-developer would not know (PR is fine). A row must make
   sense on its own and stay short (a task over about 20 words is too long).
2. Facts: a row contradicts the FACTS (a PR state, a PR number, something claimed done
   that the facts show is not, an item in the wrong tab).
3. Missing work: an item in WORK SINCE LAST PUBLISH is Passenger work but nothing on the
   page reflects it. Ignore items that are clearly not Passenger work (personal tooling,
   security of the developer's own machine, other projects).
4. Sensitive: secrets, tokens, passwords, email addresses, security incidents or malware,
   or private details about people or clients.
Do not reject for style preferences, and do not ask for things the facts cannot show.
List only rows that must change. Never list a row that is fine or "needs no change".
If nothing must change, approve with an empty problems list.

Answer with ONLY this JSON, no other text:
{"approve": true or false, "problems": ["<row>: <what is wrong and how to fix it>", ...]}"""


def run(cmd, timeout=20, env=None):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def facts(since):
    parts = []
    slug = lib.repo_slug()
    token = run(["gh", "auth", "token", "--user", lib.GH_USER])
    prs = run(["gh", "pr", "list", "--repo", slug, "--state", "all", "--limit", "30", "--json",
               "number,state,title,baseRefName"], env={**os.environ, "GH_TOKEN": token}) if slug else ""
    parts.append("GITHUB PRS (Passenger repo):\n" + (prs or "unavailable"))
    worktrees = re.findall(r"^worktree (.+)$", run(["git", "-C", lib.REPO_DIR, "worktree", "list", "--porcelain"]), re.M)
    commits = set()
    for wt in worktrees or [lib.REPO_DIR]:
        out = run(["git", "-C", wt, "log", "--all", f"--since=@{int(since)}", "--format=%h %ad %s", "--date=short"])
        commits.update(line for line in out.splitlines() if line)
    work = sorted(commits)
    for name in ("A-status.txt", "B-status.txt", "C-status.txt"):
        path = f"{lib.BRIEFS}/{name}"
        if lib.mtime(path) > since:
            lines = open(path).read().strip().splitlines()
            work.append(f"Worker {name[0]} finished: {lines[-1][:400] if lines else ''}")
    try:
        state = "".join(open(f"{lib.LEADER}/state.md").readlines()[:45])
    except OSError:
        state = "unavailable"
    return ("\n\n".join(parts) + "\n\nLEADER STATE (top):\n" + state,
            "\n".join(work) or "nothing recorded")


def changes():
    try:
        old = json.dumps(lib.read_data(lib.LAST_COPY), indent=1).splitlines()
    except Exception:  # noqa: BLE001  no earlier copy: everything counts as new
        old = []
    new = json.dumps(lib.read_data(lib.REG), indent=1).splitlines()
    return "\n".join(difflib.unified_diff(old, new, "published", "new", n=0, lineterm="")) or "no data change"


def review():
    problems = lib.lint()
    stale, _ = lib.stale_prs()
    if problems or stale:
        return False, problems + stale
    since = lib.mtime(lib.PUBLISHED) or (time.time() - 86400)
    fact_text, work = facts(since)
    page = json.dumps(lib.read_data(lib.REG), indent=1)
    prompt = (f"{RULES}\n\n=== PAGE DATA ===\n{page}\n\n=== CHANGED SINCE LAST PUBLISH ===\n{changes()}"
              f"\n\n=== WORK SINCE LAST PUBLISH ===\n{work}\n\n=== FACTS ===\n{fact_text}")
    try:
        out = subprocess.run(
            [CLAUDE, "-p", "--model", "sonnet", "--output-format", "json",
             "--settings", '{"disableAllHooks":true}',
             "--disallowedTools", "Bash,Edit,Write,Read,Glob,Grep,WebFetch,WebSearch,Agent,NotebookEdit"],
            input=prompt, capture_output=True, text=True, timeout=170, cwd="/tmp")
        result = json.loads(out.stdout).get("result", "")
        verdict = json.loads(re.search(r"\{.*\}", result, re.S).group(0))
    except Exception as e:  # noqa: BLE001  no verdict means no publish
        return False, [f"the reviewer could not give a verdict ({type(e).__name__}); try the publish again"]
    if verdict.get("approve") is True and not verdict.get("problems"):
        return True, []
    return False, verdict.get("problems") or ["the reviewer rejected it without saying why; try again"]


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    inp = data.get("tool_input", {}) or {}
    target = os.path.realpath(os.path.expanduser(inp.get("file_path", "") or ""))
    if inp.get("action", "publish") != "publish" or inp.get("asset") or target != os.path.realpath(lib.REG):
        return
    try:
        ok, problems = review()
    except Exception as e:  # noqa: BLE001
        ok, problems = False, [f"the review itself failed ({type(e).__name__}: {e})"]
    lib.log(("review: approved" if ok else "review: refused: " + " | ".join(problems))[:600])
    if ok:
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": "Register review refused this publish. Fix, then publish again: "
                                    + " ".join(f"({i + 1}) {p}" for i, p in enumerate(problems))}}))


if __name__ == "__main__":
    main()
