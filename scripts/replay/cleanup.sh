#!/usr/bin/env bash
# Safety net after replays: delete every replay-created resource in the lab resource group.
# Each replay already deletes its own resources through a trap; this catches cancelled jobs.
# Order: VMs first (their OS disk and NIC are set to go with them), then anything else that is
# tagged huginn-replay or named *huginn-replay* (disks or NICs left by a half-finished create).
# A VM must never survive a run, running or deallocated: deallocated VMs still use vCPU quota.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
huginn_preflight

mapfile -t VMS < <(az vm list -g "$RG" --query "[?tags.\"huginn-replay\" != null || contains(name, 'huginn-replay')].name" -o tsv)
for vm in "${VMS[@]}"; do if [[ -n "$vm" ]]; then huginn_vm_delete "$vm"; fi; done

mapfile -t IDS < <(az resource list -g "$RG" --query "[?tags.\"huginn-replay\" != null || contains(name, 'huginn-replay')].id" -o tsv)
for id in "${IDS[@]}"; do if [[ -n "$id" ]]; then huginn_delete "$id"; fi; done

left="$(az resource list -g "$RG" --query "length([?tags.\"huginn-replay\" != null || contains(name, 'huginn-replay')])" -o tsv)"
huginn_log "replay resources left in $RG: $left"
[[ "$left" == 0 ]]
