# `logicapp-callback-listed`

**Status: draft, not yet validated.** Tier: `core`. Validation: `ci`.

Fenrir operations: X-13 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a caller retrieving a Logic App trigger callback URL (a SAS-signed URL that lets anyone run the workflow) for a workflow they have not touched in 14 days. **Fenrir trigger:** `exploit` by default (X-13).

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | A developer's first visit to a workflow in the designer (Medium, one workflow). Terraform refresh of `callback_url`: watchlist. ARM/Bicep `listCallbackUrl()`: downgraded to Low via deployment context. |
| False negatives | Callback URLs already copied into documentation, pipelines or Key Vault. Standard (single-tenant) Logic Apps, which use `Microsoft.Web/sites` hostruntime paths: verify in lab and add the operation name. A caller who already listed the URL in the last 14 days. |
| Severity / MITRE | Medium, High for 2+ workflows, Low inside a deployment. T1552. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
