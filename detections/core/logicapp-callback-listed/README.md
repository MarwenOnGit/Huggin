# `logicapp-callback-listed`

**Status: draft, not yet validated.** Deployed for validation in Phase 4 (2026-11-03). Tier: `core`. Validation: `ci`.

Fenrir operations: X-13 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a caller retrieving a Logic App trigger callback URL (a SAS-signed URL that lets anyone run the workflow) for a workflow they have not touched in 14 days. **Fenrir trigger:** `exploit` by default (X-13).

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- **Phase 4 (2026-11-03): duplicate alerts.** Rows are "new" only if `ingestion_time()` falls in the last run interval (`Frequency = 5m`, equal to the rule frequency). Each row is processed by exactly one run, so one event raises one alert instead of up to 12. Pattern from Microsoft's "Handle ingestion delay in scheduled analytics rules".
- **Phase 4: baseline uses ingestion time too.** History is every row ingested before the current interval (up to 14 days), so a row that already alerted becomes "known" for the next run.
- **Phase 4: alert title and entities.** `alert_name_format` puts the caller in the alert title; `Account` (AadUserId = caller object ID) and `AzureResource` entities are mapped so incidents show who and what.
- **Lab evidence X-13 (2026-11-03):** `_ResourceId` is the trigger, so the rule keys on the workflow extracted from it (already in the draft). The failed attempt on a missing trigger is counted too: an attempt is still a signal.
- Uses `HuginnActivity` for both the baseline and the recent rows, instead of a separate raw `AzureActivity` query.

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
