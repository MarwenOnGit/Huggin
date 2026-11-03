# `logicapp-callback-listed`

**Status: validated on 2026-11-03** by two back-to-back benign replays (replay 41728291675 and 41734608159). Deployed for validation in Phase 4 (2026-11-03). Tier: `core`. Validation: `ci`.

Fenrir operations: X-13 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a caller retrieving a Logic App trigger callback URL (a SAS-signed URL that lets anyone run the workflow) for a workflow they have not touched in 14 days. *(Deployed version: 47 hours; see Changes from the draft.)* **Fenrir trigger:** `exploit` by default (X-13).

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- **Correction 2026-11-03: upper bound on "new".** The first version used only `ingestion_time() > ago(5m)`. In a scheduled rule `now()` is the window end but the query runs about 5 minutes later, so rows ingested in that gap were new in two runs: one replay event raised 2 alerts (21:27 and 21:32 UTC). Now `IngestedAt > ago(5m) and IngestedAt <= now()`. Simulated at the real window ends: 1 alert.
- **Phase 4 (2026-11-03): duplicate alerts.** Rows are "new" only if `ingestion_time()` falls in the last run interval (`Frequency = 5m`, equal to the rule frequency). Each row is processed by exactly one run, so one event raises one alert instead of up to 12. Pattern from Microsoft's "Handle ingestion delay in scheduled analytics rules".
- **Phase 4: baseline is 47 hours, not 14 days (2026-11-03).** The Sentinel API rejects a query period of 2 days or more with a frequency under 1 hour. Huginn keeps the 5-minute frequency (alerts in about 10 to 15 minutes) and shortens the baseline to `PT47H`. Trade-off: "new pair" now means new in about 2 days, so a person who touches the same resource every few days alerts more often than with a 14-day baseline. CI is unaffected (fresh resources per run). Roadmap: keep a long baseline outside the rule (ADR 0005, option C).
- **Phase 4: baseline uses ingestion time too.** History is every row ingested before the current interval (up to 47 hours), so a row that already alerted becomes "known" for the next run.
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
| 2026-11-03 | replay 41720948678 | fired, but 2 alerts per event (pre-fix duplicate defect) | 10 min 24 s | incidents 6 and later |
| 2026-11-03 | replay 41728291675 | fired, 1 alert (post-fix) | 16 min 46 s | incident 18 |
| 2026-11-03 | replay 41734608159 (back-to-back run 2) | fired, 1 alert | 12 min 45 s | incident 21 |
