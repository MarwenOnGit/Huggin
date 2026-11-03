# `devicecode-azure-mgmt-signin`

**Status: draft, not yet validated.** Tier: `identity`. Validation: `manual`.

**Written, not deployable on this tenant:** needs Entra ID P1/P2 and the Entra ID diagnostic setting.

Fenrir operations: A-02, A-04 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a successful device code or ROPC sign-in by a user who has not used that flow in the last 14 days. **Fenrir trigger:** `login` (A-02 by default, A-04 with `--auth-flow ropc`).

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | Admins using `az login --use-device-code` on a new headless machine. Device enrolment flows. If Conditional Access already blocks device code for most users, the residual volume is small. |
| False negatives | Users who already use device code regularly. Interactive browser flow (`--auth-flow interactive`). Sign-ins reusing a cached refresh token (no new interactive sign-in). |
| Severity / MITRE | Medium, High for ROPC. T1078.004. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
