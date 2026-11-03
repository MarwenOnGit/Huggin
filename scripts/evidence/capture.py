#!/usr/bin/env python3
"""Capture AzureActivity rows for Fenrir-shaped operations into lab-evidence/<op>.json.

Read-only: runs one Log Analytics query with the signed-in Azure CLI identity.
Raw output goes to lab-evidence/raw/ (git-ignored); the redacted copy goes to lab-evidence/.

Usage:
  python3 scripts/evidence/capture.py --since 2026-11-03T15:00:00Z [--until ...] [--ops X-13,P-12]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "lab-evidence"
RAW = OUT / "raw"
WORKSPACE_FALLBACK = "b15fe383-5018-4ce4-ada1-6e06f8c83bee"

OPERATIONS = {
    "X-08": "MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMAND/ACTION",
    "X-10": "MICROSOFT.WEB/SITES/CONFIG/LIST/ACTION",
    "X-13": "MICROSOFT.LOGIC/WORKFLOWS/TRIGGERS/LISTCALLBACKURL/ACTION",
    "X-14": "MICROSOFT.CONTAINERINSTANCE/CONTAINERGROUPS/CONTAINERS/EXEC/ACTION",
    "P-12": "MICROSOFT.STORAGE/STORAGEACCOUNTS/LISTKEYS/ACTION",
    "P-13": "MICROSOFT.CONTAINERREGISTRY/REGISTRIES/LISTCREDENTIALS/ACTION",
}

# Values that must never be committed. Activity log rows should not contain any of these,
# but the capture redacts defensively and reports what it redacted.
SECRET_PATTERNS = [
    (re.compile(r"([?&](sig|sv|se|sp|skoid|sktid)=)[^&\"\s]+", re.I), r"\1REDACTED"),
    (re.compile(r"(Bearer\s+)[A-Za-z0-9._-]+", re.I), r"\1REDACTED"),
    (re.compile(r"\b[A-Za-z0-9+/]{86}==(?![A-Za-z0-9+/=])"), "REDACTED_STORAGE_KEY"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*"), "REDACTED_JWT"),
]
# Opaque, Entra-internal token claims. Not credentials, but no rule uses them and there is no
# reason to publish token internals.
OPAQUE_CLAIMS = {"aio", "xms_rd", "rh", "uti", "xms_ftd"}
SECRET_KEYS = {"responsebody", "password", "passwords", "keys", "callbackurl", "accesstoken", "refreshtoken"}


def workspace_id() -> str:
    try:
        out = subprocess.run(
            ["terraform", f"-chdir={ROOT / 'infra' / 'sentinel'}", "output", "-raw", "workspace_customer_id"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        return out or WORKSPACE_FALLBACK
    except (subprocess.CalledProcessError, FileNotFoundError):
        return WORKSPACE_FALLBACK


def query(ws: str, kql: str) -> list[dict]:
    res = subprocess.run(
        ["az", "monitor", "log-analytics", "query", "-w", ws, "--analytics-query", kql, "-o", "json"],
        check=True, capture_output=True, text=True,
    )
    return json.loads(res.stdout)


def redact(obj, hits: list[str], path: str = ""):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            p = f"{path}.{k}" if path else k
            if k.lower() in OPAQUE_CLAIMS:
                out[k] = "OMITTED_OPAQUE_CLAIM"
            elif k.lower() in SECRET_KEYS and v not in (None, "", "{}", "[]"):
                hits.append(p)
                out[k] = "REDACTED"
            else:
                out[k] = redact(v, hits, p)
        return out
    if isinstance(obj, list):
        return [redact(v, hits, f"{path}[{i}]") for i, v in enumerate(obj)]
    if isinstance(obj, str):
        # Nested JSON strings (Properties, Claims, Authorization, Properties_d.requestbody)
        s = obj.strip()
        if s[:1] in "{[":
            try:
                inner = json.loads(s)
                return json.dumps(redact(inner, hits, path), sort_keys=True)
            except json.JSONDecodeError:
                pass
        new = obj
        for pat, repl in SECRET_PATTERNS:
            new, n = pat.subn(repl, new)
            if n:
                hits.append(f"{path} ({pat.pattern[:20]}...)")
        return new
    return obj


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True, help="ISO 8601 UTC start, e.g. 2026-11-03T15:00:00Z")
    ap.add_argument("--until", help="ISO 8601 UTC end (default: now)")
    ap.add_argument("--ops", default=",".join(OPERATIONS), help="comma-separated op IDs")
    ap.add_argument("--caller", help="optional Caller filter (object ID, app ID or UPN)")
    ap.add_argument("--note", default="", help="free text stored in the evidence file")
    args = ap.parse_args()

    ws = workspace_id()
    RAW.mkdir(parents=True, exist_ok=True)
    until = args.until or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    status = 0
    for op in [o.strip() for o in args.ops.split(",") if o.strip()]:
        name = OPERATIONS[op]
        caller = f'| where Caller =~ "{args.caller}"' if args.caller else ""
        kql = (
            f'AzureActivity | where TimeGenerated between (datetime({args.since}) .. datetime({until})) '
            f'| where OperationNameValue =~ "{name}" {caller} '
            "| extend IngestionTime = ingestion_time() | order by TimeGenerated asc"
        )
        rows = query(ws, kql)
        if not rows:
            print(f"{op}: 0 rows in window, nothing written (existing evidence kept)")
            status = 1
            continue
        (RAW / f"{op}.json").write_text(json.dumps(rows, indent=2))
        hits: list[str] = []
        clean = redact(rows, hits)
        doc = {
            "op": op,
            "operation": name,
            "captured_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "window": {"since": args.since, "until": until},
            "workspace": ws,
            "query": kql,
            "note": args.note,
            "row_count": len(rows),
            "redacted_fields": sorted(set(hits)),
            "rows": clean,
        }
        (OUT / f"{op}.json").write_text(json.dumps(doc, indent=2) + "\n")
        print(f"{op}: {len(rows)} rows -> lab-evidence/{op}.json (redacted {len(set(hits))} fields)")
    return status


if __name__ == "__main__":
    sys.exit(main())
