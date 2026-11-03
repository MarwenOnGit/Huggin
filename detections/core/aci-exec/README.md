# `aci-exec`

**Status: draft, not yet validated.** Tier: `core`. Validation: `ci`.

Fenrir operations: X-14 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** an interactive exec session opened into a container instance. **Fenrir trigger:** `exploit` by default (X-14), on the first container of each group.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | Portal "Connect" and `az container exec` for debugging: low volume, triage. Pipelines that exec: watchlist. |
| False negatives | Anything typed inside the session. AKS `kubectl exec` (different log source). Container Apps console (`Microsoft.App`): verify in lab and add its operation name. |
| Severity / MITRE | Medium, High for 2+ groups or failures. T1609. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
