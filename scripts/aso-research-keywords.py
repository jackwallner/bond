#!/usr/bin/env python3
"""Research keyword landscape for Bond via Astro MCP."""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

MCP = "http://127.0.0.1:8089/mcp"

def call(tool: str, args: dict, req_id: int = 1, timeout: int = 30):
    payload = {"jsonrpc":"2.0","id":req_id,"method":"tools/call","params":{"name":tool,"arguments":args}}
    req = urllib.request.Request(MCP, data=json.dumps(payload).encode(), headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = json.loads(r.read())
    if "error" in body:
        return {"error": body["error"]}
    text = body["result"]["content"][0]["text"]
    if text.strip().startswith(("[","{")):
        return json.loads(text)
    return text

OUT = Path(__file__).parent / "aso-research-data.json"
research = {}

# 1. Search competitors for key head terms
HEAD_TERMS = [
    "couples app", "couple app", "relationship app",
    "love language", "love reminders", "anniversary tracker",
    "relationship reminder", "date night app", "partner app",
    "paired app", "marriage app", "couples widget",
]

print("=== Searching App Store for head terms ===")
for i, kw in enumerate(HEAD_TERMS):
    try:
        result = call("search_app_store", {"keyword": kw, "store": "us", "limit": 10}, req_id=10+i)
        research[f"search:{kw}"] = result
        if isinstance(result, dict):
            apps = result.get("apps", [])
            print(f"{kw}: {result.get('totalResults','?')} results")
            for a in apps[:5]:
                print(f"  #{a.get('ranking','?')} {a.get('name','?')[:40]} | {str(a.get('subtitle',''))[:40]}")
        else:
            print(f"{kw}: {str(result)[:100]}")
    except Exception as e:
        print(f"{kw}: ERROR {e}")
    time.sleep(0.8)

# 2. Get keyword suggestions for Bond
print("\n=== Getting keyword suggestions ===")
try:
    sugg = call("get_keyword_suggestions", {"appId": "101", "store": "us"}, req_id=50)
    research["suggestions"] = sugg
    print(f"Got suggestions: {len(sugg) if isinstance(sugg, list) else str(sugg)[:200]}")
except Exception as e:
    print(f"Suggestions error: {e}")
    time.sleep(1)

# Also try via search_rankings for our existing keywords
print("\n=== Getting rankings for current keywords ===")
current_kws = ["couples app", "love language", "love language app", "relationship reminder",
               "anniversary tracker", "relationship app", "partner app", "couples widget",
               "long distance relationship", "date night", "marriage reminder", "love nudge"]
try:
    ranks = call("search_rankings", {"keywords": current_kws, "store": "us"}, req_id=60)
    research["rankings"] = ranks
    print(f"Got rankings")
except Exception as e:
    print(f"Rankings error: {e}")

OUT.write_text(json.dumps(research, indent=2, ensure_ascii=False))
print(f"\nWrote {OUT}")
