#!/usr/bin/env python3
"""Manual checks as gly tasks, through the app's own MCP bridge (gly-mcp).

  scripts/manual-checks.py push docs/manual-checks-tag-colors.md   # one task per open check (+ a setup task)
  scripts/manual-checks.py pull docs/manual-checks-tag-colors.md   # tick checks whose tasks are done

Tasks are tagged `gly/checks/<name>` (from the file name), titled "<ID> · <short text>", with the full check
and its section in the notes. `push` skips checks that already have a task; `pull` ticks `- [ ] <ID>` lines whose
task is done and reports dropped ones (a dropped task = the check failed or doesn't apply; see its notes).
"""
import json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLY_MCP = os.path.join(ROOT, "build/Build/Products/Debug/gly.app/Contents/MacOS/gly-mcp")
CHECK = re.compile(r"^- \[( |x)\] ([A-Z]\d+) (.+)$")


def call(tool, arguments):
    """One tools/call through gly-mcp (a fresh stdio session per call keeps it simple)."""
    lines = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "claude-code", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": tool, "arguments": arguments}},
    ]
    out = subprocess.run([GLY_MCP], input="\n".join(json.dumps(l) for l in lines) + "\n",
                         capture_output=True, text=True, timeout=30).stdout
    for line in out.splitlines():
        msg = json.loads(line)
        if msg.get("id") == 2:
            result = msg["result"]
            text = result["content"][0]["text"] if result.get("content") else ""
            if result.get("isError"):
                sys.exit(f"{tool} failed: {text}")
            return result.get("structuredContent") or json.loads(text)
    sys.exit(f"{tool}: no answer from gly-mcp")


def parse(path):
    """(setup text, [(id, section, text, done)])."""
    setup, section, checks = "", "", []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("Neutral test data") or line.startswith("Setup:"):
            setup += line + "\n"
        elif line.startswith("## "):
            section = line[3:]
        elif m := CHECK.match(line):
            checks.append((m.group(2), section, m.group(3), m.group(1) == "x"))
    return setup.strip(), checks


def tag_for(path):
    name = os.path.basename(path).removeprefix("manual-checks-").removesuffix(".md")
    return f"gly/checks/{name}"


def short(text):
    head = re.split(r" → | -> ", text)[0].replace("`", "")
    return head if len(head) <= 70 else head[:67].rsplit(" ", 1)[0] + "…"


def existing(tag):
    """Check tasks by ID; list_tasks includes tags below `tag` (e.g. demo data), which aren't checks."""
    tasks = call("list_tasks", {"tag": tag, "status": "all", "limit": 500})["tasks"]
    return {t["title"].split(" · ")[0]: t for t in tasks if tag in t.get("tags", [])}


def push(path):
    tag, (setup, checks) = tag_for(path), parse(path)
    have = existing(tag)
    created = 0
    if setup and "00" not in have:
        call("create_task", {"title": "00 · Setup test data", "notes": setup, "tags": [tag]}); created += 1
    for cid, section, text, done in checks:
        if done or cid in have:
            continue
        notes = f"**{section}**\n\n{text}\n\nDone = the check passed. If it fails, add what you saw here and drop the task."
        call("create_task", {"title": f"{cid} · {short(text)}", "notes": notes, "tags": [tag]})
        created += 1
    print(f"{created} task(s) created under {tag}")


def pull(path):
    tag = tag_for(path)
    have = existing(tag)
    lines = open(path, encoding="utf-8").read().split("\n")
    ticked, failed = [], []
    for i, line in enumerate(lines):
        m = CHECK.match(line)
        if not m or m.group(1) == "x" or m.group(2) not in have:
            continue
        status = have[m.group(2)]["status"]
        if status == "done":
            lines[i] = line.replace("- [ ]", "- [x]", 1); ticked.append(m.group(2))
        elif status == "dropped":
            failed.append(m.group(2))
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    open_ids = [cid for cid, t in have.items() if cid != "00" and t["status"] in ("open", "snoozed")]
    print(f"ticked: {', '.join(ticked) or '-'} | failed (dropped): {', '.join(failed) or '-'} | still open: {', '.join(sorted(open_ids)) or '-'}")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("push", "pull"):
        sys.exit(__doc__)
    {"push": push, "pull": pull}[sys.argv[1]](sys.argv[2])
