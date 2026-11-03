#!/usr/bin/env python3
"""Wait for the Sentinel alerts that a replay should produce.

Polls the SecurityAlert table (read-only, Azure CLI identity) until every expected rule has
raised an alert after --since whose entities contain --caller-oid, or until the timeout.
Reports time-to-alert per rule. Exit code 0 if every rule fired, 1 otherwise.

Usage:
  python3 tests/validate_alert.py --since 2026-11-04T02:30:00Z \\
      --rules logicapp-callback-listed,storage-keys-listed,fenrir-chain \\
      --caller-oid 380b1f3c-3bf0-44de-b940-e035eb1a0084 [--timeout-minutes 30]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULE_URL = "https://github.com/MarwenOnGit/Huggin/detections/{}"  # same input as infra/sentinel/rules.tf


def rule_guid(rule_id: str) -> str:
    # Terraform uuidv5("url", name) == RFC 4122 UUIDv5 in the URL namespace.
    return str(uuid.uuid5(uuid.NAMESPACE_URL, RULE_URL.format(rule_id)))


def parse_time(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def workspace_id(shared: dict) -> str:
    if os.environ.get("HUGINN_WORKSPACE_ID"):
        return os.environ["HUGINN_WORKSPACE_ID"]
    return subprocess.run(
        ["az", "monitor", "log-analytics", "workspace", "show",
         "-g", shared["sentinel_resource_group"], "-n", "law-huginn", "--query", "customerId", "-o", "tsv"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()


def query(ws: str, kql: str) -> list[dict] | None:
    res = subprocess.run(
        ["az", "monitor", "log-analytics", "query", "-w", ws, "--analytics-query", kql, "-o", "json"],
        capture_output=True, text=True,
    )
    if res.returncode != 0:
        # Before the first alert ever, the SecurityAlert table does not exist yet.
        if "SecurityAlert" in res.stderr and ("resolve" in res.stderr or "SEM0100" in res.stderr):
            return []
        print(res.stderr.strip()[-500:], file=sys.stderr)
        return None
    return json.loads(res.stdout)


def alert_query(since: str, guid: str, oid: str) -> str:
    # ExtendedProperties holds the analytic rule ID(s); Entities holds the mapped caller.
    return f"""
SecurityAlert
| where TimeGenerated >= datetime({since})
| where tostring(ExtendedProperties) has "{guid}"
| where tolower(Entities) has "{oid}"
| summarize FirstAlert = min(TimeGenerated), Alerts = count(),
            Severities = make_set(AlertSeverity), Names = make_set(AlertName, 5)
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True, help="replay start, ISO 8601 UTC")
    ap.add_argument("--rules", required=True, help="comma-separated rule IDs")
    ap.add_argument("--caller-oid", required=True, help="object ID of the replay identity")
    ap.add_argument("--timeout-minutes", type=float, default=30)
    ap.add_argument("--interval-seconds", type=int, default=60)
    ap.add_argument("--output", default=str(ROOT / "results" / "validate.json"))
    args = ap.parse_args()

    shared = json.loads((ROOT / "infra" / "shared" / "bootstrap.json").read_text())
    ws = workspace_id(shared)
    since = parse_time(args.since)
    rules = [r.strip() for r in args.rules.split(",") if r.strip()]
    guids = {r: rule_guid(r) for r in rules}
    oid = args.caller_oid.lower()
    found: dict[str, dict] = {}
    deadline = time.monotonic() + args.timeout_minutes * 60

    print(f"waiting for {len(rules)} alerts after {args.since} for caller {oid} (timeout {args.timeout_minutes} min)")
    while True:
        missing = [r for r in rules if r not in found]
        if not missing:
            break
        per_rule = []
        for r in missing:
            rows = query(ws, alert_query(args.since, guids[r], oid))
            if rows and rows[0].get("Alerts") not in (None, 0, "0"):
                per_rule.append((r, rows[0]))
        for r, row in per_rule:
            first = parse_time(row["FirstAlert"])
            found[r] = {
                "rule": r,
                "rule_guid": guids[r],
                "first_alert": row["FirstAlert"],
                "time_to_alert_seconds": int((first - since).total_seconds()),
                "alerts": int(row["Alerts"]),
                "severities": row["Severities"],
                "names": row["Names"],
            }
            print(f"  fired: {r} after {found[r]['time_to_alert_seconds']} s ({found[r]['alerts']} alert(s))")
        if len(found) == len(rules) or time.monotonic() > deadline:
            break
        time.sleep(args.interval_seconds)

    result = {
        "since": args.since,
        "caller_oid": oid,
        "checked_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "timeout_minutes": args.timeout_minutes,
        "rules": [found.get(r, {"rule": r, "rule_guid": guids[r], "fired": False}) for r in rules],
        "passed": len(found) == len(rules),
    }
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")

    lines = ["### Alert validation", "", "| Rule | Fired | Time to alert | Alerts | Severity |", "|---|---|---|---|---|"]
    for r in rules:
        f = found.get(r)
        if f:
            mins, secs = divmod(f["time_to_alert_seconds"], 60)
            lines.append(f"| `{r}` | yes | {mins} min {secs} s | {f['alerts']} | {', '.join(json.loads(f['severities']) if isinstance(f['severities'], str) else f['severities'])} |")
        else:
            lines.append(f"| `{r}` | **no** (timeout) | | | |")
    summary = "\n".join(lines) + "\n"
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as fh:
            fh.write(summary)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
