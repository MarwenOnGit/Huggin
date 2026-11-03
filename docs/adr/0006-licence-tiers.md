# ADR 0006: Licence tiers

Date: 2026-11-04. Status: accepted.

## Context

Fenrir's footprint spans tables with different licence needs. `AzureActivity` is free and needs
no Entra licence. Sign-in logs and `MicrosoftGraphActivityLogs` need Entra ID P1/P2 and an Entra
diagnostic setting. The lab tenant has no P1/P2 (checked 2026-11-03: `subscribedSkus` is empty).
A scheduled rule that queries a table missing from the workspace fails to deploy.

## Decision

Split rules into tiers by folder (`detections/core`, `detections/identity`,
`detections/beyond-fenrir`) and by metadata (`deployable`, `requires_licence`, `validation`).

- **Core**: `AzureActivity` only. Deployable everywhere, validated by CI replays.
- **Identity**: sign-in and Graph rules, written but `deployable: false` until a licence exists;
  plus the `AzureActivity`-only identity rules (`mi-control-plane-new-ip`) that need a real
  managed identity acting off-host and so are validated manually.
- **Beyond Fenrir**: rules for steps Fenrir reports but never performs.

The Entra diagnostic setting sits behind `enable_entra_logs` (default false), and only a person
with Global or Security Administrator can apply it, never CI.

## Consequences

- The demo set works on a free tenant.
- Static tests stop a deployable rule from referencing a licence-gated table (comments excluded).
- `fenrir-chain` lost its `SigninLogs` device code boost in the core version; the snippet is kept
  in its README for when a licence exists.
