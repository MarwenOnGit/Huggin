# ADR 0007: Exclude identities through a watchlist, never whole client apps

Date: 2026-11-04. Status: accepted.

## Context

Most legitimate look-alikes of Fenrir's actions come from tools: the Azure portal, the Azure CLI,
Terraform refreshes. The tempting exclusion is by client application ID. But Fenrir signs in with
the Azure CLI's own public client ID (`04b07795-...`) by default, so a CLI exclusion would hide the
attacker completely. A stolen portal or CLI session looks the same as the owner's.

## Decision

- Exclusions live in the Sentinel watchlist `HuginnTrustedAutomation`, one row per approved
  **(principal object ID, scope prefix, operation)**, each with `Owner`, `Reason` and `ExpiresOn`.
  Expired rows stop excluding.
- No row may exclude a client app on its own; the static test rejects rows without a principal,
  a scope or an operation.
- Rows come from a reviewed CSV and from Terraform for Huggin's own identities: the deployment
  principal (four refresh operations, Huggin resource groups) and named operators
  (`trusted_operators`: `listKeys` and `listCallbackUrl` only, Huggin resource groups, 90-day
  expiry).
- The lab attacker is never added, so every replay must alert.
- Repeat behaviour is handled by "new pair" baselines, and deployment context lowers severity
  instead of dropping events.

## Consequences

- A compromised watchlisted identity acting inside its approved scope is a known false negative,
  documented in each rule.
- Lab evidence confirmed the need: the operator's own local Terraform refresh hit
  `storage-keys-listed` on day one, and a narrow operator row removed it without changing the
  query (2026-11-03).
