#!/usr/bin/env bash
# Shared helpers for detections/*/*/replay.sh. Source it; do not run it.
#
# Safety rules for every replay (docs/TESTING.md):
# - act only on resources in huginn-lab-rg, created by the replay itself;
# - discard every response (> /dev/null): no key, URL or credential is printed or stored;
# - never request a managed-identity token;
# - delete what was created, through a trap, even on failure.

HUGINN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HUGINN_SHARED="$HUGINN_ROOT/infra/shared/bootstrap.json"

_shared() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$HUGINN_SHARED" "$1"; }

huginn_preflight() {
  SUB="$(_shared subscription_id)"
  RG="$(_shared lab_resource_group)"
  LOCATION="$(_shared location)"
  [[ "$RG" == "huginn-lab-rg" ]] || { echo "refusing: lab resource group is '$RG'" >&2; exit 2; }
  [[ "$(az account show --query id -o tsv)" == "$SUB" ]] || { echo "refusing: wrong subscription" >&2; exit 2; }
  ARM="https://management.azure.com"
  export SUB RG LOCATION ARM
  huginn_run_id > /dev/null   # fix the run ID in this shell; later $(huginn_run_id) calls reuse it
}

# Unique per run and short enough for storage account names (lower-case letters and digits).
huginn_run_id() {
  if [[ -z "${HUGINN_RUN_ID:-}" ]]; then
    HUGINN_RUN_ID="$(date -u +%m%d%H%M)$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
    export HUGINN_RUN_ID
  fi
  echo "$HUGINN_RUN_ID"
}

huginn_log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

# Delete one replay-created resource. Only touches IDs inside the lab resource group.
huginn_delete() {
  local id="$1"
  [[ "${id,,}" == "/subscriptions/${SUB,,}/resourcegroups/${RG,,}/providers/"* ]] || { echo "refusing to delete $id" >&2; return 1; }
  if az resource show --ids "$id" -o none 2>/dev/null; then
    az resource delete --ids "$id" -o none && huginn_log "deleted $(basename "$id")"
  fi
}

# --- Per-run VM for X-08 ------------------------------------------------------------------------
# Smallest workable size in francecentral (checked read-only 2026-11-03, docs/STATUS.md): 2 vCPU,
# 1 GB, Basv2 family (0/10 used). Every 1-vCPU size left in the region has 0 family quota.
# Its restriction is zone-only (zones 2, 3), so the VM is created without a zone.
HUGINN_VM_SIZE="${HUGINN_VM_SIZE:-Standard_B2ats_v2}"
HUGINN_VM_SUBNET_NAME="snet-vm"
HUGINN_VM_VNET_NAME="vnet-huginn-lab"

# huginn_vm_create NAME: Linux VM with no public IP, no NSG of its own (the subnet NSG denies all
# inbound), no identity, password login disabled, throwaway SSH key that is deleted at once.
# The OS disk and NIC are set to be deleted together with the VM.
huginn_vm_create() {
  local name="$1" keydir
  keydir="$(mktemp -d)"
  ssh-keygen -q -t ed25519 -N "" -C "huginn-throwaway" -f "$keydir/id" >/dev/null
  rm -f "$keydir/id"   # Azure needs only the public key; the private key is gone before the VM exists
  az vm create -g "$RG" -n "$name" -l "$LOCATION" \
    --image Canonical:ubuntu-24_04-lts:server:latest \
    --size "$HUGINN_VM_SIZE" \
    --admin-username huginn --authentication-type ssh --ssh-key-values "$keydir/id.pub" \
    --vnet-name "$HUGINN_VM_VNET_NAME" --subnet "$HUGINN_VM_SUBNET_NAME" \
    --public-ip-address "" --nsg "" \
    --storage-sku Standard_LRS \
    --os-disk-delete-option Delete --nic-delete-option Delete \
    --tags "huginn-replay=$(huginn_run_id)" \
    -o none
  rm -rf "$keydir"
}

# huginn_vm_delete NAME: delete the VM; its OS disk and NIC go with it (delete options above).
# Then remove any leftover disk or NIC with the same name prefix, in case creation failed halfway.
huginn_vm_delete() {
  local name="$1" id
  id="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Compute/virtualMachines/$name"
  if az vm show --ids "$id" -o none 2>/dev/null; then
    az vm delete --ids "$id" --yes -o none && huginn_log "deleted VM $name"
  fi
  local leftovers
  leftovers="$(az resource list -g "$RG" --query "[?starts_with(name, '$name')].id" -o tsv)"
  for id in $leftovers; do huginn_delete "$id"; done
}
