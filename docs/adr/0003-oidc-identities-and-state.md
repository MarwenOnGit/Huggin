# ADR 0003: OIDC identities, bootstrap stack and state

Date: 2026-11-03. Status: accepted.

## Decision

1. **No secrets anywhere.** GitHub Actions signs in with OIDC federated credentials. No client
   secret or certificate is created for any Huginn app.
2. **Two identities, split by purpose.**

   | Identity | Federated subjects | Azure roles | Watchlist |
   |---|---|---|---|
   | `huginn-github-deploy` | `repo:MarwenOnGit/Huggin:ref:refs/heads/main`, `repo:MarwenOnGit/Huggin:pull_request` | Contributor on `huginn-sentinel-rg` and `huginn-lab-rg`; Monitoring Contributor on the subscription (Activity log diagnostic setting); Storage Blob Data Contributor on the state container | Yes, for Terraform refresh operations on Huginn resource groups only |
   | `huginn-lab-attacker` | `repo:MarwenOnGit/Huggin:environment:lab-replay` | Contributor on `huginn-lab-rg` only | **Never** |

   The attacker's subject is a GitHub **environment**, not a branch. Only jobs that declare
   `environment: lab-replay` can get its token, and the environment can carry protection rules.
3. **Bootstrap is applied by a person, locally, once.** It creates the resource groups, the
   state storage, both apps and every role assignment. CI therefore never needs rights to create
   apps (Graph permissions) or role assignments (User Access Administrator). This is why the lab
   attacker lives in `infra/bootstrap` and not in `infra/lab`, as first planned.
4. **Bootstrap keeps local state** (git-ignored). It creates the remote backend, so it cannot
   store its state there on the first run. The file contains no secrets, and every resource can
   be re-imported. The sentinel and lab stacks use the remote `azurerm` backend with Entra ID auth
   (`use_azuread_auth`). The state account has shared keys disabled, versioning and soft delete on,
   and `prevent_destroy`.
5. **Non-secret IDs are committed.** Bootstrap writes `infra/shared/bootstrap.json` (tenant,
   subscription, client IDs, object IDs, resource names) and `infra/shared/backend.hcl`. The other
   stacks read them. Client IDs are not credentials under OIDC.

## Known trade-offs

- The `pull_request` subject maps to the deploy identity, which has Contributor rights. GitHub
  does not issue OIDC tokens to pull requests from forks, so only branches pushed to this repo can
  use it. `ci.yml` uses no Azure login at all. A stricter setup would map `pull_request` to a
  separate Reader identity.
- Monitoring Contributor at subscription scope is broader than the single diagnostic setting it
  is needed for. No narrower built-in role exists.
