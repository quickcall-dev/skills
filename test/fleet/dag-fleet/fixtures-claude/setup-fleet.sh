#!/usr/bin/env bash
# setup-fleet.sh — prepare a fleet root from one of this directory's fixture
# fleet.json files. Copies the fleet.json, writes a prompt.md for every worker,
# writes a per-worker bash task script under ${FLEET_ROOT}/.fake-tasks/<id>.sh,
# and rewrites placeholder strings (FIXTURES_DIR) inside the fleet.json.
#
# Usage:
#   setup-fleet.sh <fixture-name> <fleet-root>
#
# Where <fixture-name> is one of: dag, completion, cycle
#
# The caller is responsible for creating an empty/fresh <fleet-root>. Tasks per
# fixture are hard-coded below — keep them short so scenarios stay under 2m.

set -euo pipefail

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 2 ]]; then
  echo "usage: setup-fleet.sh <fixture-name> <fleet-root>" >&2
  exit 1
fi

FIXTURE="$1"
FLEET_ROOT="$2"
mkdir -p "${FLEET_ROOT}/workers" "${FLEET_ROOT}/.fake-tasks"

SRC_JSON="${FIXTURES_DIR}/${FIXTURE}-fleet.json"
if [[ ! -f "$SRC_JSON" ]]; then
  echo "fixture not found: $SRC_JSON" >&2
  exit 1
fi

# Substitute placeholder so on_complete_hook points at the real hook path.
sed "s|FIXTURES_DIR|${FIXTURES_DIR}|g" "$SRC_JSON" > "${FLEET_ROOT}/fleet.json"

# Write prompt.md + .fake-tasks/<id>.sh per worker
worker_ids=$(jq -r '.workers[].id' "${FLEET_ROOT}/fleet.json")
for wid in $worker_ids; do
  mkdir -p "${FLEET_ROOT}/workers/${wid}"
  echo "fake worker ${wid}" > "${FLEET_ROOT}/workers/${wid}/prompt.md"
done

# Per-fixture task bodies. Each writes a finding.md so verify.sh is happy.
write_task() {
  local wid="$1"; shift
  local body="$*"
  cat > "${FLEET_ROOT}/.fake-tasks/${wid}.sh" <<EOF
#!/usr/bin/env bash
set -e
mkdir -p "\${FLEET_ROOT}/workers/${wid}/output"
${body}
echo done > "\${FLEET_ROOT}/workers/${wid}/output/finding.md"
EOF
  chmod +x "${FLEET_ROOT}/.fake-tasks/${wid}.sh"
}

case "$FIXTURE" in
  dag)
    write_task a "sleep 5"
    write_task b "sleep 5"
    write_task c "sleep 3"
    write_task d "sleep 5"
    write_task e "sleep 5"
    write_task f "sleep 2"
    ;;
  completion)
    write_task w1 "sleep 3"
    write_task w2 "sleep 3"
    write_task w3 "sleep 3"
    ;;
  cycle)
    write_task a "sleep 1"
    write_task b "sleep 1"
    ;;
  *)
    echo "unknown fixture: $FIXTURE" >&2
    exit 1
    ;;
esac

echo "fleet root ready: ${FLEET_ROOT}"
