#!/usr/bin/env bash
# Phase 3 evidence: perform ONE benign instance of each requested Fenrir-shaped action, as
# whatever identity is signed in to the Azure CLI (in evidence.yml: huginn-lab-attacker).
#
# Safety rules (docs/TESTING.md):
# - acts only on resources in the Huginn lab resource group;
# - every response is discarded (> /dev/null); nothing is printed, stored or reused;
# - no managed-identity token is ever requested.
#
# Usage: scripts/evidence/run.sh X-08,X-13,P-12,X-13-fail
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../replay/lib.sh
source "$ROOT/scripts/replay/lib.sh"   # VM helpers for X-08
RG="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["lab_resource_group"])' "$ROOT/infra/shared/bootstrap.json")"
SUB="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["subscription_id"])' "$ROOT/infra/shared/bootstrap.json")"

# Refuse to run against anything but the Huginn lab resource group.
[[ "$RG" == "huginn-lab-rg" ]] || { echo "unexpected lab resource group: $RG" >&2; exit 2; }
[[ "$(az account show --query id -o tsv)" == "$SUB" ]] || { echo "wrong subscription" >&2; exit 2; }

one_id() { # one_id <resource type> : the single lab resource of that type
  local ids n
  ids="$(az resource list -g "$RG" --resource-type "$1" --query '[].id' -o tsv)"
  n="$(grep -c . <<<"$ids" || true)"
  [[ "$n" == 1 ]] || { echo "expected exactly one $1 in $RG, found $n" >&2; return 1; }
  echo "$ids"
}

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

do_op() {
  local op="$1" id
  echo "$(stamp) start $op"
  case "$op" in
    X-13) # Logic App listCallbackUrl, same API version as Fenrir
      id="$(one_id Microsoft.Logic/workflows)"
      az rest --method post --url "https://management.azure.com${id}/triggers/manual/listCallbackUrl?api-version=2019-05-01" > /dev/null
      ;;
    X-13-fail) # Same action on a trigger that does not exist: expected to fail (status strings for failures)
      id="$(one_id Microsoft.Logic/workflows)"
      if az rest --method post --url "https://management.azure.com${id}/triggers/huginn-does-not-exist/listCallbackUrl?api-version=2019-05-01" > /dev/null 2>&1; then
        echo "unexpected success" >&2; return 1
      fi
      ;;
    X-08) # VM Run Command on a FRESH VM created for this run, deleted through a trap
      huginn_preflight
      local vm="vm-huginn-replay-$(huginn_run_id)"
      trap 'huginn_vm_delete "'"$vm"'"' EXIT
      huginn_log "create $vm ($HUGINN_VM_SIZE, no public IP)"
      huginn_vm_create "$vm"
      huginn_log "run-command invoke on $vm: hostname (output discarded)"
      az vm run-command invoke -g "$RG" -n "$vm" --command-id RunShellScript --scripts hostname > /dev/null
      huginn_vm_delete "$vm"
      trap - EXIT
      ;;
    P-12) # Storage listKeys, same API version as Fenrir
      id="$(one_id Microsoft.Storage/storageAccounts)"
      az rest --method post --url "https://management.azure.com${id}/listKeys?api-version=2023-01-01" > /dev/null
      ;;
    *)
      echo "unknown or not yet supported op: $op" >&2; return 2
      ;;
  esac
  echo "$(stamp) done  $op"
}

IFS=',' read -r -a OPS <<<"${1:?usage: run.sh OP[,OP...]}"
for op in "${OPS[@]}"; do
  [[ "$op" =~ ^(X-08|X-13|X-13-fail|P-12)$ ]] || { echo "op not allowed: $op" >&2; exit 2; }
done
for op in "${OPS[@]}"; do do_op "$op"; done
