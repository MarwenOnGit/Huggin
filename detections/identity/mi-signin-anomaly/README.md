# `mi-signin-anomaly`

**Status: draft, not yet validated.** Tier: `identity`. Validation: `manual`.

**Written, not deployable on this tenant:** needs Entra ID P1/P2 and the Entra ID diagnostic setting.

Fenrir operations: X-08, X-11 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a managed identity obtaining a token for a resource it has never requested in 14 days, when the identity has at least 7 days of history. **Fenrir trigger:** `exploit` (host side of X-08 and X-11). Fenrir asks for an Azure Resource Manager token, which many workload identities never request.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | Application releases that add a dependency (new resource). New identities are skipped by `MinHistory`. Watchlist planned release windows if needed. |
| False negatives | Identities that already use ARM routinely (common for automation). **Token caching**: if the host already had a valid ARM token cached, no new sign-in row may appear. Verify in lab. The sign-in shows the token was issued, not who used it. Pair with `mi-control-plane-new-ip`. |
| Severity / MITRE | Medium, High for ARM or Graph. T1078.004 (the host-side token theft itself is T1552.005, which needs host telemetry). |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
