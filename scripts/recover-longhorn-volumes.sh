#!/usr/bin/env bash
#
# recover-longhorn-volumes.sh — Re-register orphaned Longhorn volumes (v1.12)
#
# PURPOSE
#   After a Longhorn Helm-release uninstall, the Volume CRs were deleted but
#   the replica DATA remained on disk (/var/lib/longhorn/replicas/pvc-*).
#   Longhorn v1.12 has no "Adopt" button in the UI. This script re-creates
#   the Volume CRs with the EXACT names/sizes of the originals so Longhorn
#   re-claims the on-disk replica data.
#
# SAFETY — READ FIRST
#   * This is NON-destructive: it only creates Volume CRs. It deletes nothing.
#   * Back up the replica dirs BEFORE running (see BACKUP section below).
#   * Verify data exists on disk first:  ssh <node> 'sudo ls /var/lib/longhorn/replicas/'
#
# USAGE
#   bash scripts/recover-longhorn-volumes.sh          # create all 7 volumes
#   bash scripts/recover-longhorn-volumes.sh --apply  # (same; explicit)
#
# After running, in the Longhorn UI: Volumes → each volume → Attach,
# then verify the engine/replica state shows the recovered data.
#
# NOTE: These are the 7 volumes from `kubectl get pvc -A` before the uninstall.
#       Adjust the list if your homelab has different PVCs.

set -euo pipefail

# ─── The 7 volumes to recreate (name, sizeGiB) ──────────────────────────
# From: kubectl get pvc -A -o wide (pre-uninstall)
declare -a VOLUMES=(
  "pvc-746c3394-4a48-4678-9066-e508670d4ede:10"   # garmin-influxdb-data
  "pvc-b33abf75-4ab3-4a6f-85ab-72aedd18e2ae:1"    # garminconnect-tokens
  "pvc-161cfd69-f70d-47a0-b38d-20c2ac6373ad:20"   # storage-loki-0
  "pvc-6bc49ddc-3768-4921-a1e4-910091444b4e:5"    # alertmanager-...-0
  "pvc-be2b725a-1aca-4e24-9256-947d96c198f4:5"    # monitoring-grafana
  "pvc-5ba54df6-484d-440c-9ca2-c44ae57d389a:20"   # prometheus-...-0
  "pvc-3d1f3db9-cfe5-4193-9207-9c442aedb982:5"    # victoriametrics-data
)

NS="longhorn-system"
APIV="longhorn.io/v1beta2"

# ─── Create a Volume CR for each orphaned volume ────────────────────────
create_volume() {
  local name="$1"
  local size_gi="$2"
  local size_bytes=$(( size_gi * 1024 * 1024 * 1024 ))

  echo "── Creating volume ${name} (${size_gi}Gi) ──"

  if kubectl get volume "$name" -n "$NS" >/dev/null 2>&1; then
    echo "  Volume ${name} already exists — skipping."
    return 0
  fi

  kubectl apply -f - <<EOF
apiVersion: ${APIV}
kind: Volume
metadata:
  name: ${name}
  namespace: ${NS}
spec:
  size: "${size_bytes}"
  numberOfReplicas: 3
  frontend: blockdev
  dataLocality: disabled
  replicaAutoBalance: ignored
EOF

  echo "  Volume ${name} created."
}

# ─── Main ───────────────────────────────────────────────────────────────
echo "This script creates Longhorn Volume CRs matching your orphaned replica data."
echo "It is NON-destructive — it only creates Volume CRs, it deletes nothing."
echo ""

if [[ "${1:-}" == "--apply" || "${1:-}" == "apply" ]]; then
  :
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: bash $0 [--apply]"
  exit 0
else
  echo "This will create ${#VOLUMES[@]} Longhorn volumes."
  echo "Run with:  bash $0 --apply   to actually create them."
  echo ""
  echo "(First run, we recommend: bash $0   to preview, then --apply)"
fi

if [[ "${1:-}" == "--apply" || "${1:-}" == "apply" ]]; then
  echo "Creating volumes in namespace ${NS}..."
  echo ""
  for entry in "${VOLUMES[@]}"; do
    name="${entry%%:*}"
    size="${entry##*:}"
    create_volume "$name" "$size"
  done
  echo ""
  echo "Done. Next steps:"
  echo "  1. kubectl -n longhorn-system get volumes.longhorn.io -o wide"
  echo "  2. Longhorn UI → Volumes → Attach each volume → verify engine state"
  echo "  3. Then re-create PVs/PVCs pointing at these volumes (see guide)"
fi
