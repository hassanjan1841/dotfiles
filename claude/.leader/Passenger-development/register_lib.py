"""Shared checks for the daily register guard, reviewer and daily job."""
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import time

HOME = os.path.expanduser("~")
LEADER = os.environ.get("REG_LEADER_DIR", f"{HOME}/.leader/Passenger-development")
REG = os.environ.get("REG_FILE", f"{HOME}/Passenger-research/daily-register.html")
BRIEFS = os.environ.get("REG_BRIEFS_DIR", f"{HOME}/Passenger-worker-briefs")
REPO_DIR = os.environ.get("REG_REPO_DIR", f"{HOME}/Passenger-development")
PUBLISHED = f"{LEADER}/register.published"
LAST_COPY = f"{LEADER}/register.last-published.html"
ACK = f"{LEADER}/register.ack"
LOG = f"{LEADER}/register-guard.log"
PR_CACHE = f"{LEADER}/register.pr-cache.json"
GH_USER = os.environ.get("REG_GH_USER", "hassanjanext")
DASHES = re.compile("[\u2013\u2014]")
# The only statuses allowed in In progress and Next, so every reader knows what each means.
STATUSES = [r"To do", r"To plan", r"Decided by Zabih", r"Needs Zabih", r"Waiting for Zabih's OK",
            r"PR #\d+, waiting for Zabih's review", r"Maybe done in PR #\d+",
            r"Built and checked, PR next", r"In progress: [^.]{3,60}"]
STATUS_RE = re.compile("^(" + "|".join(STATUSES) + ")$")

# The page reads its data with node, the same engine the browser uses.
_EXTRACT = r"""
const vm = require('vm'), fs = require('fs');
const html = fs.readFileSync(process.argv[1], 'utf8');
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const el = () => ({ innerHTML: '', textContent: '', addEventListener() {}, setAttribute() {}, dataset: {} });
const ctx = { document: { getElementById: el, querySelectorAll: () => [] },
              location: { hash: '' }, history: { replaceState() {} } };
const code = scripts[scripts.length - 1] +
  '\n;JSON.stringify({PROGRESS, NEXT, DONE, PAST: typeof PAST === "undefined" ? null : PAST})';
process.stdout.write(vm.runInNewContext(code, ctx, { timeout: 2000 }));
"""


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(f"{dt.datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n")
    except OSError:
        pass


def mtime(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return 0.0


def sha(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return ""


def read_data(path=REG):
    """The page's data arrays, or raises with the reason the page would break."""
    out = subprocess.run(["node", "-e", _EXTRACT, path], capture_output=True, text=True, timeout=20)
    if out.returncode != 0:
        raise ValueError("the page script does not run: " + (out.stderr.strip().splitlines() or ["?"])[-1])
    return json.loads(out.stdout)


def day_label(d):
    return f"{d:%a} {d.day} {d:%b}"


def lint(path=REG, today=None):
    """Structural problems a reader would notice. Empty list means the page is sound."""
    today = today or dt.date.today()
    problems = []
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        return [f"cannot read the register: {e}"]
    n = len(DASHES.findall(text)) + len(re.findall(r"\\u201[34]", text, re.I))
    if n:
        problems.append(f"{n} long dash(es) in the page; use commas, colons or full stops")
    try:
        data = read_data(path)
    except (ValueError, subprocess.TimeoutExpired, json.JSONDecodeError) as e:
        return problems + [str(e)]
    if data.get("PAST") is None:
        problems.append("the page has no PAST array (Past months)")
    tasks = {}
    for tab in ("PROGRESS", "NEXT"):
        for i, row in enumerate(data.get(tab) or []):
            if not (isinstance(row, list) and len(row) == 3 and all(isinstance(c, str) and c.strip() for c in row)):
                problems.append(f"{tab} row {i + 1} must be [area, task, status], all filled")
                continue
            if not STATUS_RE.match(row[2].strip()):
                problems.append(f'{tab} status "{row[2]}" is not one of the allowed statuses')
            key = row[1].strip().lower()
            if key in tasks:
                problems.append(f'"{row[1]}" appears in both {tasks[key]} and {tab}')
            tasks[key] = tab
    labels = []
    for day in data.get("DONE") or []:
        label = (day or {}).get("date", "")
        labels.append(label)
        try:
            d = dt.datetime.strptime(f"{label} {today.year}", "%a %d %b %Y").date()
            if d > today:
                d = d.replace(year=d.year - 1)
        except ValueError:
            problems.append(f'Done date "{label}" must look like "{day_label(today)}"')
            continue
        if (d.year, d.month) != (today.year, today.month):
            problems.append(f'Done day "{label}" is from an earlier month; move it to PAST')
        for i, row in enumerate(day.get("rows") or []):
            if not (isinstance(row, list) and len(row) == 3 and all(isinstance(c, str) and c.strip() for c in row)):
                problems.append(f'Done "{label}" row {i + 1} must be [area, what, status], all filled')
            elif row[1].strip().lower() in tasks:
                problems.append(f'"{row[1]}" is in Done and also in {tasks[row[1].strip().lower()]}')
        if not day.get("rows"):
            problems.append(f'Done day "{label}" has no rows')
    if len(set(labels)) != len(labels):
        problems.append("a Done day appears twice; merge its rows")
    return problems


def repo_slug():
    try:
        url = subprocess.run(["git", "-C", REPO_DIR, "remote", "get-url", "origin"],
                             capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""
    m = re.search(r"github\.com[:/](.+?)(\.git)?$", url)
    return m.group(1) if m else ""


def pr_states(max_age=600):
    """{number: state} for the Passenger repo, cached for 10 minutes. None if GitHub is unreachable."""
    if "REG_PR_STATES" in os.environ:  # tests: a fixed answer instead of GitHub
        fixed = json.loads(os.environ["REG_PR_STATES"])
        return None if fixed is None else {int(k): v for k, v in fixed.items()}
    try:
        cache = json.load(open(PR_CACHE))
        if time.time() - cache["at"] < max_age:
            return {int(k): v for k, v in cache["states"].items()}
    except (OSError, ValueError, KeyError):
        pass
    slug = repo_slug()
    if not slug:
        return None
    try:
        token = subprocess.run(["gh", "auth", "token", "--user", GH_USER],
                               capture_output=True, text=True, timeout=10).stdout.strip()
        out = subprocess.run(["gh", "pr", "list", "--repo", slug, "--state", "all", "--limit", "200",
                              "--json", "number,state"], capture_output=True, text=True, timeout=20,
                             env={**os.environ, "GH_TOKEN": token})
        states = {p["number"]: p["state"] for p in json.loads(out.stdout)}
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError):
        return None
    try:
        json.dump({"at": time.time(), "states": states}, open(PR_CACHE, "w"))
    except OSError:
        pass
    return states


def stale_prs(path=REG, states=None):
    """Rows still saying a PR is waiting when GitHub says it is merged or closed."""
    states = states if states is not None else pr_states()
    if states is None:
        return [], "GitHub could not be reached, so PR states were not checked"
    try:
        data = read_data(path)
    except (ValueError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return [], ""
    problems = []
    for tab in ("PROGRESS", "NEXT"):
        for row in data.get(tab) or []:
            if not isinstance(row, list) or len(row) != 3:
                continue
            for num in re.findall(r"PR #(\d+)", row[2]):
                state = states.get(int(num))
                if state in ("MERGED", "CLOSED"):
                    problems.append(f'"{row[1]}" says PR #{num} is waiting, but GitHub says it is {state.lower()}')
                elif state is None:
                    problems.append(f'"{row[1]}" names PR #{num}, which does not exist on GitHub')
    return problems, ""
