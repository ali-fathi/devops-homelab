#!/usr/bin/env bash
# Configure Longhorn's default BackupTarget to a Synology NFSv4 export.
#
# This script changes only longhorn-system/BackupTarget/default. It never
# reads Secret data and refuses to replace an existing non-empty target unless
# --replace-default is supplied explicitly.

set -Eeuo pipefail

LONGHORN_NAMESPACE="longhorn-system"
POLL_INTERVAL=300
TIMEOUT_SECONDS=300
CONFIRM=false
REPLACE_DEFAULT=false
NFS_SERVER=""
NFS_EXPORT=""
REPORT_ROOT="${PWD}/artifacts/longhorn-nfs-target"

usage() {
  cat <<'EOF'
Usage: configure-longhorn-synology-nfs-backup-target.sh --server <dns-or-ip> --export <absolute-nfs-export-path> --confirm [--replace-default] [--poll-interval seconds] [--timeout seconds] [--report-dir directory]

Configures Longhorn BackupTarget/default as nfs://<server>:<export>. This is
mutating: it changes Longhorn's active default backup target. It never prints
or reads Kubernetes Secret values. An existing non-empty target requires the
additional --replace-default acknowledgement.

Options:
  --server <dns-or-ip>         Synology DNS name or fixed LAN IP.
  --export <absolute-path>     Synology NFS export, e.g. /volume1/longhorn-backups.
  --confirm                    Required acknowledgement for the target change.
  --replace-default            Required if default currently has a non-empty URL.
  --poll-interval <seconds>    Longhorn backupstore poll interval (default: 300).
  --timeout <seconds>          Wait time for BackupTarget availability (default: 300).
  --report-dir <path>          Local non-secret configuration evidence directory.
  -h, --help                   Show this message.
EOF
}

positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--server needs a value." >&2; exit 2; }
      NFS_SERVER="$2"
      shift
      ;;
    --export)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--export needs a value." >&2; exit 2; }
      NFS_EXPORT="$2"
      shift
      ;;
    --confirm) CONFIRM=true ;;
    --replace-default) REPLACE_DEFAULT=true ;;
    --poll-interval)
      [[ $# -ge 2 ]] && positive_integer "$2" || { echo "--poll-interval needs a positive integer." >&2; exit 2; }
      POLL_INTERVAL="$2"
      shift
      ;;
    --timeout)
      [[ $# -ge 2 ]] && positive_integer "$2" || { echo "--timeout needs a positive integer." >&2; exit 2; }
      TIMEOUT_SECONDS="$2"
      shift
      ;;
    --report-dir)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--report-dir needs a path." >&2; exit 2; }
      REPORT_ROOT="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[[ "$CONFIRM" == true ]] || { echo "Refusing to change Longhorn without --confirm." >&2; usage >&2; exit 2; }
[[ -n "$NFS_SERVER" ]] || { echo "--server is required." >&2; exit 2; }
[[ "$NFS_EXPORT" == /* ]] || { echo "--export must be an absolute NFS export path, beginning with /." >&2; exit 2; }
[[ "$NFS_SERVER" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "--server must be an IPv4 address or DNS name containing only letters, digits, dots, and hyphens." >&2; exit 2; }
[[ "$NFS_EXPORT" =~ ^/[A-Za-z0-9._/-]+$ ]] || { echo "--export must be an absolute path containing only letters, digits, ., _, /, and -." >&2; exit 2; }

for command in kubectl jq; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required command not found: $command" >&2; exit 2; }
done

context="$(kubectl config current-context)"
target_url="nfs://${NFS_SERVER}:${NFS_EXPORT}"
run_id="$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
report_dir="${REPORT_ROOT}/${run_id}"
mkdir -p "$report_dir"

kubectl get crd backuptargets.longhorn.io >/dev/null || { echo "Longhorn BackupTarget CRD is missing." >&2; exit 1; }

existing_json="$(kubectl get backuptargets.longhorn.io default -n "$LONGHORN_NAMESPACE" -o json 2>/dev/null || true)"
existing_url=""
if [[ -n "$existing_json" ]]; then
  existing_url="$(jq -r '.spec.backupTargetURL // empty' <<<"$existing_json")"
  printf '%s\n' "$existing_json" | jq '{name: .metadata.name, namespace: .metadata.namespace, backupTargetURL: .spec.backupTargetURL, credentialSecret: .spec.credentialSecret, pollInterval: .spec.pollInterval, available: .status.available}' > "${report_dir}/previous-target.json"
fi

if [[ -n "$existing_url" && "$existing_url" != "$target_url" && "$REPLACE_DEFAULT" != true ]]; then
  echo "BackupTarget/default already points to a non-empty target. Refusing to replace it without --replace-default." >&2
  echo "Existing non-secret target metadata was recorded in ${report_dir}/previous-target.json." >&2
  exit 2
fi

printf 'context=%s\nconfigured_at=%s\ntarget_url=%s\npoll_interval_seconds=%s\n' "$context" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$target_url" "$POLL_INTERVAL" > "${report_dir}/requested-target.txt"
echo "[INFO] Kubernetes context: ${context}"
echo "[INFO] Configuring BackupTarget/default as ${target_url}"
echo "[INFO] No credential Secret is used for this NFS target."

kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: BackupTarget
metadata:
  name: default
  namespace: ${LONGHORN_NAMESPACE}
  labels:
    app.kubernetes.io/name: longhorn-backup-target
    app.kubernetes.io/component: synology-nfs
spec:
  backupTargetURL: "${target_url}"
  credentialSecret: ""
  pollInterval: "${POLL_INTERVAL}"
EOF

deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  status_json="$(kubectl get backuptargets.longhorn.io default -n "$LONGHORN_NAMESPACE" -o json)"
  if jq -e '.status.available == true' <<<"$status_json" >/dev/null; then
    printf '%s\n' "$status_json" | jq '{name: .metadata.name, namespace: .metadata.namespace, backupTargetURL: .spec.backupTargetURL, credentialSecret: .spec.credentialSecret, pollInterval: .spec.pollInterval, available: .status.available, lastSyncedAt: .status.lastSyncedAt, conditions: .status.conditions}' > "${report_dir}/configured-target-status.json"
    echo "[PASS] BackupTarget/default is available."
    echo "[INFO] Evidence: ${report_dir}"
    exit 0
  fi
  sleep 5
done

status_json="$(kubectl get backuptargets.longhorn.io default -n "$LONGHORN_NAMESPACE" -o json)"
printf '%s\n' "$status_json" | jq '{name: .metadata.name, namespace: .metadata.namespace, backupTargetURL: .spec.backupTargetURL, credentialSecret: .spec.credentialSecret, pollInterval: .spec.pollInterval, available: .status.available, lastSyncedAt: .status.lastSyncedAt, conditions: .status.conditions}' > "${report_dir}/failed-target-status.json"
echo "[FAIL] BackupTarget/default did not become available within ${TIMEOUT_SECONDS}s." >&2
echo "[INFO] The requested and previous non-secret metadata are in ${report_dir}. Do not retry blindly; follow docs/runbooks/synology-nfs-longhorn-backup-target-setup.md." >&2
exit 1
