#!/usr/bin/env bash
# Run the benign replays for a list of rules, in order.
# Usage: scripts/replay/run.sh logicapp-callback-listed,storage-keys-listed,fenrir-chain
# Only rules with validation: ci, deployable: true and an executable replay.sh are accepted.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

IFS=',' read -r -a RULES <<<"${1:?usage: run.sh RULE[,RULE...]}"

for rule in "${RULES[@]}"; do
  [[ "$rule" =~ ^[a-z0-9-]+$ ]] || { echo "bad rule id: $rule" >&2; exit 2; }
  dir="$(ls -d "$ROOT"/detections/*/"$rule" 2>/dev/null || true)"
  [[ -n "$dir" && -x "$dir/replay.sh" ]] || { echo "no replay.sh for $rule" >&2; exit 2; }
  python3 - "$dir/rule.yaml" <<'PY' || { echo "$rule is not a deployable validation: ci rule" >&2; exit 2; }
import sys, yaml
r = yaml.safe_load(open(sys.argv[1]))
sys.exit(0 if r.get("validation") == "ci" and r.get("deployable") else 1)
PY
done

has() { local x; for x in "${RULES[@]}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
if has logicapp-callback-listed && has storage-keys-listed; then
  export HUGINN_SKIP_SIBLINGS=1
fi

for rule in "${RULES[@]}"; do
  echo "::group::replay $rule"
  "$(ls -d "$ROOT"/detections/*/"$rule")/replay.sh"
  echo "::endgroup::"
done
