#!/usr/bin/env python3
"""Capture EVERYTHING a purple-team run left in the Huginn workspace, from every table.

Read-only: runs Log Analytics queries with the signed-in Azure CLI identity.

1. Inventory: row count per table in the window, for all rows and for rows that mention one of
   the run's indicators (attacker object ID, operator IP, the managed identity's IDs, ...).
   A table that only shows up in the second count is telemetry the run produced.
2. Rows: for each table with matching rows, up to --max-rows rows. Raw copies go to
   lab-evidence/raw/purple-<label>/ (git-ignored); redacted copies to lab-evidence/purple/<label>/.
3. Canary check: every table that contains the canary prefix. A canary in a log means a secret
   reached that log. The values are always redacted in the saved files.

Indicators are matched with KQL `has` on every column (`where * has "..."`), so they work on
tables whose schema is not known in advance.

Usage:
  python3 scripts/purple/capture.py --since 2026-11-10T14:00:00Z --until 2026-11-10T16:00:00Z \\
      --label 2026-11-10 --indicator <attacker object id> --indicator <operator IP>

The managed identity's IDs and the canary prefix are read from `terraform output` of
infra/purple and added automatically (use --no-terraform to skip).
"""
from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "lab-evidence" / "purple"
RAW = ROOT / "lab-evidence" / "raw"

# Reuse the redaction rules of the Phase 3 evidence capture.
_spec = importlib.util.spec_from_file_location("evidence_capture", ROOT / "scripts" / "evidence" / "capture.py")
assert _spec and _spec.loader
evidence = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(evidence)

CANARY_PREFIX = "HUGINN-CANARY-"
CANARY_RE = re.compile(re.escape(CANARY_PREFIX) + r"[a-z0-9]+")
SAFE_TERM = re.compile(r"^[A-Za-z0-9@._:/-]+$")


def tf_output(name: str) -> str:
    try:
        return subprocess.run(
            ["terraform", f"-chdir={ROOT / 'infra' / 'purple'}", "output", "-raw", name],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def kql_string(s: str) -> str:
    if not SAFE_TERM.match(s):
        raise SystemExit(f"indicator {s!r}: only letters, digits and @ . _ : / - are allowed")
    return f'"{s}"'


IP_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$|^[0-9a-fA-F:]+:[0-9a-fA-F:]*$")


def redact(rows: list[dict], hits: list[str], ips: list[str]) -> list[dict]:
    clean = evidence.redact(rows, hits)
    text = json.dumps(clean)
    text, n = CANARY_RE.subn(CANARY_PREFIX + "REDACTED", text)
    if n:
        hits.append(f"canary value ({n}x)")
    # The operator's own IP address is personal data: keep the fact, drop the value.
    for i, ip in enumerate(ips, 1):
        text, n = re.subn(rf"(?<![0-9A-Za-z.:]){re.escape(ip)}(?![0-9A-Za-z.:])", f"INDICATOR_IP_{i}", text)
        if n:
            hits.append(f"indicator IP {i} ({n}x)")
    return json.loads(text)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--since", required=True, help="ISO 8601 UTC start of the run")
    ap.add_argument("--until", help="ISO 8601 UTC end (default: now). Wait 30+ minutes after the run first.")
    ap.add_argument("--label", required=True, help="folder name for this run, e.g. the date")
    ap.add_argument("--indicator", action="append", default=[],
                    help="value that identifies the run's activity (object ID, IP, UPN, app ID); repeatable")
    ap.add_argument("--max-rows", type=int, default=500, help="rows saved per table (default 500)")
    ap.add_argument("--no-terraform", action="store_true", help="do not read infra/purple outputs")
    args = ap.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9._-]+", args.label):
        raise SystemExit("--label: letters, digits, . _ - only")
    until = args.until or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    indicators = list(args.indicator)
    if not args.no_terraform:
        for name in ("identity_principal_id", "identity_client_id", "attacker_object_id", "vm_principal_id"):
            v = tf_output(name)
            if v and v != "null":
                indicators.append(v)
        mi_res = tf_output("identity_resource_id")
        if mi_res:
            indicators.append(mi_res.lower())
    indicators = sorted(set(indicators))
    if not indicators:
        raise SystemExit("no indicators: pass --indicator, or apply infra/purple so its outputs exist")

    ips = [i for i in indicators if IP_RE.match(i)]
    ws = (tf_output("workspace_customer_id") if not args.no_terraform else "") or evidence.workspace_id()
    window = f"TimeGenerated between (datetime({args.since}) .. datetime({until}))"
    match = " or ".join(f"* has {kql_string(i)}" for i in indicators)

    # 1. Inventory: every table, all rows vs rows that match an indicator.
    # (`* has` is only valid in a where clause, hence two queries.)
    totals = evidence.query(ws, (
        f"union withsource=SourceTable * | where {window} | summarize Rows = count() by SourceTable"
    ))
    matching = evidence.query(ws, (
        f"union withsource=SourceTable * | where {window} | where {match} "
        "| summarize Matching = count() by SourceTable"
    ))
    m = {r["SourceTable"]: int(r["Matching"]) for r in matching}
    inventory = sorted(
        ({"SourceTable": r["SourceTable"], "Rows": int(r["Rows"]), "Matching": m.get(r["SourceTable"], 0)}
         for r in totals),
        key=lambda r: (-r["Matching"], -r["Rows"], r["SourceTable"]),
    )
    # 3. Canary check across every table.
    canary = evidence.query(ws, (
        f'union withsource=SourceTable * | where {window} | where * has "{CANARY_PREFIX}" '
        "| summarize Rows = count() by SourceTable"
    ))

    raw_dir = RAW / f"purple-{args.label}"
    out_dir = OUT / args.label
    raw_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    # 2. Rows per table with matches.
    saved = {}
    for t in inventory:
        table, n = t["SourceTable"], int(t["Matching"])
        if n == 0:
            continue
        if not re.fullmatch(r"[A-Za-z0-9_]+", table):
            print(f"skipping table with unexpected name: {table!r}", file=sys.stderr)
            continue
        rows = evidence.query(ws, (
            f"{table} | where {window} | where {match} "
            f"| extend IngestionTime = ingestion_time() | order by TimeGenerated asc | take {args.max_rows}"
        ))
        (raw_dir / f"{table}.json").write_text(json.dumps(rows, indent=2))
        hits: list[str] = []
        clean = redact(rows, hits, ips)
        (out_dir / f"{table}.json").write_text(json.dumps({
            "table": table,
            "window": {"since": args.since, "until": until},
            "matching_rows": n,
            "saved_rows": len(rows),
            "redacted_fields": sorted(set(hits)),
            "rows": clean,
        }, indent=2) + "\n")
        saved[table] = (n, len(rows), len(set(hits)))
        print(f"{table}: {n} matching rows, saved {len(rows)}, redacted {len(set(hits))} fields")

    canary_tables = {c["SourceTable"]: int(c["Rows"]) for c in canary}
    lines = [
        f"# Purple-team capture: {args.label}",
        "",
        f"- Window (UTC): {args.since} to {until}",
        f"- Workspace: `{ws}`",
        f"- Captured at: {dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
        f"- Indicators: {len(indicators)} (object IDs, IPs and resource IDs of the run; listed in the raw folder only)",
        "",
        "## Tables in the window",
        "",
        "| Table | All rows | Rows matching the run | Saved |",
        "|---|---|---|---|",
    ]
    for t in inventory:
        s = saved.get(t["SourceTable"])
        lines.append(f"| `{t['SourceTable']}` | {t['Rows']} | {t['Matching']} | {s[1] if s else 0} |")
    lines += ["", "## Canary check", ""]
    if canary_tables:
        lines.append("**A canary value reached these tables** (a secret in a log; values redacted in the saved files):")
        lines.append("")
        lines += [f"- `{k}`: {v} rows" for k, v in sorted(canary_tables.items())]
    else:
        lines.append("No table contains the canary prefix: no canary secret reached a log.")
    lines += ["", "Compare each table above with docs/FENRIR-OPERATIONS.md before changing any blind-spot claim."]
    (out_dir / "SUMMARY.md").write_text("\n".join(lines) + "\n")
    (raw_dir / "indicators.json").write_text(json.dumps(indicators, indent=2))
    print(f"summary -> {out_dir.relative_to(ROOT)}/SUMMARY.md")
    if canary_tables:
        print(f"CANARY FOUND in: {', '.join(sorted(canary_tables))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
