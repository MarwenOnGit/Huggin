# ADR 0008: A disposable, fully logged purple-team environment

Date: 2026-11-04. Status: accepted (stack written; not yet applied).

## Context

Huggin's coverage claims, and especially its blind-spot claims, rest partly on documentation:
"ARM reads are not logged", "the Run Command text is not logged", "X-14 is seen only in
`AzureActivity`". The project's rule is that only the lab decides what is true (lab evidence
already overturned two assumptions: duplicate alerts and three rows per Run Command).

The benign replays cannot settle these questions. They perform one action each, as a service
principal, and never request a managed-identity token (ADR 0005). A real Fenrir run does all of
it: reads, token theft on hosts, actions as the managed identity from the operator's machine,
data-plane access with stolen keys.

## Decision

Add `infra/purple`: a separate Terraform stack that creates, for one purple-team run, every
resource type Fenrir acts on, with every log source Azure offers for it switched on, and is
destroyed right after.

- **Own resource group** (`huginn-purple-rg`), own user-assigned identity, own state key. Not
  `infra/lab` (CI acts on it every night) and not `fenrir-lab-prod-rg` (out of bounds for
  Huggin's code).
- **Applied and destroyed by a person.** CI validates and lints it but never applies it, and the
  replay drift check does not include it.
- **Logging:** the `allLogs` category group on every resource that has resource logs (Logic App,
  Automation, Key Vault, web app, registry, and the storage blob, file, queue and table
  services); Syslog from the VM through the Azure Monitor Agent; the subscription Activity log
  and, with a P1/P2 trial, Entra sign-in and Graph activity logs from `infra/sentinel`;
  optionally Defender for Resource Manager.
- **Canaries:** a random value with the fixed prefix `HUGINN-CANARY-` sits where real secrets
  would be (runbook source, Automation variable and credential, Key Vault secret, blob, app
  setting, container environment). `scripts/purple/capture.py` reports every table that
  contains the prefix, which shows whether a stolen secret reaches any log, and redacts it.
- **Capture by indicator, not by table:** the capture script queries `union *` for rows that
  mention the run's identities and IP, so it finds telemetry in tables nobody expected.
- **Attacker:** a dedicated low-privilege user with Contributor on the purple resource group
  only. Fenrir acts on every resource group it can see, so it must never run as an account with
  rights elsewhere.

## Consequences

- Blind-spot claims become measured results, one run at a time, with evidence in
  `lab-evidence/purple/<run>/`.
- The same environment works for other tools (inventory them first, as in
  FENRIR-OPERATIONS.md).
- Cost per run is small (docs/COST.md) but not zero, and the workspace's 0.5 GB daily cap may
  stop ingestion during a run; raise it for the run window.
- Accepted checkov findings: the environment is deliberately exposed (shared keys, admin user,
  public endpoints, unencrypted Automation variable, extensions, no purge protection). Each is
  skipped inline with a reason that cites this ADR:

| Group | Checks |
|---|---|
| The attack surface itself | CKV_AZURE_50 (VM extensions), CKV2_AZURE_40 (storage shared keys), CKV_AZURE_137 (ACR admin user), CKV_AZURE_73 (unencrypted Automation variable) |
| Reached from the operator's machine | CKV_AZURE_59 (storage), CKV_AZURE_109 and 189 (Key Vault), CKV2_AZURE_24 (Automation), CKV_AZURE_222 (web app), CKV2_AZURE_33 and CKV2_AZURE_32 (private endpoints) |
| Disposable | CKV_AZURE_42 and 110 (Key Vault purge protection), CKV_AZURE_151 (encryption at host), CKV_AZURE_206, CKV2_AZURE_1 (storage redundancy and CMK) |
| Logged elsewhere | CKV_AZURE_33, CKV2_AZURE_21 (storage logging comes from the diagnostic settings) |
| False positive | CKV2_AZURE_31 (the subnet NSG association is missed on counted resources) |
| tflint, inline ignores | `azurerm_resources_missing_prevent_destroy` on the storage account, container, blob, Key Vault and secret (the stack must be destroyable); `azurerm_app_service_missing_auto_heal_setting` (no application) |
| Same as infra/lab (ADR 0004) | App Service Free tier and no application; ACR Premium-only features; container group without IP; storage name false positive |
