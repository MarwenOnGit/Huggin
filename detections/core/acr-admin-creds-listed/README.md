# `acr-admin-creds-listed`

**Status: draft, not yet validated.** Tier: `core`. Validation: `ci`.

Fenrir operations: P-13 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** retrieval of a container registry's admin username and password. **Fenrir trigger:** `post-exploit --dump-images` (P-13), also with `--dry-run`.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | Portal Access keys blade, `az acr credential show`, Terraform refresh with `admin_enabled = true`: watchlist or new-pair filter. |
| False negatives | Admin credentials already saved elsewhere. Pulls with Entra tokens or scoped tokens (no `listCredentials`). Registries with the admin user disabled: the call fails and shows as a failure, which the rule still sees. |
| Severity / MITRE | Medium, High for a managed identity caller. T1552. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
