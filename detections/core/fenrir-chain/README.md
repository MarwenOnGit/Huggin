# `fenrir-chain`

**Status: draft, not yet validated.** Tier: `core`. Validation: `ci`.

Fenrir operations: X-08, X-10, X-13, X-14, P-12, P-13 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** the multi-step pattern behind Fenrir rather than Fenrir itself: one non-managed caller performing two or more kinds of "execute on a host or extract a secret" actions, or touching three or more targets, within 4 hours. The strongest signal: **a managed identity then acting from the same IP address the user just used**, which is what happens when a token taken from a host is replayed from the operator's machine. **Fenrir trigger:** `exploit` (X-08, X-10, X-13, X-14) followed by `post-exploit` with a dump flag (P-12, P-13).

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

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
