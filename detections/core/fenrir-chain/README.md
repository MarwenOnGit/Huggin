# `fenrir-chain`

**Status: draft, not yet validated.** Deployed for validation in Phase 4 (2026-11-03). Tier: `core`. Validation: `ci`.

Fenrir operations: X-08, X-10, X-13, X-14, P-12, P-13 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** the multi-step pattern behind Fenrir rather than Fenrir itself: one non-managed caller performing two or more kinds of "execute on a host or extract a secret" actions, or touching three or more targets, within 4 hours. The strongest signal: **a managed identity then acting from the same IP address the user just used**, which is what happens when a token taken from a host is replayed from the operator's machine. **Fenrir trigger:** `exploit` (X-08, X-10, X-13, X-14) followed by `post-exploit` with a dump flag (P-12, P-13).

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- **Phase 4 (2026-11-03): duplicate alerts.** Rows are "new" only if `ingestion_time()` falls in the last run interval (`Frequency = 5m`, equal to the rule frequency). Each row is processed by exactly one run, so one event raises one alert instead of up to 12. Pattern from Microsoft's "Handle ingestion delay in scheduled analytics rules".
- **Phase 4: alert title and entities.** `alert_name_format` puts the caller in the alert title; `Account` (AadUserId = caller object ID) and `AzureResource` entities are mapped so incidents show who and what.
- **Correction 2026-11-03: upper bound and per-request counting.** The first version counted rows with `ingestion_time() > ago(5m)` only, and raised 3 alerts for one replay (21:24, 21:29, 21:34 UTC). Now the chain only sees rows ingested by the window end (`now()`), and a request (`CorrelationId`) is new once, when its first row is ingested. Simulated at the real window ends: one alert per window that brings a new request.
- **Known noise:** a long Fenrir run whose actions are ingested over several windows raises one alert per window. Alerting only when the chain gains a new stage was rejected: a second replay within 4 hours would never alert, which breaks the back-to-back baseline-trap test.
- **Fires only when the chain gets a new row** in the current interval (`NewRows > 0` or a new managed-identity row), so a chain is not re-alerted every 5 minutes for 4 hours. Each new stage re-raises it once, which is intended.
- `TargetResource` is the first target of the chain, for the `AzureResource` entity.
- Removed the `SigninLogs` device code boost. Without Entra ID P1/P2 the table does not exist in the workspace, and a scheduled rule referencing a missing table fails to deploy. If P1/P2 is enabled later, add this back as an identity-tier variant:

```kql
let DeviceCode = SigninLogs
    | where TimeGenerated > ago(1d)
    | where AuthenticationProtocol =~ "deviceCode" and ResultType == "0"
    | summarize DeviceCodeSignIns = count() by CallerOid = tolower(UserId);
```

## False positives, false negatives, severity

| | |
|---|---|
| Log source / licence | `AzureActivity` (free), `SigninLogs` (P1/P2) for the device code boost |
| False positives | Platform engineers doing several kinds of admin work in one session (Medium). **Jump-box admins**: an admin on an Azure VM whose own managed identity acts from the same public IP will match the pivot branch. Watchlist such jump hosts' identities. Shared corporate NAT, if workloads also egress through it (Arc). |
| False negatives | Chains split across several user accounts or spread over more than 4 hours. Operators who stop after `enumerate` (nothing logged) or after `exploit` without dump flags (pivot branch cannot fire). An operator using a different IP for each phase. |
| Severity / MITRE | Medium, High on identity pivot or device code + 2 stages. T1651, T1552, T1550.001. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
