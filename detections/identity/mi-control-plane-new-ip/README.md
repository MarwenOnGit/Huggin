# `mi-control-plane-new-ip`

**Status: draft, not yet validated.** Tier: `identity`. Validation: `manual`.

Fenrir operations: P-12, P-13 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a managed identity performing a logged control-plane action from an IP address it has never used in 14 days. A managed identity token should only be used from its host. **Fenrir trigger:** `post-exploit` with `--dump-blobs` or `--dump-images` (P-12, P-13), which runs as the identity from the operator's IP.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- Added a constant `Severity` column (the draft had none, and the rule maps severity from that column).
- Phase 3 lab evidence may still change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | Workloads whose outbound IP changes (NAT gateway changes, scale-out to new instances with public IPs). Consider comparing against a watchlist of Azure service-tag ranges: an identity acting from **outside** Azure ranges is the strongest form. Arc-enabled servers use the on-premises egress IP. |
| False negatives | **Reads are not logged**, so an identity that only enumerates (Fenrir X-19 to X-21, P-01 to P-11) is invisible. An attacker operating from another Azure VM may land in Azure ranges. New identities (no history) are skipped. |
| Severity / MITRE | High. T1550.001 Use Alternate Authentication Material: Application Access Token. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
