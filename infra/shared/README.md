# infra/shared

Written by `infra/bootstrap` on apply. Committed on purpose: the files hold identifiers, not
credentials (ADR 0003).

- `bootstrap.json`: tenant, subscription, region, resource group names, state account, client IDs
  and object IDs of `huginn-github-deploy` and `huginn-lab-attacker`. Read by `infra/sentinel`,
  `infra/lab` and the workflows.
- `backend.hcl`: partial backend config for `make init STACK=sentinel|lab`.
