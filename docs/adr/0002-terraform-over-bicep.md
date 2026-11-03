# ADR 0002: Terraform rather than Bicep

Date: 2026-11-03. Status: accepted.

## Context

Huggin deploys Azure resources (workspace, Sentinel, lab targets) and Entra ID objects (two app
registrations with federated credentials). It also needs a loop over rule folders.

## Decision

Terraform, with pinned providers: azurerm 5.12.0, azuread 3.10.0, local 2.9.1.

## Reasons

- One tool covers both Azure resources and Entra ID objects. Bicep cannot create app registrations
  or federated credentials without deployment scripts or the Microsoft Graph Bicep extension.
- `fileset` + `yamldecode` + `for_each` turns `detections/**/rule.yaml` into rules with no
  per-rule code.
- `plan` gives a reviewable diff before every change, which matches the "ask before touching
  Azure" rule.
- The internship role lists Terraform.

## Consequences

- Terraform state must be stored and protected (ADR 0003). Bicep has no state.
- azurerm 5.x is newer than most examples online. Argument names were checked against the
  provider schema (`terraform providers schema -json`) and the provider source at v5.12.0,
  not from memory. Example: the incident block is `incident { create_incident_enabled }` and the
  severity mapping is `alert_details_override { severity_column_name }`.
- The Sentinel API accepts parent techniques only, so `T1550.001` in `rule.yaml` is sent as
  `T1550`.
