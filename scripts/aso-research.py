#!/usr/bin/env python3
"""Quick keyword research for Bond via Astro MCP."""
from __future__ import annotations

import json, sys, time, urllib.request
from pathlib import Path

MCP = "http://127.0.0.1:8089/mcp"

def call(tool, args, rid=1, timeout=15):
    payload = {"jsonrpc":"2.0","id":rid,"method":"tools/call","params":{"name":tool,"arguments":args}}
    req = urllib.request.Request(MCP, data=json.dumps(payload).encode(), headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = json.loads(r.read())
    if "error" in body:
        return {"error": body["error"]}
    text = body["result"]["content"][0]["text"]
    if text.strip().startswith(("[","{")):
        return json.loads(text)
    return text

out = {}
# Search key head terms
terms = ["couples app","love language reminders","relationship app","anniversary tracker",
         "partner app","relationship reminder","paired app","date night app","marriage app",
         "couples widget","couples watch","love nudge","anniversary countdown",
         "marriage reminder","couple check in","long distance relationship app"]
for i, kw in enumerate(terms):
    try:
        r = call("search_app_store", {"keyword": kw, "store": "us", "limit": 5}, rid=10+i, timeout=15)
        out[f"search:{kw}"] = r
        total = r.get("totalResults","?") if isinstance(r, dict) else "?"
        names = [a.get("name","?") for a in (r.get("apps",[]) if isinstance(r, dict) else [])]
        print(f"{kw:35s} → {total} results | {', '.join(names[:3])}")
    except Exception as e:
        print(f"{kw:35s} → ERROR {e}")
    time.sleep(0.5)

Path("scripts/aso-research.json").write_text(json.dumps(out, indent=2, ensure_ascii=False))
print(f"\nDone — wrote scripts/aso-research.json")
