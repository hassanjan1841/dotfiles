#!/usr/bin/env python3
"""Read-only Chrome report: process load by type, profiles in use, sites per profile,
enabled extensions (with ids, background and content-script flags) and Energy/Memory Saver state.
Reads Chrome's files only; never opens or touches a window."""
import glob, json, os, re, subprocess, time

BASE = os.path.expanduser("~/Library/Application Support/Google/Chrome")


def procs():
    out = subprocess.run(["ps", "-Ao", "pid=,pcpu=,rss=,etime=,args="], capture_output=True, text=True).stdout
    groups, browser_age = {}, None
    for line in out.splitlines():
        if "/Google Chrome" not in line or "Chrome for Testing" in line:
            continue
        pid, cpu, rss, etime, args = line.split(None, 4)
        if "--type=renderer" in args:
            t = "extension" if "--extension-process" in args else "tab (renderer)"
        elif "--type=gpu-process" in args:
            t = "graphics"
        elif "--type=utility" in args:
            m = re.search(r"--utility-sub-type=([\w.]+)", args)
            t = "utility " + (m.group(1).split(".")[0] if m else "")
        else:
            t = "browser"
            if args.endswith("MacOS/Google Chrome"):
                browser_age = etime
        g = groups.setdefault(t, [0, 0.0, 0])
        g[0] += 1; g[1] += float(cpu); g[2] += int(rss)
    print("== Chrome processes (cpu % of one core)")
    for t, (n, c, r) in sorted(groups.items(), key=lambda x: -x[1][1]):
        print(f"  {t:24} n={n:<3} cpu {c:6.1f}%  ram {r/1048576:4.1f} GB")
    print(f"  Chrome running for: {browser_age or 'not running'}")


def local_state():
    try:
        ls = json.load(open(os.path.join(BASE, "Local State")))
    except Exception as e:
        print("Local State unreadable:", e); return {}
    pt = ls.get("performance_tuning", {})
    # Chromium enums: battery saver 0 off, 1 below threshold, 2 on battery, 3 always; memory saver 0 off, 2 on.
    print("== Saver modes")
    print("  Energy Saver state:", pt.get("battery_saver_mode", {}).get("state", "default"), "(2 = when unplugged, 3 = always)")
    print("  Memory Saver state:", pt.get("high_efficiency_mode", {}).get("state", "default"),
          "aggressiveness", pt.get("high_efficiency_mode", {}).get("aggressiveness", "default"))
    return ls.get("profile", {}).get("info_cache", {})


def ext_name(manifest):
    try:
        j = json.load(open(manifest))
    except Exception:
        return None, {}
    n = j.get("name", "?")
    if n.startswith("__MSG_"):
        loc = os.path.join(os.path.dirname(manifest), "_locales", j.get("default_locale", "en"), "messages.json")
        try:
            n = json.load(open(loc)).get(n[6:-2], {}).get("message", n)
        except Exception:
            pass
    return n, j


def profiles(info):
    now = time.time()
    print("== Profiles (sessions written recently are open now)")
    for d in sorted(glob.glob(os.path.join(BASE, "Default")) + glob.glob(os.path.join(BASE, "Profile *"))):
        prof = os.path.basename(d)
        name = info.get(prof, {}).get("name", "")
        sess = sorted(glob.glob(os.path.join(d, "Sessions", "Session_*")), key=os.path.getmtime)
        age = f"{int((now - os.path.getmtime(sess[-1])) / 60)} min ago" if sess else "never"
        sites = ""
        if sess:
            raw = subprocess.run(["strings", sess[-1]], capture_output=True, text=True).stdout
            hosts = {}
            for u in re.findall(r"https?://[^/\s\"]+", raw):
                hosts[u] = hosts.get(u, 0) + 1
            sites = ", ".join(h.split("//")[1] for h, _ in sorted(hosts.items(), key=lambda x: -x[1])[:6])
        print(f"  {prof:10} {name[:22]:22} session written {age:>12}  sites (history, not only open tabs): {sites}")
        enabled = []
        state = {}
        for f in ("Preferences", "Secure Preferences"):
            try:
                for eid, v in json.load(open(os.path.join(d, f))).get("extensions", {}).get("settings", {}).items():
                    if "disable_reasons" in v:
                        state[eid] = bool(v["disable_reasons"])
            except Exception:
                pass
        seen = set()
        for m in glob.glob(os.path.join(d, "Extensions", "*", "*", "manifest.json")):
            eid = m.split("/Extensions/")[1].split("/")[0]
            if eid in seen:
                continue
            seen.add(eid)
            n, j = ext_name(m)
            if n and not state.get(eid, False) and not n.startswith("__MSG_"):
                flags = ("bg " if j.get("background") else "") + ("content-scripts" if j.get("content_scripts") else "")
                enabled.append(f"{n[:40]} [{eid}] {flags}".rstrip())
        if enabled:
            print(f"    enabled extensions ({len(enabled)}):")
            for e in sorted(enabled):
                print("     ", e)


if __name__ == "__main__":
    procs()
    info = local_state()
    profiles(info)
