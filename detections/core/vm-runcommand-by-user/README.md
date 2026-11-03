# `vm-runcommand-by-user`

**Status: draft, not yet validated.** Tier: `core`. Validation: `ci`.

Fenrir operations: X-08 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a caller running commands inside VMs through the control plane, including the managed Run Command resource and Arc machines. **Fenrir trigger:** `exploit` by default (X-08). It runs Run Command on every VM in each RG where the caller has a strong role, then once more per attached user-assigned identity.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| Log source / licence | `AzureActivity`, no Entra licence |
| False positives | Admins troubleshooting (portal, CLI): single VM, Medium, acceptable to triage. Release pipelines: watchlist by principal + VM scope. Microsoft first-party callers: baseline 30 days, watchlist with expiry. |
| False negatives | Custom Script Extension (`MICROSOFT.COMPUTE/VIRTUALMACHINES/EXTENSIONS/WRITE`), VM Access extension, serial console, AKS `runCommand`. A watchlisted pipeline identity that is itself compromised. What the command did on the host (not in control-plane logs). |
| Severity / MITRE | Medium, High for 3+ VMs or any failures (permission probing). T1651. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
