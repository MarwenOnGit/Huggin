# `graph-directory-recon`

**Status: draft, not yet validated.** Tier: `identity`. Validation: `manual`.

**Written, not deployable on this tenant:** needs Entra ID P1/P2 and the Entra ID diagnostic setting.

Fenrir operations: E-01, E-02, E-03, E-04, E-05, E-06, E-07, X-06 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** one principal reading four or more privileged directory views within an hour (role assignments, PIM eligibility, all service principals, owned objects, group membership, domains, managed devices). **Fenrir trigger:** `enumerate` (E-01 to E-07), `exploit` (X-06).

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- Added a constant `Severity` column (the draft had none, and the rule maps severity from that column).
- Phase 3 lab evidence may still change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | Entra admin center and identity governance tools, Graph Explorer, security scanners and CSPM tools. Baseline the admin portal client IDs and scanner principals for 14 days, then watchlist them. |
| False negatives | Slow enumeration spread over hours. Enumeration through other endpoints (`/directoryRoles`, `$batch` requests: verify in lab how `$batch` appears). No coverage at all if the Graph activity log category is not exported. |
| Severity / MITRE | Low (discovery). T1087.004, T1069.003. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
