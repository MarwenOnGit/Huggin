# Cost

**These are estimates from public pricing, written on 2026-11-03 before anything was deployed.**
Check Azure Cost Management one week after the first apply and replace them with real numbers.

## Always on (expected under 1 USD per month)

| Resource | Tier | Expected monthly cost | Why |
|---|---|---|---|
| Log Analytics workspace `law-huginn` | PerGB2018, 30-day retention, 0.5 GB/day cap | ~0 | `AzureActivity` ingestion is free in Log Analytics and in Sentinel. 31 days of retention are free. Other activity log categories are tiny. |
| Microsoft Sentinel on the workspace | Pay as you go | ~0 | Billed per GB of billable data analysed, and free data sources (Azure Activity) are not billed. New workspaces also get a 31-day free trial. |
| Analytics rules, watchlist, saved function | | 0 | No charge for the objects themselves |
| State storage account | Standard LRS | < 0.10 | A few KB of state, with versions |
| Logic App `logic-huginn-lab` | Consumption | 0 | Billed per action run. The HTTP trigger never runs. |
| VNet, subnet and NSG for the per-run VM | | 0 | No public IP, no gateway |
| Lab storage account | Standard LRS | < 0.05 | Empty |
| User-assigned identity | | 0 | |
| App registrations | | 0 | |

**Worst case** if something floods the workspace: the 0.5 GB/day cap stops billable ingestion.
At roughly 2 to 6 USD per GB (Log Analytics plus Sentinel, after the trial), that is a ceiling of
about 1 to 3 USD per day. Huginn has no source that should come close.

## Per replay run (opt-in, created and deleted in the same run)

| Resource | Tier | Rough cost while it exists | Billing unit |
|---|---|---|---|
| Linux VM (X-08), created and deleted by the run itself | `Standard_B2ats_v2` (2 vCPU, 1 GB), Standard LRS OS disk deleted with the VM | about 1 US cent per hour; a run keeps it for about 5 minutes | per minute (compute), prorated (disk) |
| App Service (X-10) | F1 Free | 0 | |
| Container group (X-14) | 0.5 vCPU, 0.5 GB | about 2 US cents per hour | per second |
| Container registry (P-13) | Basic | about 0.17 USD per day | **per day**: one run on a day costs the full day |
| Fresh storage account per run (P-12) | Standard LRS, empty | ~0 | |
| Fresh Logic App per run (X-13) | Consumption, never triggered | 0 | |

Core rules 1 to 3 (the demo set) use only the always-on resources and the free per-run storage
account and Logic App. A nightly run of rules 1 to 3 costs about nothing. Rules 4 to 7 add the
opt-in resources above. With ACR, one nightly run costs about 0.20 USD, or about 6 USD per month,
so run them on demand rather than nightly.

## Purple-team environment (`infra/purple`, one manual run)

Estimates from public pricing, not yet measured. Created for one run and destroyed the same day.

| Resource | Tier | Rough cost | Billing unit |
|---|---|---|---|
| Linux VM with the Azure Monitor Agent | `Standard_B2ats_v2`, Standard LRS disk | about 1 US cent per hour | per minute |
| Container group | 0.5 vCPU, 0.5 GB | about 2 US cents per hour | per second |
| Container registry | Basic | about 0.17 USD per day | per day |
| Web app | F1 Free | 0 | |
| Logic App, Automation Account, Key Vault, storage | Consumption / Basic / Standard / LRS | ~0 (a handful of operations) | per operation |
| Diagnostic and Syslog ingestion | Log Analytics | a few cents per run (tens of MB) | per GB |
| Defender for Resource Manager (opt-in) | subscription-wide | see its pricing page; free during its trial | per subscription |
| Entra ID P2 (opt-in) | trial | free for the trial; Graph activity logs are billed per GB ingested | |

A 4-hour run: well under 1 USD. Keeping it up 7 days for the identity baselines: about 2 to 3
USD (mostly the VM and the registry). Raise the workspace cap only for the run window.

## Teardown

```bash
make destroy          # destroys infra/lab, then infra/sentinel (asks before each)
```

`make destroy` keeps `infra/bootstrap`: the state account, the empty resource groups and the two
app registrations cost nothing. To remove everything, remove `prevent_destroy` from the state
account and container, then run `terraform -chdir=infra/bootstrap destroy`.

## Not Huginn's cost

Other resource groups in the subscription hold VMs that are not Huginn's. A deallocated VM costs
nothing for compute, but its disks are still billed, and its vCPUs still count against the
regional quota.
