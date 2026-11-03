# Fenrir operation inventory and Sentinel log sources

Source reviewed: Fenrir `main` at commit `5959162`. Read-only review. Nothing was run.

Paths are relative to the Fenrir package root (`src/fenrir/`). Every operation has an ID
(`A-` auth, `E-` enumerate, `X-` exploit, `P-` post-exploit) that the other Huggin docs reuse.

Fenrir uses no Azure SDK. Every call is a raw `requests` call to a hard-coded URL, and
authentication goes through `msal`. This makes the inventory complete from a `grep` of
`requests.` plus the URL constants. Each call site was then read by hand.

## Headline facts for the defender

1. **No PUT, PATCH or DELETE anywhere.** Fenrir never creates, changes or deletes an
   Azure resource. It never writes a role assignment and never attaches an identity.
   `core/enumerate/verdict.py` only *reports* that the caller could do these things
   (`ROLE_ASSIGNMENT_WRITE_ROLES`, `UAI_ASSIGN_ROLES`).
2. **No Entra ID directory changes.** Every Graph call is a GET. Fenrir writes nothing
   to `AuditLogs`.
3. **Its whole `AzureActivity` footprint is six POST actions** (X-08, X-10, X-13, X-14,
   P-12, P-13). Everything else is an ARM GET, which `AzureActivity` does not record.
4. **The Automation Account path is read-only.** `exploit_automation_account` lists
   runbooks and reads runbook source, variables and credential metadata with GETs. It does
   not start a job. The RBAC preflight checks for `runbooks/draft/write`, but nothing
   writes a draft.
5. **`--dry-run` does not stop the credential listing.** In `post-exploit`, `listKeys`
   (P-12) and `listCredentials` (P-13) run before the dry-run check. Only the data-plane
   download is skipped.
6. **Post-exploit runs as the managed identity**, using a token captured during `exploit`
   (or one passed with `--access-token`). Its ARM calls come from the operator's machine,
   but `Caller` is the managed identity.

## Authentication (all commands)

| ID | File:function | What it does | Default |
|---|---|---|---|
| A-01 | `core/authenticator.py:AzureAuthenticator.app` / `_default_client_id` | MSAL `PublicClientApplication`. Client ID `04b07795-8ddb-461a-bbee-02f9e1bf7b46` (**Microsoft Azure CLI**, first-party), unless `AZAUTH_CLIENT_ID` or `--client-id` is set. Authority `https://login.microsoftonline.com/common`, or `/{tenant}` if `--tenant` is set. | Always |
| A-02 | `core/authenticator.py:_device_code_flow` | Device code flow. Initial scope `https://graph.microsoft.com/.default`. | **Default flow** (`login`, `AZAUTH_AUTH_FLOW` unset) |
| A-03 | `core/authenticator.py:_interactive_flow` | Interactive browser flow. The `login` help text says it needs your own client ID. | Only with `--auth-flow interactive` |
| A-04 | `core/authenticator.py:_ropc_flow` | Resource owner password credentials (username + password). | Only with `--auth-flow ropc` |
| A-05 | `core/authenticator.py:get_token_for_scopes` / `_try_silent` | Silent token for a second resource (`https://management.azure.com/.default`) from the cached refresh token. If that fails, it falls back to a **new device code prompt**. | Every `enumerate` and `exploit` run |

`exploit` builds `Credentials()` with defaults (`commands/exploit.py:exploit`), so it reuses the
cache from `login`. `post-exploit` does not sign in a user at all: it uses the cached managed
identity token.

---

## Step 1: Operation inventory

Conventions:
- `{s}` subscription ID, `{rg}` resource group name, `{rgId}` full RG resource ID,
  `{id}` full resource ID.
- "Read" means HTTP GET. "Action" means a POST to an ARM `/action`-style endpoint.
- Graph base URL is `https://graph.microsoft.com/v1.0`. ARM base is `https://management.azure.com`.

### `enumerate` (`commands/enumerate.py:enumerate_cmd`)

The caller is the signed-in user (A-01 to A-05).

| ID | File:function | Service | Method + path | API version | Read / action | When |
|---|---|---|---|---|---|---|
| E-01 | `core/enumerate/collector.py:collect_me` | Graph | GET `/me` | v1.0 | Read | Always |
| E-02 | `collector.py:collect_domains` | Graph | GET `/domains` | v1.0 | Read | Always |
| E-03 | `collector.py:collect_directory_roles` | Graph | GET `/roleManagement/directory/roleAssignments?$expand=roleDefinition` | v1.0 | Read | Always |
| E-04 | `collector.py:collect_pim_roles` | Graph | GET `/roleManagement/directory/roleEligibilityScheduleInstances` | v1.0 | Read | Always (errors ignored) |
| E-05 | `collector.py:collect_groups` | Graph | GET `/me/transitiveMemberOf` | v1.0 | Read | Always |
| E-06 | `collector.py:collect_owned_apps`, `collect_owned_service_principals` | Graph | GET `/me/ownedObjects` (called twice) | v1.0 | Read | Always |
| E-07 | `collector.py:collect_managed_devices` | Graph | GET `/me/managedDevices` | v1.0 | Read | Always (errors ignored) |
| E-08 | `collector.py:collect_management_groups` | ARM | GET `/providers/Microsoft.Management/managementGroups` | 2020-05-01 | Read | Always |
| E-09 | `collector.py:collect_subscriptions` | ARM | GET `/subscriptions` | 2020-01-01 | Read | Skipped with `--no-resources` |
| E-10 | `collector.py:_role_assignments_at_scope` (via `_role_names_at_scope`, `fetch_rg_resources`) | ARM | GET `{scope}/providers/Microsoft.Authorization/roleAssignments` | 2022-04-01 | Read | Once per subscription, per RG **and per resource**. Skipped with `--no-resources` |
| E-11 | `collector.py:_role_names` | ARM | GET `/subscriptions/{s}/providers/Microsoft.Authorization/roleDefinitions/{guid}` | 2022-04-01 | Read | Once per distinct role (cached) |
| E-12 | `collector.py:_collect_subscription_resources` | ARM | GET `/subscriptions/{s}/resourceGroups` | 2021-04-01 | Read | Per subscription |
| E-13 | `collector.py:_collect_subscription_resources.fetch_rg_resources` | ARM | GET `/subscriptions/{s}/resourceGroups/{rg}/resources` | 2021-04-01 | Read | Per RG |

**"Interesting RG" block.** E-14 to E-27 run only for an RG where the caller holds one of
`INTERESTING_ROLE_NAMES` (`exploit/arm_enum.py`): Owner, Contributor, User Access Administrator,
Virtual Machine Contributor, Managed Identity Operator, Managed Identity Contributor, Website
Contributor, Logic App Contributor, Automation Contributor, Automation Operator, or Azure
Container Instances Contributor Role. Entry point: `collector.py:_collect_interesting_group` calls
`exploit/discovery.py:collect_interesting_group`. The same block is reused by `exploit` (X-05).

| ID | File:function | Service | Method + path | API version | Read / action | When |
|---|---|---|---|---|---|---|
| E-14 | `exploit/discovery.py:resolve_role_name` → `arm_enum.py:get_role_definition_name` | ARM | GET `{roleDefinitionId}` | 2022-04-01 | Read | Custom roles only (built-ins resolved locally) |
| E-15 | `arm_enum.py:list_managed_identities` | ARM | GET `/subscriptions/{s}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities` | 2023-01-31 | Read | Per interesting RG |
| E-16 | `arm_enum.py:list_virtual_machines` | ARM | GET `.../providers/Microsoft.Compute/virtualMachines` | 2023-03-01 | Read | Per interesting RG |
| E-17 | `arm_enum.py:list_service_principals_in_rg` | ARM | GET `{rgId}/providers/Microsoft.Authorization/roleAssignments` | 2022-04-01 | Read | Per interesting RG |
| E-18 | `arm_enum.py:list_app_services` | ARM | GET `.../providers/Microsoft.Web/sites` | 2022-03-01 | Read | Per interesting RG |
| E-19 | `arm_enum.py:enrich_app_service_capabilities` | ARM | GET `{siteId}/basicPublishingCredentialsPolicies/scm` (2024-04-01), then GET `{serverFarmId}` (2023-12-01) | see path | Read | Per site |
| E-20 | `arm_enum.py:list_container_groups` | ARM | GET `.../providers/Microsoft.ContainerInstance/containerGroups` | 2023-05-01 | Read | Per interesting RG |
| E-21 | `arm_enum.py:list_logic_apps` | ARM | GET `.../providers/Microsoft.Logic/workflows` | 2019-05-01 | Read | Per interesting RG |
| E-22 | `arm_enum.py:list_automation_accounts` | ARM | GET `.../providers/Microsoft.Automation/automationAccounts` | 2022-08-08 | Read | Per interesting RG |
| E-23 | `arm_enum.py:list_all_resources_in_rg` | ARM | GET `/subscriptions/{s}/resourceGroups/{rg}/resources` | 2021-04-01 | Read | Per interesting RG |
| E-24 | `discovery.py:enrich_mi_role_assignments` → `arm_enum.py:get_role_assignments` | ARM | GET `/subscriptions/{s}/providers/Microsoft.Authorization/roleAssignments`, then GET `{rgId}/providers/Microsoft.Authorization/roleAssignments` | 2022-04-01 | Read | Per user-assigned identity found in E-15 |
| E-25 | `arm_enum.py:get_effective_actions_at_scope` | ARM | GET `{rgId}/providers/Microsoft.Authorization/permissions` | 2018-01-01-preview | Read | Per interesting RG |
| E-26 | `arm_enum.py:enrich_resource_permissions` → `get_role_definition_actions` | ARM | GET `{roleDefinitionId}` | 2022-04-01 | Read | Only if E-25 returns nothing |
| E-27 | `arm_enum.py:fetch_access_policies` | ARM | GET `{id}` (Key Vault, Storage, ACR, Web, SQL, Event Hubs, Service Bus, Cognitive Services, AKS, Batch, Automation, Search, APIM, App Gateway, Synapse, MySQL, PostgreSQL, SignalR, Web PubSub, Relay) | per type, see `ACCESS_POLICY_RESOURCE_TYPES` | Read | Per resource of those 20 types |

### `exploit` (`commands/exploit.py:exploit` → `exploit/orchestrator.py:ExploitOrchestrator`)

The caller is the signed-in user, except X-19 to X-21, where the caller is the managed identity.

**Discovery.** Runs only when there is no saved state from `enumerate`, when `--fresh` is set, or
when the saved state has no interesting RG. Entry point: `orchestrator.py:discover` →
`discovery.py:discover`.

| ID | File:function | Service | Method + path | API version | Read / action | When |
|---|---|---|---|---|---|---|
| X-01 | `arm_enum.py:list_subscriptions` | ARM | GET `/subscriptions` | 2021-04-01 | Read | Discovery |
| X-02 | `arm_enum.py:list_resource_groups` | ARM | GET `/subscriptions/{s}/resourceGroups` | 2021-04-01 | Read | Per subscription |
| X-03 | `discovery.py:get_current_principal_id` | ARM | GET `/me` | 2021-01-01 | Read | **Once per RG** in discovery. Also once in `exploit` when saved state has a `principal_id`. If it fails, the code falls back to the token's `oid` claim. Verify in lab what ARM returns for this path. |
| X-04 | `arm_enum.py:get_role_assignments` | ARM | GET `{rgId}/providers/Microsoft.Authorization/roleAssignments` | 2022-04-01 | Read | Per RG |
| X-05 | `discovery.py:collect_interesting_group` | ARM | Same calls as E-14 to E-27 | see above | Read | Per interesting RG |
| X-06 | `discovery.py:cross_reference_enterprise_apps` → `arm_enum.py:list_enterprise_apps` | Graph | GET `/servicePrincipals?$top=999` (follows `@odata.nextLink`, so it reads **every** service principal in the tenant) | v1.0 | Read | Always in `exploit`, whenever a Graph token can be obtained (fresh discovery and saved-state paths) |

**Exploitation.** Runs by default. Skipped entirely with `--skip-run-command`. For each interesting
RG, `orchestrator.py:exploit_resource_types` runs first, then `orchestrator.py:extract_mi_tokens`.

| ID | File:function | Service | Method + path | API version | Read / action | When |
|---|---|---|---|---|---|---|
| X-07 | `resource_exploit.py:_check_rbac_preflight` → `arm_enum.py:check_action_allowed_at_scope` | ARM | GET `{id}/providers/Microsoft.Authorization/permissions` | 2018-01-01-preview | Read | Before every X-08, X-10, X-12, X-14, X-15 attempt |
| X-08 | `exploit/run_command.py:run_shell_command` (called by `resource_exploit.py:exploit_vm_run_command`) | ARM | POST `/subscriptions/{s}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/{vm}/runCommand`. Body `commandId` is `RunShellScript` or `RunPowerShellScript` (`imds_payload.py`). | 2021-07-01 | **Action** | **Every VM** in an interesting RG, whether or not it has an identity (`exploit_resource_types`). Then **once more per attached user-assigned identity** (`extract_mi_tokens`), deduplicated by client ID across hosts. A VM with N user-assigned identities gets N+1 Run Commands. |
| X-09 | `run_command.py:run_shell_command` | ARM | GET the `Azure-AsyncOperation` URL returned by X-08, every 5 s | from header | Read | After each X-08, until done or 300 s |
| X-10 | `resource_exploit.py:exploit_app_service_kudu` | ARM | POST `{siteId}/config/publishingcredentials/list` | 2022-03-01 | **Action** | Every Web App / Function App in an interesting RG, unless E-19 showed a Flex Consumption plan or SCM basic auth disabled. Repeated per user-assigned identity in `extract_mi_tokens`. |
| X-11 | `resource_exploit.py:exploit_app_service_kudu._kudu_request` | Kudu (not ARM) | POST `https://{app}.scm.{domain}/api/command` with Basic auth from X-10 | n/a | Action (data plane) | After X-10 succeeds. See the non-ARM appendix. |
| X-12 | `resource_exploit.py:exploit_logic_app_callback` | ARM | GET `{workflowId}/triggers` | 2019-05-01 | Read | Every Logic App (Consumption) in an interesting RG |
| X-13 | `resource_exploit.py:exploit_logic_app_callback` | ARM | POST `{workflowId}/triggers/{trigger}/listCallbackUrl` | 2019-05-01 | **Action** | Per trigger, stopping at the first success. Repeated per user-assigned identity on the workflow. Fenrir lists the URL but does not call it. |
| X-14 | `resource_exploit.py:exploit_container_group_exec` | ARM | POST `{containerGroupId}/containers/{container}/exec`, body `command` `/bin/sh` or `cmd.exe` | 2023-05-01 | **Action** | First container of every container group in an interesting RG |
| X-15 | `resource_exploit.py:exploit_automation_account` | ARM | GET `{automationAccountId}/runbooks` | 2022-08-08 | Read | Every Automation Account in an interesting RG |
| X-16 | `resource_exploit.py:exploit_automation_account` | ARM | GET `{automationAccountId}/runbooks/{name}/content` | 2022-08-08 | Read | Per runbook (downloads the source) |
| X-17 | `resource_exploit.py:exploit_automation_account` | ARM | GET `{automationAccountId}/variables` | 2022-08-08 | Read | Per Automation Account |
| X-18 | `resource_exploit.py:exploit_automation_account` | ARM | GET `{automationAccountId}/credentials` | 2022-08-08 | Read | Per Automation Account (names and user names only) |

**Identity check.** `orchestrator.py:enumerate_identity` → `exploit/identity_enum.py:enumerate_with_token`.
Runs only for targets that returned an ARM access token, which in practice means X-08 and X-11.
**The caller is the managed identity**, and the source IP is the operator's machine.

| ID | File:function | Service | Method + path | API version | Read / action | When |
|---|---|---|---|---|---|---|
| X-19 | `arm_enum.py:list_subscriptions` | ARM | GET `/subscriptions` | 2021-04-01 | Read | Per captured identity |
| X-20 | `arm_enum.py:list_resource_groups` | ARM | GET `/subscriptions/{s}/resourceGroups` | 2021-04-01 | Read | Per subscription visible to the identity |
| X-21 | `identity_enum.py:_check_user_roles` | ARM | GET `{rgId}/providers/Microsoft.Authorization/roleAssignments` | 2022-04-01 | Read | Per RG |

### `post-exploit` (`commands/post_exploit.py:post_exploit` → `exploit/post_exploit.py:PostExploitEnumerator`)

**The caller is the managed identity** (cached token from `exploit`, or `--access-token`). The
source IP is the operator's machine. No Graph calls.

| ID | File:function | Service | Method + path | API version | Read / action | When |
|---|---|---|---|---|---|---|
| P-01 | `post_exploit.py:enumerate` → `arm_enum.py:list_subscriptions` | ARM | GET `/subscriptions` | 2021-04-01 | Read | Always |
| P-02 | `arm_enum.py:list_resource_groups` | ARM | GET `/subscriptions/{s}/resourceGroups` | 2021-04-01 | Read | Per subscription |
| P-03 | `post_exploit.py:_enumerate_rg` | ARM | Same paths as E-15, E-16, E-18, E-20, E-21, E-22, E-23 (no E-19) | as above | Read | Per RG (no role gate here) |
| P-04 | `post_exploit.py:_enumerate_rg` → `get_effective_actions_at_scope` | ARM | GET `{rgId}/providers/Microsoft.Authorization/permissions` | 2018-01-01-preview | Read | Per RG |
| P-05 | `post_exploit.py:_enumerate_rg` → `fetch_access_policies` | ARM | GET `{id}` | per type | Read | Per resource of the 20 types in E-27 |
| P-06 | `post_exploit.py:list_identity_role_assignments` | ARM | GET `/subscriptions/{s}/providers/Microsoft.Authorization/roleAssignments?$filter=principalId eq '{oid}'` | 2022-04-01 | Read | Per subscription |
| P-07 | `post_exploit.py:_role_name_for` → `get_role_definition_name` | ARM | GET `{roleDefinitionId}` | 2022-04-01 | Read | Non-built-in roles, cached |
| P-08 | `storage.py:list_storage_accounts_in_scope` | ARM | GET `/subscriptions/{s}/providers/Microsoft.Storage/storageAccounts` | 2023-01-01 | Read | Always |
| P-09 | `storage.py:resolve_storage_capabilities` | ARM | GET `{storageAccountId}/providers/Microsoft.Authorization/permissions` | 2018-01-01-preview | Read | Per storage account |
| P-10 | `acr.py:list_registries_in_scope` | ARM | GET `/subscriptions/{s}/providers/Microsoft.ContainerRegistry/registries` | 2023-06-01-preview | Read | Always |
| P-11 | `acr.py:resolve_registry_capabilities` | ARM | GET `{registryId}/providers/Microsoft.Authorization/permissions` | 2018-01-01-preview | Read | Per registry |
| P-12 | `storage.py:list_storage_account_keys` (from `harvest_storage_account`) | ARM | POST `{storageAccountId}/listKeys` | 2023-01-01 | **Action** | Only with `--dump-blobs`, and only on accounts where P-09 shows `listKeys/action`. **Also runs with `--dry-run`.** Asks for confirmation unless `--yes` or `--dry-run`. |
| P-13 | `acr.py:list_registry_admin_creds` (from `harvest_container_registry`) | ARM | POST `{registryId}/listCredentials` | 2023-06-01-preview | **Action** | Only with `--dump-images`, and only where P-11 shows `listCredentials/action`. **Also runs with `--dry-run`.** |

### Appendix: non-ARM, non-Graph endpoints

These are outside the Step 1 scope, but they matter for Sentinel because some have their own log tables.

| ID | File:function | Endpoint | When | Possible log source |
|---|---|---|---|---|
| X-11 | `resource_exploit.py:exploit_app_service_kudu` | `https://{app}.scm.*/api/command` (Basic auth with publishing credentials) | After X-10 | `AppServiceAuditLogs` (publishing-credential logins, `Protocol`), `AppServiceHTTPLogs`. Needs diagnostic settings on the app. Verify in lab that a Kudu `/api/command` call with Basic auth appears and with which fields. |
| D-01 | `storage.py:_harvest_blobs`, `download_blob` | `https://{account}.blob.core.windows.net` list + GET (SharedKey from P-12, or OAuth) | `post-exploit --dump-blobs` (listing only with `--dry-run`) | `StorageBlobLogs` (`AuthenticationType` = `AccountKey` or `OAuth`). Needs diagnostic settings. |
| D-02 | `storage.py:_harvest_files`, `walk_share_files` | `https://{account}.file.core.windows.net` | `post-exploit --dump-blobs` | `StorageFileLogs`. Needs diagnostic settings. |
| D-03 | `acr.py:_exchange_refresh_token`, `_RegistryClient` | `https://{registry}/oauth2/exchange`, `/oauth2/token`, `/v2/_catalog`, `/v2/{repo}/tags/list`, `/manifests/`, `/blobs/` | `post-exploit --dump-images` | `ContainerRegistryLoginEvents`, `ContainerRegistryRepositoryEvents`. Needs diagnostic settings. |

---

## Step 2: Log source for each operation

### Sign-in (A-01 to A-05)

| Log | What appears | Key fields |
|---|---|---|
| `SigninLogs` | The device code sign-in (A-02), or ROPC (A-04), or interactive (A-03). | `AppId` = `04b07795-8ddb-461a-bbee-02f9e1bf7b46`, `AppDisplayName` = "Microsoft Azure CLI", `AuthenticationProtocol` = `deviceCode` (A-02) or `ropc` (A-04), `ResourceDisplayName` = "Microsoft Graph", `IPAddress`, `UserAgent`. Verify in lab the exact `AuthenticationProtocol` string and which `UserAgent` is recorded for a device code sign-in (the browser that entered the code, or the MSAL client). |
| `AADNonInteractiveUserSignInLogs` | A-05 refresh-token redemptions for ARM and Graph. | Same `AppId`. `ResourceDisplayName` = "Windows Azure Service Management API" (`797f4846-ba00-4fd7-ba43-dac1f8f63013`) or "Microsoft Graph". |
| `AADManagedIdentitySignInLogs` | Token issuance to the managed identity on the host during X-08 / X-11 (this is the host side, so it is noted here only as a log source). | `ServicePrincipalId`, `ServicePrincipalName`, `ResourceDisplayName` / `ResourceIdentity` = Azure Resource Manager. |

Licence: Entra ID sign-in logs can be sent to Log Analytics only with Entra ID P1 or P2.
Verify in lab that this also covers `AADManagedIdentitySignInLogs`.

Defender note: by default the Fenrir sign-in is indistinguishable by `AppId` from a normal
`az login --use-device-code`, because it uses the Azure CLI's own public client ID. Do not build a
rule on the client ID alone.

### Graph operations (E-01 to E-07, X-06)

| Op | `AuditLogs` | `MicrosoftGraphActivityLogs` | Notes |
|---|---|---|---|
| E-01 to E-07 | No (reads) | Yes, one row per request: `RequestMethod` GET, `RequestUri`, `AppId` (Azure CLI), `UserId`, `IPAddress`, `UserAgent`, `ResponseStatusCode` | Needs a diagnostic setting on Entra ID that sends `MicrosoftGraphActivityLogs` to the workspace, and an Entra ID P1 or P2 licence in the tenant. Verify in lab. |
| X-06 | No (read) | Yes, one row per page of `/servicePrincipals?$top=999` | Same requirements. |

Without `MicrosoftGraphActivityLogs`, all Graph enumeration is a **blind spot**.

### ARM operations

`AzureActivity` records control-plane write, delete and action operations. It does not record
GETs. Every row below marked "blind spot" is a GET.

| Op | Log source | Expected `OperationNameValue` | Notes |
|---|---|---|---|
| E-08 to E-27 | **Blind spot** | n/a | ARM reads |
| X-01 to X-07, X-09 | **Blind spot** | n/a | ARM reads, including the RBAC permission preflight (X-07) |
| **X-08** | `AzureActivity` | `MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMAND/ACTION` | Several rows per call (start, accept, success or failure) sharing one `CorrelationId`. A 403 should appear as a failed row. Verify in lab. |
| **X-10** | `AzureActivity` | `MICROSOFT.WEB/SITES/CONFIG/LIST/ACTION` | The same operation name covers `config/appsettings/list` and `config/connectionstrings/list`. Verify in lab whether `_ResourceId` or `Properties_d.entity` keeps the `/config/publishingcredentials` suffix, so the rule can tell them apart. |
| X-11 | Not in `AzureActivity` | n/a | See the non-ARM appendix |
| X-12 | **Blind spot** | n/a | Read |
| **X-13** | `AzureActivity` | `MICROSOFT.LOGIC/WORKFLOWS/TRIGGERS/LISTCALLBACKURL/ACTION` | Verify in lab that this POST is recorded and whether `_ResourceId` is the trigger or the workflow. |
| **X-14** | `AzureActivity` | `MICROSOFT.CONTAINERINSTANCE/CONTAINERGROUPS/CONTAINERS/EXEC/ACTION` | Only the session creation is logged. What happens in the session is not. Verify in lab. |
| X-15 to X-18 | **Blind spot** | n/a | Reading runbook **source code**, variables and credential names leaves no `AzureActivity` record |
| X-19 to X-21 | **Blind spot** | n/a | ARM reads, made **as the managed identity from the operator's IP**. Nothing in Sentinel records them. |
| P-01 to P-11 | **Blind spot** | n/a | ARM reads as the managed identity |
| **P-12** | `AzureActivity` | `MICROSOFT.STORAGE/STORAGEACCOUNTS/LISTKEYS/ACTION` | `Caller` is the managed identity (expect its object ID GUID; verify in lab whether it is the object ID or the app ID). `CallerIpAddress` is the operator's IP. |
| **P-13** | `AzureActivity` | `MICROSOFT.CONTAINERREGISTRY/REGISTRIES/LISTCREDENTIALS/ACTION` | Same caller and IP pattern as P-12 |

### Summary of the Sentinel-visible footprint

| Command | `AzureActivity` | `AuditLogs` | `MicrosoftGraphActivityLogs` | Sign-in logs |
|---|---|---|---|---|
| `login` | none | none | none | `SigninLogs` (device code by default), `AADNonInteractiveUserSignInLogs` |
| `enumerate` | **none** | none | E-01 to E-07 | non-interactive ARM token (A-05) |
| `exploit` | X-08, X-10, X-13, X-14 | none | X-06 | non-interactive; `AADManagedIdentitySignInLogs` for each captured identity |
| `post-exploit` | P-12, P-13 (only with `--dump-blobs` / `--dump-images`) | none | none | none for the user. The identity token was minted earlier. |

`enumerate` on its own, and `post-exploit` without the dump flags, leave **no `AzureActivity`
record at all**.
