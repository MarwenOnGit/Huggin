# `storage-keys-listed`

**Status: draft, not yet validated.** Deployed for validation in Phase 4 (2026-11-03). Tier: `core`. Validation: `ci`.

Fenrir operations: P-12 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** storage account key retrieval in three suspicious shapes: (A) by a managed identity from an IP it has never used, (B) by one caller across 3 or more accounts in an hour, (C) a new (caller, account) pair outside deployments and trusted automation. **Fenrir trigger:** `post-exploit --dump-blobs` (P-12), also with `--dry-run`. Fires branch A (the caller is the captured identity, acting from the operator's IP), and often B.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- **Phase 4 (2026-11-03): duplicate alerts.** Rows are "new" only if `ingestion_time()` falls in the last run interval (`Frequency = 5m`, equal to the rule frequency). Each row is processed by exactly one run, so one event raises one alert instead of up to 12. Pattern from Microsoft's "Handle ingestion delay in scheduled analytics rules".
- **Phase 4: baseline is 47 hours, not 14 days (2026-11-03).** The Sentinel API rejects a query period of 2 days or more with a frequency under 1 hour. Huginn keeps the 5-minute frequency (alerts in about 10 to 15 minutes) and shortens the baseline to `PT47H`. Trade-off: "new pair" now means new in about 2 days, so a person who touches the same resource every few days alerts more often than with a 14-day baseline. CI is unaffected (fresh resources per run). Roadmap: keep a long baseline outside the rule (ADR 0005, option C).
- **Phase 4: baseline uses ingestion time too.** History is every row ingested before the current interval (up to 47 hours), so a row that already alerted becomes "known" for the next run.
- **Phase 4: alert title and entities.** `alert_name_format` puts the caller in the alert title; `Account` (AadUserId = caller object ID) and `AzureResource` entities are mapped so incidents show who and what.
- **Branch B** now requires at least one new row in the current interval, and joins back on all rows of the 1-hour window.
- **Branch validation:** C is exercised by the CI replay (fresh account per run). A (managed identity from a new IP) and B (3+ accounts) are not; A is for the manual purple-team run.
- **Lab evidence (2026-11-03):** an operator running Terraform locally produced `listKeys` on the state account and hit branch C. Handled with a narrow watchlist entry (`trusted_operators`), not by changing the query.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | Terraform refresh (branches B, C): watchlist the pipeline principal per scope. Portal users opening storage blades (C): one account at a time, Medium. First-party services (C): 30-day baseline then watchlist. Branch A: a managed identity whose workload changes outbound IP (new NAT gateway, scale-out). Mitigate by comparing against an Azure service-tag IP watchlist instead of exact IPs if this is noisy. |
| False negatives | Keys already stored elsewhere (app settings, Key Vault, pipeline secrets). Data access with OAuth roles or SAS (no `listKeys`). `listAccountSas` / `listServiceSas` (add these operation names after a lab check). Fenrir `post-exploit` without `--dump-blobs`. |
| Severity / MITRE | Medium, High on branch A. T1552, then T1530 Data from Cloud Storage for the follow-on download. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
