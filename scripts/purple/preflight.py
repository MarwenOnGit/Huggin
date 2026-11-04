#!/usr/bin/env python3
"""Check that the purple environment logs to the workspace BEFORE spending a Fenrir run on it.

Run it after `make apply STACK=purple` (wait about 15 minutes for the agent and the diagnostic
settings to start). Uses the signed-in Azure CLI identity (the operator).

1. Config: every resource that should have a diagnostic setting has one, sending to law-huginn.
2. Poke (default on, --no-poke to skip): generate a little benign, operator-side activity on the
   data planes that only log when used: read the Key Vault secret and list the canary blob
   (responses discarded). This is the operator's own activity, not the attacker's.
3. Data: rows per (table, resource) from the purple resource group in the last --minutes.

Exit code 0 only if the config is complete and the required sources have data:
AzureActivity (the apply itself), Syslog from the VM, the Key Vault audit log and
StorageBlobLogs (after the poke). Logic App, Automation, web app and registry log only when
they are used, so "no data yet" is expected for them until the Fenrir run.

Usage: python3 scripts/purple/preflight.py [--minutes 60] [--no-poke]
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("evidence_capture", ROOT / "scripts" / "evidence" / "capture.py")
assert _spec and _spec.loader
evidence = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(evidence)

RG = "huginn-purple-rg"
# Resource types that get a diagnostic setting in infra/purple/diagnostics.tf, and the
# storage sub-services that get one each.
DIAG_TYPES = {
    "microsoft.logic/workflows",
    "microsoft.automation/automationaccounts",
    "microsoft.keyvault/vaults",
    "microsoft.web/sites",
    "microsoft.containerregistry/registries",
}
STORAGE_SERVICES = ("blobServices", "fileServices", "queueServices", "tableServices")


def az(*args: str) -> str:
    return subprocess.run(["az", *args], check=True, capture_output=True, text=True).stdout


def az_json(*args: str):
    return json.loads(az(*args, "-o", "json") or "null")


def tf_output(name: str) -> str:
    try:
        return subprocess.run(
            ["terraform", f"-chdir={ROOT / 'infra' / 'purple'}", "output", "-raw", name],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--minutes", type=int, default=60, help="look-back for data (default 60)")
    ap.add_argument("--no-poke", action="store_true", help="do not generate operator-side data-plane activity")
    args = ap.parse_args()

    resources = az_json("resource", "list", "-g", RG, "--query", "[].{id:id, type:type, name:name}")
    if not resources:
        print(f"no resources in {RG}: apply infra/purple first", file=sys.stderr)
        return 2
    by_type: dict[str, list[dict]] = {}
    for r in resources:
        by_type.setdefault(r["type"].lower(), []).append(r)

    ok = True
    print("== 1. Diagnostic settings")
    targets = [r["id"] for t in DIAG_TYPES for r in by_type.get(t, [])]
    for sa in by_type.get("microsoft.storage/storageaccounts", []):
        targets += [f"{sa['id']}/{s}/default" for s in STORAGE_SERVICES]
    for rid in sorted(targets):
        settings = az_json("monitor", "diagnostic-settings", "list", "--resource", rid) or []
        if isinstance(settings, dict):  # older CLI shape
            settings = settings.get("value", [])
        good = [s for s in settings
                if "law-huginn" in (s.get("workspaceId") or "").lower()
                and any(l.get("enabled") for l in s.get("logs") or [])]
        short = rid.split(f"/resourceGroups/{RG}/", 1)[-1] if f"/resourceGroups/{RG}/" in rid else rid
        print(f"  {'ok     ' if good else 'MISSING'} {short}")
        ok &= bool(good)

    if not args.no_poke:
        print("== 2. Operator-side poke (responses discarded)")
        for kv in by_type.get("microsoft.keyvault/vaults", []):
            az("keyvault", "secret", "show", "--vault-name", kv["name"], "-n", "huginn-canary", "--query", "id")
            print(f"  read secret huginn-canary in {kv['name']}")
        for sa in by_type.get("microsoft.storage/storageaccounts", []):
            az("storage", "blob", "list", "--account-name", sa["name"], "-c", "huginn-canary",
               "--auth-mode", "key", "--query", "[].name")
            print(f"  listed container huginn-canary in {sa['name']}")
        print("  data-plane rows take 5 to 15 minutes to arrive: re-run with --no-poke if section 3 is short")

    print(f"== 3. Rows from {RG} in the last {args.minutes} minutes")
    ws = tf_output("workspace_customer_id") or evidence.workspace_id()
    rows = evidence.query(ws, (
        f"union withsource=SourceTable * | where TimeGenerated > ago({args.minutes}m) "
        f'| where tolower(_ResourceId) has "/resourcegroups/{RG.lower()}/" '
        "| extend Resource = tostring(split(_ResourceId, '/')[-1]) "
        "| summarize Rows = count(), Last = max(TimeGenerated) by SourceTable, Resource "
        "| order by SourceTable asc, Resource asc"
    ))
    tables = {r["SourceTable"] for r in rows}
    for r in rows:
        print(f"  {r['SourceTable']:<28} {r['Resource']:<32} {r['Rows']:>6}  last {r['Last']}")
    if not rows:
        print("  (none)")

    kv_tables = {"AzureDiagnostics", "AZKVAuditLogs"}
    required = {
        "AzureActivity (the apply)": "AzureActivity" in tables,
        "Syslog from the VM": "Syslog" in tables or not by_type.get("microsoft.compute/virtualmachines"),
        "Key Vault audit log": bool(tables & kv_tables),
        "StorageBlobLogs": "StorageBlobLogs" in tables,
    }
    print("== Verdict")
    for name, seen in required.items():
        print(f"  {'ok     ' if seen else 'NO DATA'} {name}")
        ok &= seen
    print("  Logic App, Automation, web app and registry log only when used: no data is expected before the run.")
    print("READY for the Fenrir run." if ok else "NOT READY: fix the items above (or wait and re-run with --no-poke).")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
