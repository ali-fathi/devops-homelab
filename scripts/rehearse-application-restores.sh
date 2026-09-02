#!/usr/bin/env bash
# Restore every current stateful application PVC into isolated test volumes.
#
# This is deliberately opt-in and read-only against production workloads. It
# restores the newest completed Longhorn backup for each application PVC into
# a one-replica test volume, mounts it read-only, runs an application-specific
# filesystem validation, records non-secret evidence, and optionally cleans up.

set -Eeuo pipefail

LONGHORN_NAMESPACE="longhorn-system"
STORAGE_CLASS="longhorn"
TIMEOUT_SECONDS=1800
CONFIRM=false
CLEANUP=false
REPORT_ROOT="${PWD}/artifacts/application-restore-drills"
ONLY=""

usage() {
  cat <<'EOF'
Usage: rehearse-application-restores.sh --confirm --cleanup [options]

Restores the newest completed Longhorn backup for every stateful application
PVC into an isolated namespace and validates the restored filesystem without
changing production workloads or PVCs. The restored volumes use one replica to
limit test capacity. No credential values are read or printed.

Options:
  --confirm              Required acknowledgement that this creates test resources.
  --cleanup              Delete each test Pod/PVC/snapshot/content and the test StorageClass.
  --only <name>          Test one key: grafana, alertmanager, loki, prometheus,
                         influxdb, tokens, or victoriametrics.
  --timeout <seconds>    Timeout for each asynchronous operation (default: 1800).
  --report-dir <path>    Directory for non-secret evidence files.
  -h, --help             Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) CONFIRM=true ;;
    --cleanup) CLEANUP=true ;;
    --only)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--only needs a key." >&2; exit 2; }
      ONLY="$2"
      shift
      ;;
    --timeout)
      [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || { echo "--timeout needs a positive integer." >&2; exit 2; }
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

if [[ "$CONFIRM" != true ]]; then
  echo "Refusing to create restore-drill resources without --confirm." >&2
  usage >&2
  exit 2
fi

for command in kubectl jq; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required command not found: $command" >&2; exit 2; }
done

declare -a ALL_KEYS=(grafana alertmanager loki prometheus influxdb tokens victoriametrics)
declare -A SOURCE_NAMESPACES=(
  [grafana]=monitoring
  [alertmanager]=monitoring
  [loki]=logging
  [prometheus]=monitoring
  [influxdb]=garmin
  [tokens]=garmin
  [victoriametrics]=ring-health
)
declare -A SOURCE_PVCS=(
  [grafana]=monitoring-grafana
  [alertmanager]=alertmanager-monitoring-kube-prometheus-alertmanager-db-alertmanager-monitoring-kube-prometheus-alertmanager-0
  [loki]=storage-loki-0
  [prometheus]=prometheus-monitoring-kube-prometheus-prometheus-db-prometheus-monitoring-kube-prometheus-prometheus-0
  [influxdb]=garmin-influxdb-data
  [tokens]=garminconnect-tokens
  [victoriametrics]=victoriametrics-data
)

valid_key() {
  local key="$1"
  for candidate in "${ALL_KEYS[@]}"; do
    [[ "$candidate" == "$key" ]] && return 0
  done
  return 1
}

if [[ -n "$ONLY" ]] && ! valid_key "$ONLY"; then
  echo "Unknown --only key: $ONLY" >&2
  exit 2
fi

run_id="$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
test_namespace="longhorn-restore-drill-${run_id}"
storage_class="longhorn-restore-${run_id}"
snapshot_class="longhorn-restore-${run_id}"
report_dir="${REPORT_ROOT}/${run_id}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
content_names=()

fail() {
  echo "[FAIL] $*" >&2
  echo "Test resources are retained for investigation: namespace=${test_namespace}, report=${report_dir}" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  echo "[FAIL] Restore drill stopped. Production workloads and PVCs were not modified." >&2
  echo "Investigate retained resources: namespace=${test_namespace}, report=${report_dir}" >&2
  exit "$exit_code"
}
trap on_error ERR

wait_for_json() {
  local resource="$1"
  local name="$2"
  local namespace="$3"
  local filter="$4"
  local description="$5"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    if kubectl get "$resource" "$name" -n "$namespace" -o json 2>/dev/null | jq -e "$filter" >/dev/null; then
      echo "[OK] ${description}"
      return 0
    fi
    sleep 5
  done
  fail "Timed out after ${TIMEOUT_SECONDS}s waiting for ${description}."
}

wait_for_pvc_bound() {
  local pvc="$1"
  kubectl wait -n "$test_namespace" --for=jsonpath='{.status.phase}'=Bound "pvc/${pvc}" --timeout="${TIMEOUT_SECONDS}s" >/dev/null || fail "PVC ${pvc} did not become Bound."
  echo "[OK] PVC ${pvc} is Bound"
}

wait_for_pod_ready() {
  local pod="$1"
  kubectl wait -n "$test_namespace" --for=condition=Ready "pod/${pod}" --timeout="${TIMEOUT_SECONDS}s" >/dev/null || fail "Pod ${pod} did not become Ready."
  echo "[OK] Pod ${pod} is Ready"
}

validator_for() {
  case "$1" in
    grafana) printf '%s' 'test -s /data/grafana.db' ;;
    alertmanager) printf '%s' 'test -e /data/alertmanager-db/nflog && find /data -type f -size +0c -print -quit | grep -q .' ;;
    loki) printf '%s' '(test -d /data/chunks || test -d /data/index || test -d /data/boltdb-shipper-active) && find /data -type f -size +0c -print -quit | grep -q .' ;;
    prometheus) printf '%s' '(test -d /data/prometheus-db/wal || test -d /data/prometheus-db/chunks_head || find /data/prometheus-db -maxdepth 1 -type d -name "01*" -print -quit | grep -q .) && find /data -type f -size +0c -print -quit | grep -q .' ;;
    influxdb) printf '%s' 'test -d /data/meta && find /data -type f -size +0c -print -quit | grep -q .' ;;
    tokens) printf '%s' 'find /data -type f -size +0c -print -quit | grep -q .' ;;
    victoriametrics) printf '%s' 'test -d /data/metadata && find /data -type f -size +0c -print -quit | grep -q .' ;;
    *) return 1 ;;
  esac
}

cleanup_one() {
  local pod="$1" pvc="$2" snapshot="$3" content="$4"
  kubectl delete pod "$pod" -n "$test_namespace" --ignore-not-found --wait=true >/dev/null
  kubectl delete pvc "$pvc" -n "$test_namespace" --ignore-not-found --wait=true >/dev/null
  kubectl delete volumesnapshot "$snapshot" -n "$test_namespace" --ignore-not-found --wait=true >/dev/null
  kubectl delete volumesnapshotcontent "$content" --ignore-not-found --wait=true >/dev/null
}

mkdir -p "$report_dir"
printf 'run_id=%s\nstarted_at=%s\nnamespace=%s\nstorage_class=%s\nsnapshot_class=%s\n' \
  "$run_id" "$started_at" "$test_namespace" "$storage_class" "$snapshot_class" > "${report_dir}/result.txt"

context="$(kubectl config current-context)"
echo "[INFO] Kubernetes context: ${context}"
echo "[INFO] This test creates only namespace ${test_namespace}, one temporary StorageClass, and test-only CSI snapshot objects."
echo "[INFO] Production workloads, PVCs, Longhorn volumes, backups, BackupTarget, and Secrets are not modified."

kubectl get storageclass "$STORAGE_CLASS" >/dev/null || fail "StorageClass ${STORAGE_CLASS} is missing."
kubectl get crd volumesnapshots.snapshot.storage.k8s.io volumesnapshotcontents.snapshot.storage.k8s.io volumesnapshotclasses.snapshot.storage.k8s.io >/dev/null || fail "CSI snapshot CRDs are missing."
backup_target_json="$(kubectl get backuptarget.longhorn.io default -n "$LONGHORN_NAMESPACE" -o json 2>/dev/null)" || fail "Longhorn BackupTarget/default is missing."
jq -e '.status.available == true' <<<"$backup_target_json" >/dev/null || fail "Longhorn BackupTarget/default is unavailable."
printf '%s\n' "$backup_target_json" | jq '{available: .status.available, lastSyncedAt: .status.lastSyncedAt}' > "${report_dir}/backup-target-status.json"
kubectl get pvc -A -o json > "${report_dir}/pvc-inventory-before.json"
kubectl get volumes.longhorn.io -n "$LONGHORN_NAMESPACE" -o json > "${report_dir}/longhorn-volume-inventory-before.json"

kubectl create namespace "$test_namespace" >/dev/null
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${storage_class}
  labels:
    app.kubernetes.io/name: longhorn-application-restore-drill
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "1"
  staleReplicaTimeout: "30"
  dataLocality: disabled
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ${snapshot_class}
  labels:
    app.kubernetes.io/name: longhorn-application-restore-drill
driver: driver.longhorn.io
deletionPolicy: Retain
EOF

keys=("${ALL_KEYS[@]}")
[[ -n "$ONLY" ]] && keys=("$ONLY")

for key in "${keys[@]}"; do
  source_namespace="${SOURCE_NAMESPACES[$key]}"
  source_pvc="${SOURCE_PVCS[$key]}"
  source_pvc_json="$(kubectl get pvc "$source_pvc" -n "$source_namespace" -o json 2>/dev/null)" || fail "Source PVC ${source_namespace}/${source_pvc} is missing."
  source_volume="$(jq -r '.spec.volumeName // empty' <<<"$source_pvc_json")"
  restore_size="$(jq -r '.spec.resources.requests.storage // empty' <<<"$source_pvc_json")"
  [[ -n "$source_volume" ]] || fail "Source PVC ${source_namespace}/${source_pvc} has no bound volume."
  [[ -n "$restore_size" ]] || fail "Source PVC ${source_namespace}/${source_pvc} has no requested size."

  backup_json="$(kubectl get backups.longhorn.io -n "$LONGHORN_NAMESPACE" -o json | jq -e --arg volume "$source_volume" '
    [.items[] | select(.metadata.labels["backup-volume"] == $volume and .status.state == "Completed" and .status.backupTargetName == "default")]
    | sort_by(.status.backupCreatedAt // .metadata.creationTimestamp) | last
  ')" || fail "No completed external Longhorn backup found for ${source_namespace}/${source_pvc}."
  backup_name="$(jq -r '.metadata.name' <<<"$backup_json")"
  backup_time="$(jq -r '.status.backupCreatedAt // .metadata.creationTimestamp' <<<"$backup_json")"
  [[ -n "$backup_name" && "$backup_name" != null ]] || fail "Selected backup for ${source_namespace}/${source_pvc} has no name."

  snapshot="${key}-${run_id}"
  content="content-${key}-${run_id}"
  restore_pvc="restore-${key}-${run_id}"
  reader_pod="reader-${key}-${run_id}"
  content_names+=("$content")
  validator="$(validator_for "$key")"
  handle="bak://${source_volume}/${backup_name}"

  echo "[INFO] ${key}: restoring backup ${backup_name} created at ${backup_time}"
  kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotContent
metadata:
  name: ${content}
  labels:
    app.kubernetes.io/name: longhorn-application-restore-drill
spec:
  deletionPolicy: Retain
  driver: driver.longhorn.io
  source:
    snapshotHandle: ${handle}
  volumeSnapshotClassName: ${snapshot_class}
  volumeSnapshotRef:
    name: ${snapshot}
    namespace: ${test_namespace}
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${snapshot}
  namespace: ${test_namespace}
  labels:
    app.kubernetes.io/name: longhorn-application-restore-drill
    app.kubernetes.io/component: ${key}
spec:
  source:
    volumeSnapshotContentName: ${content}
  volumeSnapshotClassName: ${snapshot_class}
EOF
  wait_for_json volumesnapshot "$snapshot" "$test_namespace" '.status.readyToUse == true' "${key} backup snapshot is ready"

  kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${restore_pvc}
  namespace: ${test_namespace}
  labels:
    app.kubernetes.io/name: longhorn-application-restore-drill
    app.kubernetes.io/component: ${key}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${storage_class}
  dataSource:
    name: ${snapshot}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: ${restore_size}
EOF
  wait_for_pvc_bound "$restore_pvc"

  restore_started=$SECONDS
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${reader_pod}
  namespace: ${test_namespace}
  labels:
    app.kubernetes.io/name: longhorn-application-restore-drill
    app.kubernetes.io/component: ${key}
spec:
  restartPolicy: Never
  securityContext:
    fsGroup: 65534
    fsGroupChangePolicy: OnRootMismatch
  containers:
    - name: reader
      image: busybox:1.37.0
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        runAsUser: 65534
      volumeMounts:
        - name: restored-data
          mountPath: /data
          readOnly: true
  volumes:
    - name: restored-data
      persistentVolumeClaim:
        claimName: ${restore_pvc}
EOF
  wait_for_pod_ready "$reader_pod"
  kubectl exec -n "$test_namespace" "$reader_pod" -- sh -ec "$validator" || fail "${key} application-specific filesystem validation failed."
  rto_seconds=$((SECONDS - restore_started))
  printf 'application=%s\nsource_namespace=%s\nsource_pvc=%s\nsource_volume=%s\nbackup=%s\nbackup_created_at=%s\nrestore_seconds=%s\nvalidation=passed\n' \
    "$key" "$source_namespace" "$source_pvc" "$source_volume" "$backup_name" "$backup_time" "$rto_seconds" >> "${report_dir}/${key}.result.txt"
  echo "[PASS] ${key}: restored backup and passed application-specific filesystem validation in ${rto_seconds}s"

  if [[ "$CLEANUP" == true ]]; then
    cleanup_one "$reader_pod" "$restore_pvc" "$snapshot" "$content"
    echo "[OK] ${key}: isolated restore resources removed"
  fi
done

completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'completed_at=%s\nresult=passed\n' "$completed_at" >> "${report_dir}/result.txt"
kubectl get pvc -n "$test_namespace" -o json > "${report_dir}/test-pvcs.json" 2>/dev/null || true
kubectl get volumesnapshot -n "$test_namespace" -o json > "${report_dir}/test-volume-snapshots.json" 2>/dev/null || true

if [[ "$CLEANUP" == true ]]; then
  kubectl delete namespace "$test_namespace" --ignore-not-found --wait=true >/dev/null
  kubectl delete storageclass "$storage_class" --ignore-not-found --wait=true >/dev/null
  kubectl delete volumesnapshotclass "$snapshot_class" --ignore-not-found --wait=true >/dev/null
  echo "[OK] Shared restore-drill resources removed"
else
  echo "[INFO] Test resources are retained. Delete them only after reviewing ${report_dir}."
fi

echo "[PASS] Application restore drill completed for: ${keys[*]}"
echo "[INFO] Non-secret evidence: ${report_dir}"
