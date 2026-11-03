# ADR 0004: Accepted tflint and checkov findings

Date: 2026-11-03. Status: accepted.

`make lint` runs `terraform fmt`, `terraform validate`, tflint (terraform recommended preset and
the azurerm ruleset 0.33.0) and checkov 3.4.3. Every accepted finding is suppressed **inline, next
to the resource, with its reason**, and summarised here. checkov was also run on `infra/lab` with
every opt-in flag set to true, because resources with `count = 0` are not scanned otherwise.

Result on 2026-11-03: see the latest `make lint` output; at the time of writing tflint reported 0
issues, checkov 0 failed (with default flags and with every opt-in flag on), and `terraform
validate` had no deprecation warnings.

## Fixed instead of accepted

| Finding | Fix |
|---|---|
| tflint `azurerm_resources_missing_prevent_destroy` on the state account and container | `prevent_destroy = true` |
| CKV_AZURE_59 on the lab storage account | `public_network_access = "Disabled"` (`listKeys` is a control-plane action). checkov 3.4.3 only knows the deprecated `public_network_access_enabled`, so the check is then skipped inline as a false positive. |
| CKV2_AZURE_38 on the lab storage account | Blob and container soft delete, 7 days |
| CKV_AZURE_63, 65, 66 on the lab web app | File-system HTTP logs, detailed errors and failed request tracing (free) |

## Accepted, with reasons

| Group | Checks | Reason |
|---|---|---|
| Student budget | CKV_AZURE_206 (LRS), CKV2_AZURE_33 (private endpoints), CKV2_AZURE_1 (customer-managed keys), CKV2_AZURE_21 (blob read logging) | Each adds a monthly or per-hour cost. The state account compensates with Entra-only auth, versioning, soft delete and `prevent_destroy`. |
| State account reachability | CKV_AZURE_59 on the state account | GitHub-hosted runners need the public endpoint. Shared keys are disabled. |
| Not applicable | CKV_AZURE_33 (queue logging) | No queues are used. |
| False positive | CKV_AZURE_43 (storage naming) on the lab account | The name is interpolated; checkov cannot evaluate it. It is valid. |
| The attack surface itself | CKV_AZURE_137 (ACR admin user), CKV_AZURE_50 (VM extensions) | The ACR admin user is what P-13 lists. Run Command (X-08) needs the VM agent. Both resources are opt-in, empty and deleted after each run. |
| Free / Basic tier limits | CKV_AZURE_211, 212, 225, 214 (App Service plan and Always On); CKV_AZURE_139, 163 to 167, 233, 237 (ACR Premium features) | The opt-in targets use the cheapest tiers on purpose and live for one replay run. |
| No application on the site | CKV_AZURE_13, 17, 88, 213, 222 | The web app serves the default page only. X-10 targets the control plane. |
| One-run container | CKV_AZURE_98 (container group in a VNet) | The group has no IP address at all (`ip_address_type = "None"`). |

## tflint ignore

`azurerm_resources_missing_prevent_destroy` on the lab storage account: it holds no data and must
be removed by `make destroy`.
