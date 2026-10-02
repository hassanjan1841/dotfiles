#!/usr/bin/env python3
"""PostToolUse(Artifact) hook: after a successful register publish, remember its hash and keep a copy."""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import register_lib as lib  # noqa: E402

try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
inp = data.get("tool_input", {}) or {}
target = os.path.realpath(os.path.expanduser(inp.get("file_path", "") or ""))
if inp.get("action", "publish") != "publish" or inp.get("asset") or target != os.path.realpath(lib.REG):
    sys.exit(0)
resp = data.get("tool_response")
ok = (isinstance(resp, dict) and resp.get("version") and resp.get("url")) or (isinstance(resp, str) and resp.startswith("Published"))
if not ok:
    sys.exit(0)
with open(lib.PUBLISHED, "w") as f:
    f.write(lib.sha(lib.REG) + "\n")
shutil.copyfile(lib.REG, lib.LAST_COPY)
lib.log("published: stamp and copy saved")
