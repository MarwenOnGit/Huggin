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
