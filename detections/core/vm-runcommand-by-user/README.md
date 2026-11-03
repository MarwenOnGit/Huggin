# `vm-runcommand-by-user`

**Status: draft, not yet validated.** Prepared for deployment in Phase 4 (2026-11-03). Tier: `core`. Validation: `ci`.

Fenrir operations: X-08 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a caller running commands inside VMs through the control plane, including the managed Run Command resource and Arc machines. **Fenrir trigger:** `exploit` by default (X-08). It runs Run Command on every VM in each RG where the caller has a strong role, then once more per attached user-assigned identity.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- **Lab evidence X-08 (2026-11-03, `lab-evidence/X-08.json`):** one `az vm run-command invoke` is **three rows**, `Start`, `Accept` (sub-status `Accepted`) and `Success`, with one `CorrelationId`; `_ResourceId` is the VM. The command text is **not** logged (`Properties_d.requestbody` empty). The rows were ingested 7 to 10 minutes after the action, and not together (Success at 21:58:02, Start and Accept at 22:00:26).
- **Deduplication per request.** A request (`CorrelationId`) is new once, when its first row is ingested in `(now() - 5m, now()]`; the rule fires only if the run brought a new request. In a scheduled rule `now()` is the window end and the query runs about 5 minutes later, so the upper bound is needed. Simulated at the real window ends on the X-08 rows: exactly one alert for two different window alignments (per-row counting gave two).
- **Severity.** The draft gave Low to every service principal. Now: High for 3+ VMs or any failure, Low only inside a deployment, Medium otherwise. An unknown service principal running commands on a VM is not low risk (the lab attacker is a service principal).
- **Alert title and entities:** "Huginn: VM Run Command by {{Caller}}"; Account (caller object ID) and AzureResource (first VM).
- **Replay:** creates a fresh `Standard_B2ats_v2` VM per run and deletes it with its disk and NIC (about 2 to 3 minutes; see docs/TESTING.md).

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
