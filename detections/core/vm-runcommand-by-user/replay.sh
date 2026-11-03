#!/usr/bin/env bash
# Benign replay for vm-runcommand-by-user (Fenrir X-08).
# Creates a FRESH Linux VM (Standard_B2ats_v2, no public IP, deny-all inbound subnet, no identity,
# throwaway SSH key deleted before the VM exists), runs `hostname` through action Run Command
# with the output discarded, then deletes the VM with its OS disk and NIC through a trap.
# The VM never outlives the run, running or deallocated (deallocated VMs still use vCPU quota).
# Takes about 2 to 3 minutes (create, run, delete).
set -euo pipefail
# shellcheck source=../../../scripts/replay/lib.sh
source "$(dirname "$0")/../../../scripts/replay/lib.sh"
huginn_preflight

NAME="vm-huginn-replay-$(huginn_run_id)"
trap 'huginn_vm_delete "$NAME"' EXIT

huginn_log "create $NAME ($HUGINN_VM_SIZE, no public IP)"
huginn_vm_create "$NAME"

huginn_log "run-command invoke on $NAME: hostname (X-08, output discarded)"
az vm run-command invoke -g "$RG" -n "$NAME" --command-id RunShellScript --scripts hostname > /dev/null
huginn_log "done"
