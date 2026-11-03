# Huggin rule proposals

**Every query in this file is a draft, not yet validated.** Each one must pass a benign replay in
the lab before it is deployed. Field names, status strings and request-body shapes marked
"verify in lab" are the most likely places for a draft to be wrong.

Operation IDs (X-08, P-12, ...) refer to [FENRIR-OPERATIONS.md](FENRIR-OPERATIONS.md). Exclusion
reasoning is in [LEGIT-BASELINE.md](LEGIT-BASELINE.md).

## Overview

| Rule ID | Fenrir trigger | Log source | Severity | MITRE ATT&CK |
|---|---|---|---|---|
| `vm-runcommand-by-user` | `exploit` (X-08), default | `AzureActivity` | Medium, High on spread or failures | T1651 Cloud Administration Command |
| `appservice-publish-creds` | `exploit` (X-10), default | `AzureActivity` (+ `AppServiceAuditLogs`) | Medium | T1552 Unsecured Credentials |
| `logicapp-callback-listed` | `exploit` (X-13), default | `AzureActivity` | Medium | T1552 Unsecured Credentials |
| `aci-exec` | `exploit` (X-14), default | `AzureActivity` | Medium | T1609 Container Administration Command |
| `storage-keys-listed` | `post-exploit --dump-blobs` (P-12) | `AzureActivity` | Medium, High for a managed identity from a new IP | T1552 Unsecured Credentials |
| `acr-admin-creds-listed` *(new)* | `post-exploit --dump-images` (P-13) | `AzureActivity` | Medium, High for a managed identity from a new IP | T1552 Unsecured Credentials |
| `mi-signin-anomaly` | `exploit` (host side of X-08 / X-11) | `AADManagedIdentitySignInLogs` | Medium, High for an ARM or Graph audience | T1078.004 Valid Accounts: Cloud Accounts |
| `mi-control-plane-new-ip` *(new)* | `post-exploit` (P-12, P-13 as the managed identity) | `AzureActivity` | High | T1550.001 Application Access Token |
| `fenrir-chain` | `exploit` then `post-exploit` | `AzureActivity`, `SigninLogs` | Medium, High on identity pivot | T1651, T1552, T1550.001 |
| `graph-directory-recon` *(new)* | `enumerate` (E-01 to E-07), `exploit` (X-06) | `MicrosoftGraphActivityLogs` | Low | T1087.004 Cloud Account Discovery, T1069.003 Cloud Groups |
| `devicecode-azure-mgmt-signin` *(new)* | `login` (A-02 default, A-04 with `--auth-flow ropc`) | `SigninLogs` | Medium | T1078.004 Valid Accounts: Cloud Accounts |
| `rbac-self-assignment` | **not triggered by Fenrir** | `AzureActivity` | High | T1098.003 Additional Cloud Roles |
| `uai-attached-to-host` | **not triggered by Fenrir** | `AzureActivity` | High | T1098 Account Manipulation |
| `automation-runbook-run` | **not triggered by Fenrir** | `AzureActivity` | Medium | T1651 Cloud Administration Command |

MITRE mappings for credential-listing actions (T1552 parent technique) and for identity attachment
(T1098 parent) are judgement calls. There is no exact sub-technique for them.

### Licences and data connectors

| Table | Needs |
|---|---|
| `AzureActivity` | Azure Activity connector (subscription diagnostic setting). No Entra licence. |
| `SigninLogs`, `AADNonInteractiveUserSignInLogs`, `AADManagedIdentitySignInLogs` | Entra ID P1 or P2, Entra ID diagnostic setting. Verify in lab that managed identity sign-ins export on your licence. |
| `MicrosoftGraphActivityLogs` | Entra ID P1 or P2, Entra ID diagnostic setting for this category. Verify in lab. |
| `AppServiceAuditLogs` | App Service diagnostic setting per app. Verify in lab which plan tiers support it. |

Scheduled analytics rules can look back at most 14 days, so every baseline below uses 14 days.

---

## Shared building blocks

### Watchlist `HuginnTrustedAutomation`

Columns: `PrincipalId` (object ID, lower case), `AppId`, `ScopePrefix` (lower-case resource ID
prefix), `Operation` (upper-case `OperationNameValue`), `Owner`, `Reason`, `ExpiresOn`.
One row per approved (identity, scope, operation). No row may exclude a whole client application.

### Saved function `HuginnActivity(Ops:dynamic, Lookback:timespan)`

Normalises `AzureActivity` for the rules below and flags trusted automation and deployment
context. Saved once in the workspace, so each rule stays short.

```kql
// Draft, not yet validated.
// Saved as workspace function HuginnActivity(Ops:dynamic, Lookback:timespan)
let Trusted = _GetWatchlist('HuginnTrustedAutomation')
    | extend PrincipalId = tolower(tostring(PrincipalId)),
             ScopePrefix = tolower(tostring(ScopePrefix)),
             Operation   = toupper(tostring(Operation)),
             Expires     = todatetime(ExpiresOn)
    | where isnull(Expires) or Expires > now()
    | project PrincipalId, ScopePrefix, Operation;
let DeploymentCorr = AzureActivity
    | where TimeGenerated > ago(Lookback + 1h)
    | where OperationNameValue =~ "MICROSOFT.RESOURCES/DEPLOYMENTS/WRITE"
    | distinct CorrelationId;
let Events = AzureActivity
    | where TimeGenerated > ago(Lookback)
    | extend Op = toupper(OperationNameValue)
    | where Op in (Ops)
    | extend CallerOid = tolower(tostring(Claims_d["http://schemas.microsoft.com/identity/claims/objectidentifier"])),
             AppId     = tolower(tostring(Claims_d.appid)),
             MiResId   = tolower(tostring(Claims_d.xms_mirid)),   // verify in lab: present for managed identities
             Rid       = tolower(_ResourceId);
let TrustedHits = Events
    | join kind=inner Trusted on $left.CallerOid == $right.PrincipalId, $left.Op == $right.Operation
    | where Rid startswith ScopePrefix
    | distinct CorrelationId;
Events
| extend IsTrusted    = CorrelationId in (TrustedHits),
         InDeployment = CorrelationId in (DeploymentCorr),
         CallerKind   = case(isnotempty(MiResId), "ManagedIdentity",
                             Caller has "@",      "User",
                             isnotempty(AppId),   "ServicePrincipal",
                                                  "Unknown")
```

Verify in lab: the exact `ActivityStatusValue` strings (`Start` / `Accept` / `Success` / `Failure`
or `Started` / `Accepted` / `Succeeded` / `Failed`). The rules below accept both forms.

---

## `vm-runcommand-by-user`

**Detects:** a caller running commands inside VMs through the control plane, including the
managed Run Command resource and Arc machines. **Fenrir trigger:** `exploit` by default (X-08).
It runs Run Command on every VM in each RG where the caller has a strong role, then once more per
attached user-assigned identity.

```kql
// Draft, not yet validated.
HuginnActivity(dynamic([
    "MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMAND/ACTION",
    "MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMANDS/WRITE",
    "MICROSOFT.COMPUTE/VIRTUALMACHINESCALESETS/VIRTUALMACHINES/RUNCOMMAND/ACTION",
    "MICROSOFT.HYBRIDCOMPUTE/MACHINES/RUNCOMMANDS/WRITE"]), 1h)
| where not(IsTrusted)
| extend Vm = extract(@"^(.*/(virtualmachines|machines)/[^/]+)", 1, Rid)
| summarize FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated),
            Requests  = dcount(CorrelationId),
            VmCount   = dcount(Vm), Vms = make_set(Vm, 50),
            Failures  = dcountif(CorrelationId, ActivityStatusValue in~ ("Failure", "Failed")),
            Ips       = make_set(CallerIpAddress, 10),
            InDeployment = max(toint(InDeployment))
    by Caller, CallerOid, CallerKind, AppId, SubscriptionId
| extend Severity = case(VmCount >= 3 or Failures > 0, "High",
                         CallerKind in ("User", "ManagedIdentity"), "Medium",
                         "Low")
```

| | |
|---|---|
| Log source / licence | `AzureActivity`, no Entra licence |
| False positives | Admins troubleshooting (portal, CLI): single VM, Medium, acceptable to triage. Release pipelines: watchlist by principal + VM scope. Microsoft first-party callers: baseline 30 days, watchlist with expiry. |
| False negatives | Custom Script Extension (`MICROSOFT.COMPUTE/VIRTUALMACHINES/EXTENSIONS/WRITE`), VM Access extension, serial console, AKS `runCommand`. A watchlisted pipeline identity that is itself compromised. What the command did on the host (not in control-plane logs). |
| Severity / MITRE | Medium, High for 3+ VMs or any failures (permission probing). T1651. |

---

## `appservice-publish-creds`

**Detects:** retrieval of App Service deployment (Kudu/FTP) credentials or a publish profile.
**Fenrir trigger:** `exploit` by default (X-10) on every Kudu-capable site with SCM basic auth on.

```kql
// Draft, not yet validated.
HuginnActivity(dynamic([
    "MICROSOFT.WEB/SITES/CONFIG/LIST/ACTION",
    "MICROSOFT.WEB/SITES/SLOTS/CONFIG/LIST/ACTION",
    "MICROSOFT.WEB/SITES/PUBLISHXML/ACTION",
    "MICROSOFT.WEB/SITES/SLOTS/PUBLISHXML/ACTION"]), 1h)
| extend Entity = tolower(tostring(Properties_d.entity))
// verify in lab: does the resource ID keep the /config/publishingcredentials suffix?
| where Op endswith "/PUBLISHXML/ACTION"
     or Rid has "/config/publishingcredentials"
     or Entity has "/config/publishingcredentials"
| where not(IsTrusted)
| extend Site = extract(@"^(.*/sites/[^/]+(/slots/[^/]+)?)", 1, Rid)
| summarize FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated),
            SiteCount = dcount(Site), Sites = make_set(Site, 50),
            Ips = make_set(CallerIpAddress, 10),
            InDeployment = max(toint(InDeployment))
    by Caller, CallerOid, CallerKind, AppId, SubscriptionId
| extend Severity = iff(SiteCount >= 2 and InDeployment == 0, "High", "Medium")
```

Optional enrichment, if App Service diagnostics are on (columns to verify in lab):

```kql
// Draft, not yet validated. Basic-auth Kudu logins on the same sites in the next 2 hours.
AppServiceAuditLogs
| where TimeGenerated > ago(2h)
| where Protocol in~ ("Kudu", "FTP", "FTPS", "WebDeploy")
| summarize KuduLogins = count(), KuduIps = make_set(UserAddress, 10) by Site = tolower(_ResourceId)
```

| | |
|---|---|
| Log source / licence | `AzureActivity`. `AppServiceAuditLogs` needs per-app diagnostic settings. |
| False positives | Portal Configuration blade (app settings / connection strings) if the suffix is not visible: fall back to a "new (caller, site) pair in 14 days" filter. Terraform refresh of `site_credential`: watchlist. Deployment tasks in Azure DevOps / GitHub Actions: watchlist. Visual Studio publish: Medium, triage. |
| False negatives | Credentials read from a publish profile already stored elsewhere (a CI secret). Kudu access with an Entra token instead of basic auth. If the suffix is not logged, the suffix filter drops real events, so test this first. |
| Severity / MITRE | Medium, High for 2+ sites outside a deployment. T1552. |

---

## `logicapp-callback-listed`

**Detects:** a caller retrieving a Logic App trigger callback URL (a SAS-signed URL that lets
anyone run the workflow) for a workflow they have not touched in 14 days.
**Fenrir trigger:** `exploit` by default (X-13).

```kql
// Draft, not yet validated.
let Lookback = 1h;
let Baseline = 14d;
let Op = "MICROSOFT.LOGIC/WORKFLOWS/TRIGGERS/LISTCALLBACKURL/ACTION";
let Known = AzureActivity
    | where TimeGenerated between (ago(Baseline) .. ago(Lookback))
    | where OperationNameValue =~ Op
    | extend CallerOid = tolower(tostring(Claims_d["http://schemas.microsoft.com/identity/claims/objectidentifier"])),
             Workflow  = extract(@"^(.*/workflows/[^/]+)", 1, tolower(_ResourceId))
    | distinct CallerOid, Workflow;
HuginnActivity(dynamic(["MICROSOFT.LOGIC/WORKFLOWS/TRIGGERS/LISTCALLBACKURL/ACTION"]), Lookback)
| where not(IsTrusted)
| extend Workflow = extract(@"^(.*/workflows/[^/]+)", 1, Rid)   // verify in lab: trigger or workflow ID
| join kind=leftanti Known on CallerOid, Workflow
| summarize FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated),
            WorkflowCount = dcount(Workflow), Workflows = make_set(Workflow, 50),
            Ips = make_set(CallerIpAddress, 10),
            InDeployment = max(toint(InDeployment))
    by Caller, CallerOid, CallerKind, AppId, SubscriptionId
| extend Severity = case(InDeployment == 1, "Low", WorkflowCount >= 2, "High", "Medium")
```

| | |
|---|---|
| False positives | A developer's first visit to a workflow in the designer (Medium, one workflow). Terraform refresh of `callback_url`: watchlist. ARM/Bicep `listCallbackUrl()`: downgraded to Low via deployment context. |
| False negatives | Callback URLs already copied into documentation, pipelines or Key Vault. Standard (single-tenant) Logic Apps, which use `Microsoft.Web/sites` hostruntime paths: verify in lab and add the operation name. A caller who already listed the URL in the last 14 days. |
| Severity / MITRE | Medium, High for 2+ workflows, Low inside a deployment. T1552. |

---

## `aci-exec`

**Detects:** an interactive exec session opened into a container instance.
**Fenrir trigger:** `exploit` by default (X-14), on the first container of each group.

```kql
// Draft, not yet validated.
HuginnActivity(dynamic(["MICROSOFT.CONTAINERINSTANCE/CONTAINERGROUPS/CONTAINERS/EXEC/ACTION"]), 1h)
| where not(IsTrusted)
| extend ContainerGroup = extract(@"^(.*/containergroups/[^/]+)", 1, Rid)
| summarize FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated),
            GroupCount = dcount(ContainerGroup), Groups = make_set(ContainerGroup, 50),
            Failures = dcountif(CorrelationId, ActivityStatusValue in~ ("Failure", "Failed")),
            Ips = make_set(CallerIpAddress, 10)
    by Caller, CallerOid, CallerKind, AppId, SubscriptionId
| extend Severity = iff(GroupCount >= 2 or Failures > 0, "High", "Medium")
```

| | |
|---|---|
| False positives | Portal "Connect" and `az container exec` for debugging: low volume, triage. Pipelines that exec: watchlist. |
| False negatives | Anything typed inside the session. AKS `kubectl exec` (different log source). Container Apps console (`Microsoft.App`): verify in lab and add its operation name. |
| Severity / MITRE | Medium, High for 2+ groups or failures. T1609. |

---

## `storage-keys-listed`

**Detects:** storage account key retrieval in three suspicious shapes: (A) by a managed identity
from an IP it has never used, (B) by one caller across 3 or more accounts in an hour, (C) a new
(caller, account) pair outside deployments and trusted automation.
**Fenrir trigger:** `post-exploit --dump-blobs` (P-12), also with `--dry-run`. Fires branch A
(the caller is the captured identity, acting from the operator's IP), and often B.

```kql
// Draft, not yet validated.
let Lookback = 1h;
let Baseline = 14d;
let Op = "MICROSOFT.STORAGE/STORAGEACCOUNTS/LISTKEYS/ACTION";
let OidClaim = "http://schemas.microsoft.com/identity/claims/objectidentifier";
let PairHistory = AzureActivity
    | where TimeGenerated between (ago(Baseline) .. ago(Lookback))
    | where OperationNameValue =~ Op
    | extend CallerOid = tolower(tostring(Claims_d[OidClaim])),
             Account   = extract(@"^(.*/storageaccounts/[^/]+)", 1, tolower(_ResourceId))
    | distinct CallerOid, Account;
let MiIpHistory = AzureActivity
    | where TimeGenerated between (ago(Baseline) .. ago(Lookback))
    | where isnotempty(tostring(Claims_d.xms_mirid))
    | extend CallerOid = tolower(tostring(Claims_d[OidClaim]))
    | distinct CallerOid, CallerIpAddress;
let Recent = HuginnActivity(dynamic(["MICROSOFT.STORAGE/STORAGEACCOUNTS/LISTKEYS/ACTION"]), Lookback)
    | extend Account = extract(@"^(.*/storageaccounts/[^/]+)", 1, Rid);
let BranchA = Recent
    | where CallerKind == "ManagedIdentity"
    | join kind=leftanti MiIpHistory on CallerOid, CallerIpAddress
    | extend Branch = "A: managed identity from new IP";
let BranchB = Recent
    | where not(IsTrusted)
    | summarize Accounts = dcount(Account) by CallerOid
    | where Accounts >= 3
    | join kind=inner Recent on CallerOid
    | extend Branch = "B: 3+ accounts in 1h";
let BranchC = Recent
    | where not(IsTrusted) and not(InDeployment)
    | join kind=leftanti PairHistory on CallerOid, Account
    | extend Branch = "C: new caller-account pair";
union BranchA, BranchB, BranchC
| summarize Branches = make_set(Branch),
            AccountCount = dcount(Account), Accounts = make_set(Account, 50),
            Ips = make_set(CallerIpAddress, 10),
            FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated)
    by Caller, CallerOid, CallerKind, AppId, SubscriptionId
| extend Severity = iff(set_has_element(Branches, "A: managed identity from new IP"), "High", "Medium")
```

| | |
|---|---|
| False positives | Terraform refresh (branches B, C): watchlist the pipeline principal per scope. Portal users opening storage blades (C): one account at a time, Medium. First-party services (C): 30-day baseline then watchlist. Branch A: a managed identity whose workload changes outbound IP (new NAT gateway, scale-out). Mitigate by comparing against an Azure service-tag IP watchlist instead of exact IPs if this is noisy. |
| False negatives | Keys already stored elsewhere (app settings, Key Vault, pipeline secrets). Data access with OAuth roles or SAS (no `listKeys`). `listAccountSas` / `listServiceSas` (add these operation names after a lab check). Fenrir `post-exploit` without `--dump-blobs`. |
| Severity / MITRE | Medium, High on branch A. T1552, then T1530 Data from Cloud Storage for the follow-on download. |

---

## `acr-admin-creds-listed` *(new)*

**Detects:** retrieval of a container registry's admin username and password.
**Fenrir trigger:** `post-exploit --dump-images` (P-13), also with `--dry-run`.

```kql
// Draft, not yet validated.
let Lookback = 1h;
let Baseline = 14d;
let OidClaim = "http://schemas.microsoft.com/identity/claims/objectidentifier";
let PairHistory = AzureActivity
    | where TimeGenerated between (ago(Baseline) .. ago(Lookback))
    | where OperationNameValue =~ "MICROSOFT.CONTAINERREGISTRY/REGISTRIES/LISTCREDENTIALS/ACTION"
    | extend CallerOid = tolower(tostring(Claims_d[OidClaim])),
             Registry  = extract(@"^(.*/registries/[^/]+)", 1, tolower(_ResourceId))
    | distinct CallerOid, Registry;
HuginnActivity(dynamic(["MICROSOFT.CONTAINERREGISTRY/REGISTRIES/LISTCREDENTIALS/ACTION"]), Lookback)
| where not(IsTrusted)
| extend Registry = extract(@"^(.*/registries/[^/]+)", 1, Rid)
| join kind=leftanti PairHistory on CallerOid, Registry
| summarize FirstSeen = min(TimeGenerated), Registries = make_set(Registry, 50),
            Ips = make_set(CallerIpAddress, 10), InDeployment = max(toint(InDeployment))
    by Caller, CallerOid, CallerKind, AppId, SubscriptionId
| extend Severity = case(CallerKind == "ManagedIdentity", "High", InDeployment == 1, "Low", "Medium")
```

| | |
|---|---|
| False positives | Portal Access keys blade, `az acr credential show`, Terraform refresh with `admin_enabled = true`: watchlist or new-pair filter. |
| False negatives | Admin credentials already saved elsewhere. Pulls with Entra tokens or scoped tokens (no `listCredentials`). Registries with the admin user disabled: the call fails and shows as a failure, which the rule still sees. |
| Severity / MITRE | Medium, High for a managed identity caller. T1552. |

---

## `mi-signin-anomaly`

**Detects:** a managed identity obtaining a token for a resource it has never requested in 14
days, when the identity has at least 7 days of history.
**Fenrir trigger:** `exploit` (host side of X-08 and X-11). Fenrir asks for an Azure Resource
Manager token, which many workload identities never request.

```kql
// Draft, not yet validated.
let Lookback = 1h;
let Baseline = 14d;
let MinHistory = 7d;
let Known = AADManagedIdentitySignInLogs
    | where TimeGenerated between (ago(Baseline) .. ago(Lookback))
    | where ResultType == "0"          // verify in lab: column type and value
    | summarize FirstEver = min(TimeGenerated), KnownResources = make_set(ResourceIdentity, 200)
        by ServicePrincipalId;
AADManagedIdentitySignInLogs
| where TimeGenerated > ago(Lookback)
| where ResultType == "0"
| summarize FirstSeen = min(TimeGenerated), SignIns = count(), Ips = make_set(IPAddress, 10)
    by ServicePrincipalId, ServicePrincipalName, ResourceIdentity, ResourceDisplayName
| join kind=inner Known on ServicePrincipalId
| where FirstEver < ago(MinHistory)
| where not(set_has_element(KnownResources, ResourceIdentity))
| extend Severity = iff(ResourceIdentity in ("797f4846-ba00-4fd7-ba43-dac1f8f63013",   // Azure Resource Manager
                                             "00000003-0000-0000-c000-000000000000"),  // Microsoft Graph
                        "High", "Medium")
```

| | |
|---|---|
| False positives | Application releases that add a dependency (new resource). New identities are skipped by `MinHistory`. Watchlist planned release windows if needed. |
| False negatives | Identities that already use ARM routinely (common for automation). **Token caching**: if the host already had a valid ARM token cached, no new sign-in row may appear. Verify in lab. The sign-in shows the token was issued, not who used it. Pair with `mi-control-plane-new-ip`. |
| Severity / MITRE | Medium, High for ARM or Graph. T1078.004 (the host-side token theft itself is T1552.005, which needs host telemetry). |

---

## `mi-control-plane-new-ip` *(new)*

**Detects:** a managed identity performing a logged control-plane action from an IP address it
has never used in 14 days. A managed identity token should only be used from its host.
**Fenrir trigger:** `post-exploit` with `--dump-blobs` or `--dump-images` (P-12, P-13), which
runs as the identity from the operator's IP.

```kql
// Draft, not yet validated.
let Lookback = 1h;
let Baseline = 14d;
let OidClaim = "http://schemas.microsoft.com/identity/claims/objectidentifier";
let Mi = AzureActivity
    | where TimeGenerated > ago(Baseline)
    | extend MiResId = tolower(tostring(Claims_d.xms_mirid))   // verify in lab
    | where isnotempty(MiResId)
    | extend CallerOid = tolower(tostring(Claims_d[OidClaim]));
let Known = Mi
    | where TimeGenerated < ago(Lookback)
    | distinct CallerOid, CallerIpAddress;
let KnownIds = Known | distinct CallerOid;
Mi
| where TimeGenerated > ago(Lookback)
| where CallerOid in (KnownIds)            // identity must have history
| join kind=leftanti Known on CallerOid, CallerIpAddress
| summarize FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated),
            Ops = make_set(OperationNameValue, 20), Resources = make_set(_ResourceId, 20)
    by Caller, CallerOid, MiResId, CallerIpAddress, SubscriptionId
```

| | |
|---|---|
| False positives | Workloads whose outbound IP changes (NAT gateway changes, scale-out to new instances with public IPs). Consider comparing against a watchlist of Azure service-tag ranges: an identity acting from **outside** Azure ranges is the strongest form. Arc-enabled servers use the on-premises egress IP. |
| False negatives | **Reads are not logged**, so an identity that only enumerates (Fenrir X-19 to X-21, P-01 to P-11) is invisible. An attacker operating from another Azure VM may land in Azure ranges. New identities (no history) are skipped. |
| Severity / MITRE | High. T1550.001 Use Alternate Authentication Material: Application Access Token. |

---

## `fenrir-chain`

**Detects:** the multi-step pattern behind Fenrir rather than Fenrir itself: one non-managed
caller performing two or more kinds of "execute on a host or extract a secret" actions, or
touching three or more targets, within 4 hours. The strongest signal: **a managed identity then
acting from the same IP address the user just used**, which is what happens when a token taken
from a host is replayed from the operator's machine.
**Fenrir trigger:** `exploit` (X-08, X-10, X-13, X-14) followed by `post-exploit` with a dump flag
(P-12, P-13).

```kql
// Draft, not yet validated.
let Window = 4h;
let StageMap = datatable(Op:string, Stage:string) [
    "MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMAND/ACTION",                  "HostExecution",
    "MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMANDS/WRITE",                  "HostExecution",
    "MICROSOFT.WEB/SITES/CONFIG/LIST/ACTION",                               "AppServiceCreds",
    "MICROSOFT.WEB/SITES/PUBLISHXML/ACTION",                                "AppServiceCreds",
    "MICROSOFT.LOGIC/WORKFLOWS/TRIGGERS/LISTCALLBACKURL/ACTION",            "LogicAppCallback",
    "MICROSOFT.CONTAINERINSTANCE/CONTAINERGROUPS/CONTAINERS/EXEC/ACTION",   "ContainerExec",
    "MICROSOFT.STORAGE/STORAGEACCOUNTS/LISTKEYS/ACTION",                    "SecretListing",
    "MICROSOFT.CONTAINERREGISTRY/REGISTRIES/LISTCREDENTIALS/ACTION",        "SecretListing"
];
let UserSide = HuginnActivity(toscalar(StageMap | summarize make_list(Op)), Window)
    | where CallerKind != "ManagedIdentity" and not(IsTrusted)
    | lookup kind=inner StageMap on Op
    | summarize Stages = make_set(Stage), StageCount = dcount(Stage),
                Targets = dcount(Rid),
                FirstStage = min(TimeGenerated), LastStage = max(TimeGenerated),
                UserIps = make_set(CallerIpAddress, 20)
        by Caller, CallerOid;
let MiSide = AzureActivity
    | where TimeGenerated > ago(Window)
    | extend MiResId = tolower(tostring(Claims_d.xms_mirid))
    | where isnotempty(MiResId)
    | project MiTime = TimeGenerated, MiResId, MiOp = OperationNameValue, MiIp = CallerIpAddress;
let Pivot = UserSide
    | mv-expand UserIp = UserIps to typeof(string)
    | join kind=inner MiSide on $left.UserIp == $right.MiIp
    | where MiTime between (FirstStage .. (LastStage + 2h))
    | summarize MiIdentities = make_set(MiResId, 10), MiOps = make_set(MiOp, 10) by CallerOid;
let DeviceCode = SigninLogs
    | where TimeGenerated > ago(1d)
    | where AuthenticationProtocol =~ "deviceCode" and ResultType == "0"
    | summarize DeviceCodeSignIns = count() by CallerOid = tolower(UserId);
UserSide
| join kind=leftouter Pivot on CallerOid
| join kind=leftouter DeviceCode on CallerOid
| extend MiPivot = coalesce(array_length(MiIdentities), 0) > 0,
         DeviceCodeSignIns = coalesce(DeviceCodeSignIns, 0)
| where StageCount >= 2 or Targets >= 3 or MiPivot
| extend Severity = case(MiPivot, "High",
                         StageCount >= 2 and DeviceCodeSignIns > 0, "High",
                         "Medium")
```

| | |
|---|---|
| Log source / licence | `AzureActivity` (free), `SigninLogs` (P1/P2) for the device code boost |
| False positives | Platform engineers doing several kinds of admin work in one session (Medium). **Jump-box admins**: an admin on an Azure VM whose own managed identity acts from the same public IP will match the pivot branch. Watchlist such jump hosts' identities. Shared corporate NAT, if workloads also egress through it (Arc). |
| False negatives | Chains split across several user accounts or spread over more than 4 hours. Operators who stop after `enumerate` (nothing logged) or after `exploit` without dump flags (pivot branch cannot fire). An operator using a different IP for each phase. |
| Severity / MITRE | Medium, High on identity pivot or device code + 2 stages. T1651, T1552, T1550.001. |

---

## `graph-directory-recon` *(new)*

**Detects:** one principal reading four or more privileged directory views within an hour (role
assignments, PIM eligibility, all service principals, owned objects, group membership, domains,
managed devices). **Fenrir trigger:** `enumerate` (E-01 to E-07), `exploit` (X-06).

```kql
// Draft, not yet validated.
MicrosoftGraphActivityLogs
| where TimeGenerated > ago(1h)
| where RequestMethod == "GET"
| extend Path = replace_regex(tolower(tostring(parse_url(RequestUri).Path)), @"^/(v1\.0|beta)", "")
| extend View = case(
      Path startswith "/rolemanagement/directory/roleassignments",                  "DirectoryRoleAssignments",
      Path startswith "/rolemanagement/directory/roleeligibilityscheduleinstances", "PimEligibility",
      Path startswith "/serviceprincipals",                                         "AllServicePrincipals",
      Path has "/ownedobjects",                                                     "OwnedObjects",
      Path has "/transitivememberof",                                               "TransitiveGroups",
      Path startswith "/domains",                                                   "Domains",
      Path has "/manageddevices",                                                   "ManagedDevices",
      "")
| where isnotempty(View)
| summarize Views = make_set(View), ViewCount = dcount(View), Requests = count(),
            Apps = make_set(AppId, 5), Ips = make_set(IPAddress, 10),
            FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated)
    by UserId, ServicePrincipalId
| where ViewCount >= 4
```

| | |
|---|---|
| False positives | Entra admin center and identity governance tools, Graph Explorer, security scanners and CSPM tools. Baseline the admin portal client IDs and scanner principals for 14 days, then watchlist them. |
| False negatives | Slow enumeration spread over hours. Enumeration through other endpoints (`/directoryRoles`, `$batch` requests: verify in lab how `$batch` appears). No coverage at all if the Graph activity log category is not exported. |
| Severity / MITRE | Low (discovery). T1087.004, T1069.003. |

---

## `devicecode-azure-mgmt-signin` *(new)*

**Detects:** a successful device code or ROPC sign-in by a user who has not used that flow in the
last 14 days. **Fenrir trigger:** `login` (A-02 by default, A-04 with `--auth-flow ropc`).

```kql
// Draft, not yet validated.
let Lookback = 1h;
let Baseline = 14d;
let Flows = dynamic(["deviceCode", "ropc"]);   // verify in lab: exact AuthenticationProtocol strings
let Known = SigninLogs
    | where TimeGenerated between (ago(Baseline) .. ago(Lookback))
    | where AuthenticationProtocol in~ (Flows) and ResultType == "0"
    | distinct UserId, AuthenticationProtocol;
SigninLogs
| where TimeGenerated > ago(Lookback)
| where AuthenticationProtocol in~ (Flows) and ResultType == "0"
| join kind=leftanti Known on UserId, AuthenticationProtocol
| project TimeGenerated, UserPrincipalName, UserId, AppId, AppDisplayName, ResourceDisplayName,
          AuthenticationProtocol, IPAddress, Location, UserAgent, ConditionalAccessStatus
| extend Severity = iff(AuthenticationProtocol =~ "ropc", "High", "Medium")
```

| | |
|---|---|
| False positives | Admins using `az login --use-device-code` on a new headless machine. Device enrolment flows. If Conditional Access already blocks device code for most users, the residual volume is small. |
| False negatives | Users who already use device code regularly. Interactive browser flow (`--auth-flow interactive`). Sign-ins reusing a cached refresh token (no new interactive sign-in). |
| Severity / MITRE | Medium, High for ROPC. T1078.004. |

---

## `rbac-self-assignment` (not triggered by Fenrir)

**Detects:** a principal creating a role assignment for itself, outside PIM.
**Fenrir:** never does this. `core/enumerate/verdict.py` reports `ROLE_ASSIGNMENT_WRITE_ROLES` as
an opportunity. Lab replay: `az role assignment create --assignee <your own object ID>`.

```kql
// Draft, not yet validated.
AzureActivity
| where TimeGenerated > ago(1h)
| where OperationNameValue =~ "MICROSOFT.AUTHORIZATION/ROLEASSIGNMENTS/WRITE"
| extend Body = todynamic(tostring(Properties_d.requestbody))   // verify in lab: on which status row, and key casing
| extend TargetPrincipal = tolower(coalesce(tostring(Body.Properties.PrincipalId), tostring(Body.properties.principalId))),
         RoleDefinitionId = coalesce(tostring(Body.Properties.RoleDefinitionId), tostring(Body.properties.roleDefinitionId)),
         CallerOid = tolower(tostring(Claims_d["http://schemas.microsoft.com/identity/claims/objectidentifier"])),
         AppId     = tolower(tostring(Claims_d.appid))
| where isnotempty(TargetPrincipal) and TargetPrincipal == CallerOid
| where AppId != "01fc33a7-78ba-4d2f-a4b7-768e336e890e"          // MS-PIM activations
| extend RoleGuid = tolower(extract(@"([0-9a-fA-F-]{36})$", 1, RoleDefinitionId))
| summarize arg_min(TimeGenerated, *) by CorrelationId
| project TimeGenerated, Caller, CallerOid, AppId, CallerIpAddress, Scope = _ResourceId,
          RoleGuid, ActivityStatusValue, CorrelationId
| extend Severity = iff(RoleGuid in ("8e3af657-a8ff-443c-a75c-2fe8c4bcb635",   // Owner
                                     "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9",   // User Access Administrator
                                     "b24988ac-6180-42a0-ab88-20f7382dd24c",   // Contributor
                                     "f58310d9-a9f6-439a-9e8d-f62e7b41a168"),  // RBAC Administrator
                        "High", "Medium")
```

| | |
|---|---|
| False positives | PIM activations (excluded by `appid`). Owners who intentionally add themselves a narrower role: rare, triage. |
| False negatives | Granting a role to a **group** the caller belongs to, or to a second account or service principal the caller controls. Assignments where `requestbody` is not logged. Add a companion rule for "user grants a privileged role to a principal created in the last 24 hours". |
| Severity / MITRE | High for privileged roles. T1098.003. |

---

## `uai-attached-to-host` (not triggered by Fenrir)

**Detects:** a user-assigned identity newly attached to a compute host (VM, scale set, site,
container group, workflow, Automation Account), outside trusted automation.
**Fenrir:** never does this. `core/enumerate/verdict.py` reports `UAI_ASSIGN_ROLES` as an
opportunity. Lab replay: `az vm identity assign --identities <uai>` on a lab VM.

```kql
// Draft, not yet validated.
let Lookback = 1h;
let Baseline = 14d;
let HostWrites = dynamic([
    "MICROSOFT.COMPUTE/VIRTUALMACHINES/WRITE",
    "MICROSOFT.COMPUTE/VIRTUALMACHINESCALESETS/WRITE",
    "MICROSOFT.WEB/SITES/WRITE",
    "MICROSOFT.WEB/SITES/SLOTS/WRITE",
    "MICROSOFT.CONTAINERINSTANCE/CONTAINERGROUPS/WRITE",
    "MICROSOFT.LOGIC/WORKFLOWS/WRITE",
    "MICROSOFT.AUTOMATION/AUTOMATIONACCOUNTS/WRITE"]);
let UaiPattern = @'(/subscriptions/[^"]+/providers/microsoft\.managedidentity/userassignedidentities/[^"]+)';
let Pairs = (T:(TimeGenerated:datetime, _ResourceId:string, Properties_d:dynamic)) {
    T
    | extend Body = tolower(tostring(Properties_d.requestbody))   // verify in lab: populated for these writes
    | where Body has "userassignedidentities"
    | extend Uai = extract_all(UaiPattern, Body), HostId = tolower(_ResourceId)
    | mv-expand Uai to typeof(string)
};
let Known = AzureActivity
    | where TimeGenerated between (ago(Baseline) .. ago(Lookback))
    | where toupper(OperationNameValue) in (HostWrites)
    | project TimeGenerated, _ResourceId, Properties_d
    | invoke Pairs()
    | distinct HostId, Uai;
HuginnActivity(HostWrites, Lookback)
| where not(IsTrusted)
| extend Body = tolower(tostring(Properties_d.requestbody))
| where Body has "userassignedidentities"
| extend Uai = extract_all(UaiPattern, Body), HostId = Rid
| mv-expand Uai to typeof(string)
| join kind=leftanti Known on HostId, Uai
| summarize FirstSeen = min(TimeGenerated), NewIdentities = make_set(Uai, 20),
            InDeployment = max(toint(InDeployment))
    by Caller, CallerOid, CallerKind, AppId, HostId, SubscriptionId
| extend Severity = iff(CallerKind == "User" and InDeployment == 0, "High", "Medium")
```

| | |
|---|---|
| False positives | Azure Policy assigning a monitoring identity to many hosts: watchlist the policy identity. Terraform / Bicep creating new hosts: new hosts have no history, so they match; downgrade via deployment context or watchlist the pipeline. |
| False negatives | Writes where `requestbody` is missing or truncated. System-assigned identity enabled on a host (no UAI ID in the body): add a branch for `"type":"systemassigned"` changes. Identities attached at creation by a trusted but compromised pipeline. |
| Severity / MITRE | High for interactive users. T1098 (judgement call). |

---

## `automation-runbook-run` (not triggered by Fenrir)

**Detects:** a runbook job started by a caller who edited a runbook in the same account in the
last 2 hours, or who has never started a job in that account in 14 days.
**Fenrir:** only **reads** runbooks, runbook source, variables and credentials (X-15 to X-18).
It never starts a job, so this rule will not fire on Fenrir. Those reads are a blind spot.
Lab replay: edit a lab runbook, publish it, start it from the portal.

```kql
// Draft, not yet validated.
let Lookback = 1h;
let Baseline = 14d;
let OidClaim = "http://schemas.microsoft.com/identity/claims/objectidentifier";
let AccountOf = (id:string) { extract(@"^(.*/automationaccounts/[^/]+)", 1, tolower(id)) };
let Edits = HuginnActivity(dynamic([
        "MICROSOFT.AUTOMATION/AUTOMATIONACCOUNTS/RUNBOOKS/DRAFT/WRITE",
        "MICROSOFT.AUTOMATION/AUTOMATIONACCOUNTS/RUNBOOKS/PUBLISH/ACTION",
        "MICROSOFT.AUTOMATION/AUTOMATIONACCOUNTS/RUNBOOKS/WRITE"]), Lookback + 2h)
    | extend Account = AccountOf(Rid)
    | summarize LastEdit = max(TimeGenerated) by CallerOid, Account;
let JobHistory = AzureActivity
    | where TimeGenerated between (ago(Baseline) .. ago(Lookback))
    | where OperationNameValue =~ "MICROSOFT.AUTOMATION/AUTOMATIONACCOUNTS/JOBS/WRITE"
    | extend CallerOid = tolower(tostring(Claims_d[OidClaim])), Account = AccountOf(_ResourceId)
    | distinct CallerOid, Account
    | extend SeenBefore = true;
HuginnActivity(dynamic(["MICROSOFT.AUTOMATION/AUTOMATIONACCOUNTS/JOBS/WRITE"]), Lookback)
| where not(IsTrusted)
| extend Account = AccountOf(Rid)
| join kind=leftouter Edits on CallerOid, Account
| join kind=leftouter JobHistory on CallerOid, Account
| extend EditThenRun  = isnotnull(LastEdit) and LastEdit <= TimeGenerated,
         NewForCaller = isnull(SeenBefore)
| where EditThenRun or NewForCaller
| summarize FirstSeen = min(TimeGenerated), Jobs = dcount(CorrelationId),
            EditThenRun = max(toint(EditThenRun))
    by Caller, CallerOid, CallerKind, AppId, Account, SubscriptionId
| extend Severity = iff(EditThenRun == 1, "High", "Medium")
```

| | |
|---|---|
| False positives | Runbook developers testing their own changes (edit then run): High is noisy for them; watchlist the automation team per account after the first week. Schedule and webhook starts: confirm in lab which `Caller` they show, then exclude that caller. |
| False negatives | Reading runbook source, variables and credentials (Fenrir's actual behaviour): no log. Webhook URLs used by an outsider (the job start comes from the service, not the attacker). Hybrid Runbook Worker activity on hosts. |
| Severity / MITRE | Medium, High for edit then run. T1651. |
