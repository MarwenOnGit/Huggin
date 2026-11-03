"""Static checks on every rule folder. No Azure access.

Run with: python -m pytest tests/test_rules_static.py
"""
from __future__ import annotations

import csv
import os
import re
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
DETECTIONS = ROOT / "detections"
TIERS = {"core", "identity", "beyond-fenrir"}
SEVERITIES = {"Informational", "Low", "Medium", "High"}
# Tactic names accepted by azurerm_sentinel_alert_rule_scheduled.
TACTICS = {
    "Reconnaissance", "ResourceDevelopment", "InitialAccess", "Execution", "Persistence",
    "PrivilegeEscalation", "DefenseEvasion", "CredentialAccess", "Discovery", "LateralMovement",
    "Collection", "CommandAndControl", "Exfiltration", "Impact", "ImpairProcessControl",
    "InhibitResponseFunction", "PreAttack",
}
REQUIRED_KEYS = {
    "id", "name", "tier", "fenrir_ops", "status", "validation", "deployable", "requires_licence",
    "severity", "severity_column", "frequency", "lookback", "trigger_threshold", "mitre",
}
OPTIONAL_KEYS = {"branches"}
WATCHLIST_COLUMNS = ["PrincipalId", "AppId", "ScopePrefix", "Operation", "Owner", "Reason", "ExpiresOn"]
# Client app IDs that must never be excluded on their own (LEGIT-BASELINE.md, principle 1).
CLIENT_APP_IDS = {
    "04b07795-8ddb-461a-bbee-02f9e1bf7b46",  # Azure CLI (also Fenrir's default)
    "c44b4083-3bb0-49c1-b47d-974e53cbdf3c",  # Azure portal
    "1950a258-227b-4e31-a9cf-717495945fc2",  # Azure PowerShell
    "872cd9fa-d31f-45e0-9eab-6e460a02d1f1",  # Visual Studio
    "aebc6443-996d-45c2-90f0-388ff96faa56",  # VS Code
}


def iso_duration_seconds(value: str) -> int:
    m = re.fullmatch(r"P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?", value)
    if not m or value in ("P", "PT"):
        raise ValueError(f"not an ISO 8601 duration: {value!r}")
    d, h, mi = (int(x or 0) for x in m.groups())
    return ((d * 24 + h) * 60 + mi) * 60


def known_fenrir_ops() -> set[str]:
    text = (ROOT / "docs" / "FENRIR-OPERATIONS.md").read_text()
    # Every ID defined in the first column of an inventory table.
    return set(re.findall(r"^\| ([AEXPD]-\d{2}) \|", text, flags=re.M))


def rule_dirs() -> list[Path]:
    return sorted(p.parent for p in DETECTIONS.glob("*/*/rule.yaml"))


RULES = rule_dirs()
IDS = [f"{p.parent.name}/{p.name}" for p in RULES]


def load(rule_dir: Path) -> dict:
    return yaml.safe_load((rule_dir / "rule.yaml").read_text())


def test_rules_found():
    assert RULES, "no detections/*/*/rule.yaml found"


def test_no_stray_rule_folders():
    for tier_dir in DETECTIONS.iterdir():
        if tier_dir.is_dir():
            assert tier_dir.name in TIERS, f"unknown tier folder {tier_dir}"
            for d in tier_dir.iterdir():
                assert (d / "rule.yaml").exists(), f"{d} has no rule.yaml"


def test_rule_ids_unique():
    ids = [load(p)["id"] for p in RULES]
    assert len(ids) == len(set(ids))


@pytest.mark.parametrize("rule_dir", RULES, ids=IDS)
def test_folder_complete(rule_dir: Path):
    for f in ("rule.kql", "rule.yaml", "README.md"):
        assert (rule_dir / f).is_file(), f"missing {f}"
        assert (rule_dir / f).read_text().strip(), f"empty {f}"


@pytest.mark.parametrize("rule_dir", RULES, ids=IDS)
def test_schema(rule_dir: Path):
    r = load(rule_dir)
    keys = set(r)
    assert REQUIRED_KEYS <= keys, f"missing keys: {REQUIRED_KEYS - keys}"
    assert keys <= REQUIRED_KEYS | OPTIONAL_KEYS, f"unknown keys: {keys - REQUIRED_KEYS - OPTIONAL_KEYS}"
    assert r["id"] == rule_dir.name
    assert r["tier"] == rule_dir.parent.name
    assert r["status"] in ("draft", "validated")
    assert r["validation"] in ("ci", "manual")
    assert isinstance(r["deployable"], bool)
    assert r["requires_licence"] in ("none", "entra-p1-p2")
    if r["requires_licence"] != "none":
        assert r["deployable"] is False, "licence-gated rules stay non-deployable on this tenant"
    assert r["severity"] in SEVERITIES
    assert isinstance(r["name"], str) and r["name"].startswith("Huginn - ")
    assert isinstance(r["trigger_threshold"], int) and r["trigger_threshold"] >= 0
    freq = iso_duration_seconds(r["frequency"])
    look = iso_duration_seconds(r["lookback"])
    assert 5 * 60 <= freq <= 14 * 86400
    assert look <= 14 * 86400, "Sentinel scheduled rules look back at most 14 days"
    assert freq <= look, "frequency must not exceed lookback"
    tactics = r["mitre"]["tactics"]
    techniques = r["mitre"]["techniques"]
    assert tactics and set(tactics) <= TACTICS, f"bad tactics {tactics}"
    assert techniques and all(re.fullmatch(r"T\d{4}(\.\d{3})?", t) for t in techniques)
    for branch, mode in (r.get("branches") or {}).items():
        assert mode in ("ci", "manual"), f"branch {branch}: {mode}"


@pytest.mark.parametrize("rule_dir", RULES, ids=IDS)
def test_fenrir_ops_exist(rule_dir: Path):
    r = load(rule_dir)
    ops = r["fenrir_ops"]
    assert isinstance(ops, list)
    if r["tier"] == "beyond-fenrir":
        assert ops == [], "beyond-fenrir rules are not triggered by Fenrir"
    else:
        assert ops, "core and identity rules must name the Fenrir operations they cover"
    unknown = set(ops) - known_fenrir_ops()
    assert not unknown, f"fenrir_ops not in FENRIR-OPERATIONS.md: {unknown}"


@pytest.mark.parametrize("rule_dir", RULES, ids=IDS)
def test_ci_rules_have_replay(rule_dir: Path):
    r = load(rule_dir)
    replay = rule_dir / "replay.sh"
    if r["validation"] == "ci":
        assert replay.is_file(), "validation: ci needs replay.sh"
        assert os.access(replay, os.X_OK), "replay.sh must be executable"
        assert r["deployable"], "a CI-validated rule must be deployable"
    else:
        assert not replay.exists(), "replay.sh only for validation: ci"


@pytest.mark.parametrize("rule_dir", RULES, ids=IDS)
def test_kql_hygiene(rule_dir: Path):
    r = load(rule_dir)
    kql = (rule_dir / "rule.kql").read_text()
    if r["status"] == "draft":
        assert kql.startswith("// Draft, not yet validated."), "drafts must say so on line 1"
    assert re.search(rf"\b{r['severity_column']}\s*=", re.sub(r"//.*", "", kql)), "query must compute the severity column"
    code = re.sub(r"//.*", "", kql)  # ignore comments
    if r["deployable"]:
        for table in ("SigninLogs", "AADNonInteractiveUserSignInLogs", "AADManagedIdentitySignInLogs",
                      "MicrosoftGraphActivityLogs"):
            assert not re.search(rf"\b{table}\b", code), f"deployable rule references licence-gated {table}"
    assert "\u2014" not in kql, "no em dashes"


def test_watchlist_columns_and_no_client_app_rows():
    path = ROOT / "watchlists" / "HuginnTrustedAutomation.csv"
    with path.open(newline="") as fh:
        reader = csv.DictReader(fh)
        assert reader.fieldnames == WATCHLIST_COLUMNS
        for i, row in enumerate(reader, start=2):
            assert row["PrincipalId"].strip(), f"line {i}: every row must name a principal"
            assert row["ScopePrefix"].strip().startswith("/subscriptions/"), f"line {i}: scope required"
            assert row["Operation"].strip(), f"line {i}: operation required"
            assert row["AppId"].strip().lower() not in CLIENT_APP_IDS or row["PrincipalId"].strip(), \
                f"line {i}: never exclude a whole client app"
            assert row["Owner"].strip() and row["Reason"].strip() and row["ExpiresOn"].strip(), \
                f"line {i}: Owner, Reason and ExpiresOn are required"
