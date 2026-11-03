# `storage-keys-listed`

**Status: draft, not yet validated.** Tier: `core`. Validation: `ci`.

Fenrir operations: P-12 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** storage account key retrieval in three suspicious shapes: (A) by a managed identity from an IP it has never used, (B) by one caller across 3 or more accounts in an hour, (C) a new (caller, account) pair outside deployments and trusted automation. **Fenrir trigger:** `post-exploit --dump-blobs` (P-12), also with `--dry-run`. Fires branch A (the caller is the captured identity, acting from the operator's IP), and often B.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

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
