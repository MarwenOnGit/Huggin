# Legitimate look-alikes and exclusion strategy

This doc covers every Fenrir operation that lands in `AzureActivity`. None land in `AuditLogs`
(see [FENRIR-OPERATIONS.md](FENRIR-OPERATIONS.md)). It also covers the three Huginn rules that
Fenrir does not trigger but that watch writes (`rbac-self-assignment`, `uai-attached-to-host`,
`automation-runbook-run`).

Everything here describes **expected** behaviour from documentation and common practice. Each
claim marked "verify in lab" must be checked with a benign replay before it becomes an exclusion.

## 1. Fields that separate legitimate use from abuse

| Field | Where | What it tells you |
|---|---|---|
| `Caller` | `AzureActivity` | UPN for a user. GUID for a service principal or managed identity. Verify in lab whether the GUID is the object ID or the app ID for each caller type. |
| `Claims_d.idtyp` | `AzureActivity` | `user` or `app`. Verify in lab that this claim is kept in `Claims_d`. |
| `Claims_d.appid` | `AzureActivity` | The **client application** that got the token. This is how you tell portal, CLI, PowerShell and pipelines apart. |
| `Claims_d.xms_mirid` | `AzureActivity` | Present only in managed identity tokens: the resource ID of the identity. Verify in lab that it appears in `Claims_d`. If it does, it is the cleanest "caller is a managed identity" test. |
| `Claims_d["http://schemas.microsoft.com/identity/claims/objectidentifier"]` | `AzureActivity` | Caller object ID. Needed to compare the caller with a role assignment's target. |
| `CallerIpAddress` | `AzureActivity` | Public IP for users and off-Azure callers. Azure-internal or Azure public ranges for first-party services and in-Azure workloads. |
| `CorrelationId` | `AzureActivity` | Shared by every row of one request, and by the child operations of an ARM/Bicep deployment. Join on it to see whether an action ran **inside a deployment**. |
| `OperationNameValue`, `ActivityStatusValue` | `AzureActivity` | What happened, and whether it worked. A burst of failures is itself a signal (permission probing). |
| `_ResourceId`, `Properties_d.entity` | `AzureActivity` | Which resource. For some actions the suffix (for example `/config/publishingcredentials`) is the only way to tell sub-operations apart. Verify in lab. |

### Common client application IDs (verify each in your tenant)

| Client | `appid` |
|---|---|
| Azure portal | `c44b4083-3bb0-49c1-b47d-974e53cbdf3c` |
| Azure CLI (and anything else using its public client ID, **including Fenrir by default**) | `04b07795-8ddb-461a-bbee-02f9e1bf7b46` |
| Azure PowerShell | `1950a258-227b-4e31-a9cf-717495945fc2` |
| Visual Studio | `872cd9fa-d31f-45e0-9eab-6e460a02d1f1` |
| Visual Studio Code | `aebc6443-996d-45c2-90f0-388ff96faa56` |
| Microsoft PIM (MS-PIM) | `01fc33a7-78ba-4d2f-a4b7-768e336e890e` |
| Terraform azurerm, GitHub Actions, Azure DevOps | **The pipeline's own service principal or federated identity.** If Terraform runs on a laptop with `az login`, it shows the Azure CLI `appid`. |

### How each legitimate source usually looks

| Source | `idtyp` | `appid` | Inside a deployment? | Typical pattern |
|---|---|---|---|---|
| Azure portal | user | portal | no | One person, one resource, during working hours, from a corporate or known IP |
| Azure CLI / PowerShell | user (sometimes app) | CLI / PowerShell | no | Admin workstation or jump host. Same person repeats the same action. |
| Terraform (azurerm) | app (pipeline SP) or user via CLI | pipeline SP, or CLI | no. Terraform calls ARM directly, there is no deployment wrapper. | Bursts at plan/apply time. **Refresh re-reads secrets on every plan**, so the same set of resources is touched on a regular schedule. |
| Bicep / ARM templates | user or app | portal, CLI, PowerShell or pipeline SP | **yes**: shares `CorrelationId` with `MICROSOFT.RESOURCES/DEPLOYMENTS/WRITE` | `list*()` template functions run as the deployer during deployment. Verify in lab that the `CorrelationId` link holds for `listKeys()` and `listCallbackUrl()`. |
| GitHub Actions / Azure DevOps | app | pipeline SP (federated or secret) | sometimes | Runner IPs (GitHub-hosted runners rotate across Azure ranges, self-hosted runners are fixed). Matches commit or release times. |
| Azure Policy remediation (DeployIfNotExists / Modify) | app (managed identity of the policy assignment) | managed identity | yes, for DeployIfNotExists | Same identity touches many resources of one type, usually right after resource creation or a remediation task |
| Microsoft first-party services | app | Microsoft-owned app IDs | no | Azure IPs, steady cadence, many resources. Build the list from a 30-day baseline, never from memory. |

### Exclusion principles used in every rule

1. **Never exclude a whole client app** such as the portal or the CLI. An attacker with a stolen
   session uses the same clients. Fenrir uses the CLI's client ID by default.
2. **Exclude identities, not tools.** Keep approved automation in a Sentinel watchlist
   `HuginnTrustedAutomation` with columns `PrincipalId`, `AppId`, `ScopePrefix`, `Operation`,
   `Owner`, `Reason`, `ExpiresOn`. Match on principal **and** scope **and** operation.
   Review it on a schedule and let entries expire.
3. **Prefer "new for this caller" over static allow lists** for noisy operations: compare the
   last hour against a 14-day baseline of (caller, resource) or (caller, IP) pairs.
4. **Deployment context reduces risk but does not remove it.** Downgrade severity when an action
   shares a `CorrelationId` with a deployment by a trusted identity. Do not drop the event.
5. **Managed identities acting from an IP they have never used before are never excluded.**
   This is the core signal of a stolen identity token being used outside its host.

---

## 2. Per-operation baseline

### VM Run Command (X-08): `MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMAND/ACTION`

| Legitimate source | What it looks like |
|---|---|
| Portal "Run command" blade | User, portal `appid`, one VM, `RunShellScript` / `RunPowerShellScript`, often during an incident or troubleshooting |
| `az vm run-command invoke` | User, CLI `appid`. Same operation name as Fenrir. |
| Pipelines (GitHub Actions, Azure DevOps) | Pipeline SP, fixed set of VMs, matches release windows |
| Terraform | Rare. Terraform normally uses the managed `runCommands` resource (`MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMANDS/WRITE`), not this action. |
| Microsoft first-party services | Verify in lab. Some management services may use Run Command. Baseline 30 days before writing any exclusion. |

What is unusual: a user (any client) running commands on **several VMs in a short window**,
including VMs that have no recent Run Command history. Fenrir targets **every** VM in each RG
where the caller has a strong role, and repeats once per attached user-assigned identity.

**Exclusion strategy for `vm-runcommand-by-user`:** watchlist match on (pipeline principal, VM
scope prefix). No exclusion for interactive users. Instead, severity rises with the number of
distinct VMs and with any failed attempts.

### App Service publishing credentials (X-10): `MICROSOFT.WEB/SITES/CONFIG/LIST/ACTION`

| Legitimate source | What it looks like |
|---|---|
| Portal: Configuration blade | Same operation name, but for `config/appsettings` and `config/connectionstrings`. **The main false-positive source if the rule cannot see the suffix.** |
| Portal: Deployment Center, FTPS credentials | User, portal `appid`, `config/publishingcredentials` |
| Visual Studio / VS Code publish | User, Visual Studio or VS Code `appid`. Often uses `MICROSOFT.WEB/SITES/PUBLISHXML/ACTION` (download publish profile) instead. |
| Azure DevOps "Azure App Service deploy" task, GitHub Actions `azure/webapps-deploy` | Pipeline SP, the same sites on each release. Verify in lab whether these tasks call `publishingcredentials/list` or deploy with an Entra token. |
| Terraform `azurerm_linux_web_app` / `azurerm_windows_web_app` | Pipeline SP on **every plan/refresh**, because the provider reads `site_credential`. Verify in lab. |

**Exclusion strategy for `appservice-publish-creds`:** first, filter to the
`/config/publishingcredentials` suffix and `PUBLISHXML`. If the lab shows the suffix is not
visible, fall back to "new (caller, site) pair in 14 days". Watchlist pipeline and Terraform
principals per site scope.

### Logic App callback URL (X-13): `MICROSOFT.LOGIC/WORKFLOWS/TRIGGERS/LISTCALLBACKURL/ACTION`

| Legitimate source | What it looks like |
|---|---|
| Portal Logic Apps designer | User, portal `appid`. Opening a workflow with a Request trigger shows the URL, which may call this action. **Frequent for Logic App developers.** Verify in lab. |
| Terraform `azurerm_logic_app_trigger_http_request` | Pipeline SP on every refresh (reads `callback_url`). Verify in lab. |
| Bicep / ARM `listCallbackUrl()` | Inside a deployment (`CorrelationId` link) |
| API Management importing a Logic App, Event Grid subscriptions | First-party or deployer identity, at configuration time |

**Exclusion strategy for `logicapp-callback-listed`:** "new (caller, workflow) pair in 14 days",
plus the watchlist for pipeline principals. A developer who opens their own workflow every day
builds a baseline and stops alerting. A stranger listing several workflows does not.

### Container Instances exec (X-14): `MICROSOFT.CONTAINERINSTANCE/CONTAINERGROUPS/CONTAINERS/EXEC/ACTION`

| Legitimate source | What it looks like |
|---|---|
| Portal "Connect" on a container | User, portal `appid`, one container, interactive debugging |
| `az container exec` | User, CLI `appid` |
| Pipelines | Rare. Exec in CI is unusual and worth a review anyway. |

**Exclusion strategy for `aci-exec`:** low volume, so alert on every exec except watchlisted
principals at a matching scope. Raise severity for more than one container group per caller per hour.

### Storage account keys (P-12): `MICROSOFT.STORAGE/STORAGEACCOUNTS/LISTKEYS/ACTION`

This is the noisiest operation in the set.

| Legitimate source | What it looks like |
|---|---|
| Portal: Access keys blade, Storage browser, some data blades | User, portal `appid` |
| Azure Storage Explorer | User. Verify the `appid` in lab. |
| Terraform `azurerm_storage_account` | Pipeline SP on **every plan/refresh**, because the provider reads the access keys. Same accounts every time. |
| Bicep / ARM `listKeys()` | Inside a deployment |
| Function Apps, Logic App connectors, Data Factory, Synapse, Machine Learning, Azure Monitor and other first-party services | Microsoft-owned or workload identities, Azure IPs, steady cadence |
| Azure Policy remediation | Policy assignment managed identity, inside a deployment |

What is unusual for Fenrir's case: the **caller is a managed identity** (the identity captured
during `exploit`), and `CallerIpAddress` is **outside Azure / never seen for that identity**. A
second pattern is one caller listing keys on many accounts in an hour.

**Exclusion strategy for `storage-keys-listed`:** the rule keeps three branches. Branch A, managed
identity from a new IP: no exclusions. Branch B, one caller on 3 or more accounts in an hour:
exclude watchlisted Terraform and pipeline principals at matching scope. Branch C, new (caller,
account) pair: exclude watchlisted principals and anything inside a deployment by a trusted identity.

### Container registry admin credentials (P-13): `MICROSOFT.CONTAINERREGISTRY/REGISTRIES/LISTCREDENTIALS/ACTION`

| Legitimate source | What it looks like |
|---|---|
| Portal Access keys blade | User, portal `appid` |
| `az acr credential show` | User, CLI `appid` |
| Terraform `azurerm_container_registry` with `admin_enabled = true` | Pipeline SP on every refresh |
| App Service / Container Apps configured with admin credentials | Deployer at configuration time |

Normal `az acr login` with an Entra identity uses a token exchange, not `listCredentials`.

**Exclusion strategy for `acr-admin-creds-listed`:** same three branches as storage keys.
Volume is much lower, so branch C can stay on with only the watchlist.

### Role assignment write (not done by Fenrir): `MICROSOFT.AUTHORIZATION/ROLEASSIGNMENTS/WRITE`

| Legitimate source | What it looks like |
|---|---|
| PIM for Azure resources activation | Principal assigns to itself in effect, but `Caller` / `appid` is MS-PIM. **The main self-assignment false positive.** |
| Portal IAM blade, `az role assignment create` | User grants a role to **someone else** |
| Terraform `azurerm_role_assignment`, Bicep | Pipeline SP, or inside a deployment |
| Azure Policy remediation | Policy managed identity grants roles to other managed identities |
| Azure Lighthouse | Delegated principals, at onboarding |

**Exclusion strategy for `rbac-self-assignment`:** only fire when the caller object ID equals the
`principalId` in the request body. Exclude MS-PIM by `appid`. Do not exclude pipelines, because a
pipeline SP granting itself a role is exactly the abuse case.

### Identity attached to a host (not done by Fenrir): writes on VMs, VM scale sets, sites, container groups, workflows, Automation Accounts

| Legitimate source | What it looks like |
|---|---|
| Terraform / Bicep | Pipeline SP or inside a deployment, identity is set at creation time |
| Portal Identity blade | User, one resource |
| Azure Policy (for example built-in policies that assign a user-assigned identity for Azure Monitor Agent) | Policy managed identity, same identity attached to many hosts |
| Azure Monitor Agent / Defender onboarding | Same as Policy |

**Exclusion strategy for `uai-attached-to-host`:** watchlist the policy-assignment identities and
the specific user-assigned identity they attach. Alert on interactive users attaching an identity
that holds strong roles. Verify in lab that `Properties_d.requestbody` is populated for VM writes.
Without it, the rule cannot see the identity block.

### Automation job start (not done by Fenrir): `MICROSOFT.AUTOMATION/AUTOMATIONACCOUNTS/JOBS/WRITE`

| Legitimate source | What it looks like |
|---|---|
| Schedules | Started by the Automation service on a timetable. Verify in lab which `Caller` appears. |
| Webhooks | External system calls the webhook URL. Verify in lab which `Caller` appears. |
| Portal "Start", `Start-AzAutomationRunbook` | User, portal or PowerShell `appid` |

The abuse pattern is a runbook edited (`RUNBOOKS/DRAFT/WRITE`, `RUNBOOKS/PUBLISH/ACTION` or
`RUNBOOKS/WRITE`) and then started by the same user within an hour.

**Exclusion strategy for `automation-runbook-run`:** do not alert on scheduled or webhook jobs.
Alert on user-started jobs that follow an edit by the same caller, and on user-started jobs on
accounts where that user has no 14-day history.

---

## 3. Sign-in and identity baselines

### User sign-in with the Azure CLI client (A-02, A-04)

Legitimate: `az login --use-device-code` on headless machines, Cloud Shell, admins on jump hosts.
Unusual: a device code sign-in for a user who never used one, from a new IP or country, or ROPC
at all (ROPC cannot satisfy MFA). Many organisations block device code flow with Conditional
Access for everyone outside a small group. If yours does, a successful device code sign-in by
anyone else is itself an alert.

### Managed identity sign-ins (`mi-signin-anomaly`)

Legitimate: each managed identity asks for tokens for a small, stable set of resources (for
example Storage and Key Vault), on a steady cadence, from its host. Unusual: the identity asks for
a **resource it has never asked for** (Fenrir's Run Command path asks for Azure Resource
Manager), or the identity's token is then **used from an IP outside its host's network**
(`mi-control-plane-new-ip`). Expected false positives: newly deployed identities (no baseline yet)
and application releases that add a new dependency. Handle these by requiring 7 or more days of
history for the identity before alerting, and by watchlisting known release windows.
