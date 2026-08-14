#!/usr/bin/env bash
# Create, back up, restore, and verify an isolated Longhorn test volume.
#
# This is deliberately opt-in and mutating. It never touches an existing PVC,
# Longhorn volume, backup, Secret, or backup-target configuration.

set -Eeuo pipefail

LONGHORN_NAMESPACE="longhorn-system"
STORAGE_CLASS="longhorn"
TIMEOUT_SECONDS=1800
CONFIRM=false
CLEANUP=false
REPORT_ROOT="${PWD}/artifacts/longhorn-rehearsal"

usage() {
  cat <<'EOF'
Usage: rehearse-longhorn-backup-restore.sh --confirm [--cleanup] [--timeout seconds] [--report-dir directory]

Creates an isolated Longhorn PVC, writes a deterministic fixture, creates an
external Longhorn backup through a CSI VolumeSnapshot, restores it to a second
PVC, and compares SHA-256 checksums. A configured, available default Longhorn
BackupTarget is required. No credential values are read or printed.

Options:
  --confirm              Required acknowledgement that this changes the cluster.
  --cleanup              Delete the test namespace and test VolumeSnapshotClass after a successful test.
  --timeout <seconds>    Timeout for each asynchronous operation (default: 1800).
  --report-dir <path>    Directory for non-secret inventory and result files.
  -h, --help             Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) CONFIRM=true ;;
    --cleanup) CLEANUP=true ;;
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
  echo "Refusing to mutate the cluster without --confirm." >&2
  usage >&2
  exit 2
fi

for command in kubectl jq awk; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required command not found: $command" >&2; exit 2; }
done

run_id="$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
test_namespace="longhorn-rehearsal-${run_id}"
snapshot_class="longhorn-rehearsal-backup-${run_id}"
snapshot_name="backup-${run_id}"
source_pvc="source-${run_id}"
restore_pvc="restore-${run_id}"
writer_pod="writer-${run_id}"
reader_pod="reader-${run_id}"
report_dir="${REPORT_ROOT}/${run_id}"
marker="longhorn-backup-restore-rehearsal-${run_id}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
backup_started_seconds=0
restore_started_seconds=0

fail() {
  echo "[FAIL] $*" >&2
  echo "Artifacts are retained for investigation: namespace=${test_namespace}, snapshot-class=${snapshot_class}, report=${report_dir}" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  echo "[FAIL] Rehearsal stopped. No existing workload was changed." >&2
  echo "Investigate retained artifacts: namespace=${test_namespace}, snapshot-class=${snapshot_class}, report=${report_dir}" >&2
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

mkdir -p "$report_dir"
printf 'run_id=%s\nstarted_at=%s\nnamespace=%s\nsnapshot_class=%s\n' "$run_id" "$started_at" "$test_namespace" "$snapshot_class" > "${report_dir}/result.txt"

context="$(kubectl config current-context)"
echo "[INFO] Kubernetes context: ${context}"
echo "[INFO] This test creates only namespace ${test_namespace} and snapshot class ${snapshot_class}."
echo "[INFO] Existing workloads, PVCs, Longhorn volumes, backup targets, and Secrets are not modified."

kubectl get storageclass "$STORAGE_CLASS" >/dev/null || fail "StorageClass ${STORAGE_CLASS} is missing."
kubectl get crd volumesnapshots.snapshot.storage.k8s.io volumesnapshotcontents.snapshot.storage.k8s.io volumesnapshotclasses.snapshot.storage.k8s.io >/dev/null || fail "Kubernetes CSI snapshot CRDs are missing."

backup_target_json="$(kubectl get backuptargets.longhorn.io default -n "$LONGHORN_NAMESPACE" -o json 2>/dev/null)" || fail "Longhorn default BackupTarget is missing. Configure and validate an external backup target before this rehearsal."
jq -e '.status.available == true' <<<"$backup_target_json" >/dev/null || fail "Longhorn default BackupTarget is not available. Inspect its status and do not start the rehearsal."
printf '%s\n' "$backup_target_json" | jq '{name: .metadata.name, namespace: .metadata.namespace, available: .status.available, lastSyncedAt: .status.lastSyncedAt}' > "${report_dir}/backup-target-status.json"
kubectl get pvc -A -o json > "${report_dir}/pvc-inventory-before.json"
kubectl get volumes.longhorn.io -n "$LONGHORN_NAMESPACE" -o json > "${report_dir}/longhorn-volume-inventory-before.json"
echo "[OK] Preconditions and non-secret inventory recorded"

kubectl create namespace "$test_namespace" >/dev/null

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${source_pvc}
  namespace: ${test_namespace}
  labels:
    app.kubernetes.io/name: longhorn-backup-restore-rehearsal
    app.kubernetes.io/part-of: longhorn-rehearsal
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${STORAGE_CLASS}
  resources:
    requests:
      storage: 1Gi
EOF
wait_for_pvc_bound "$source_pvc"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${writer_pod}
  namespace: ${test_namespace}
  labels:
    app.kubernetes.io/name: longhorn-backup-restore-rehearsal
spec:
  restartPolicy: Never
  securityContext:
    fsGroup: 65534
    fsGroupChangePolicy: OnRootMismatch
  containers:
    - name: writer
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
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: ${source_pvc}
EOF
wait_for_pod_ready "$writer_pod"

source_hash="$(kubectl exec -n "$test_namespace" "$writer_pod" -- sh -ec "printf '%s\\n' '${marker}' > /data/fixture; sha256sum /data/fixture > /data/fixture.sha256; cut -d ' ' -f1 /data/fixture.sha256")"
[[ "$source_hash" =~ ^[a-f0-9]{64}$ ]] || fail "Source fixture checksum was not a SHA-256 value."
printf 'source_sha256=%s\n' "$source_hash" >> "${report_dir}/result.txt"
echo "[OK] Source fixture written and checksum recorded"

kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ${snapshot_class}
  labels:
    app.kubernetes.io/name: longhorn-backup-restore-rehearsal
driver: driver.longhorn.io
deletionPolicy: Retain
parameters:
  type: bak
  backupMode: full
EOF

backup_started_seconds=$SECONDS
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${snapshot_name}
  namespace: ${test_namespace}
  labels:
    app.kubernetes.io/name: longhorn-backup-restore-rehearsal
spec:
  volumeSnapshotClassName: ${snapshot_class}
  source:
    persistentVolumeClaimName: ${source_pvc}
EOF
wait_for_json "volumesnapshot" "$snapshot_name" "$test_namespace" '.status.readyToUse == true' "external Longhorn backup is ready"

snapshot_content="$(kubectl get volumesnapshot "$snapshot_name" -n "$test_namespace" -o json | jq -r '.status.boundVolumeSnapshotContentName // empty')"
[[ -n "$snapshot_content" ]] || fail "VolumeSnapshot did not report a bound VolumeSnapshotContent."
kubectl get volumesnapshotcontent "$snapshot_content" -o json | jq -e '.status.snapshotHandle | startswith("bak://")' >/dev/null || fail "VolumeSnapshotContent is not backed by a Longhorn backup."
backup_duration_seconds=$((SECONDS - backup_started_seconds))
printf 'backup_ready_at=%s\nbackup_duration_seconds=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$backup_duration_seconds" >> "${report_dir}/result.txt"
echo "[OK] External backup completed in ${backup_duration_seconds}s"

restore_started_seconds=$SECONDS
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${restore_pvc}
  namespace: ${test_namespace}
  labels:
    app.kubernetes.io/name: longhorn-backup-restore-rehearsal
    app.kubernetes.io/component: restored-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${STORAGE_CLASS}
  dataSource:
    name: ${snapshot_name}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: 1Gi
EOF
wait_for_pvc_bound "$restore_pvc"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${reader_pod}
  namespace: ${test_namespace}
  labels:
    app.kubernetes.io/name: longhorn-backup-restore-rehearsal
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
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: ${restore_pvc}
EOF
wait_for_pod_ready "$reader_pod"

restore_hash="$(kubectl exec -n "$test_namespace" "$reader_pod" -- sh -ec "sha256sum -c /data/fixture.sha256 >/dev/null; cut -d ' ' -f1 /data/fixture.sha256")"
[[ "$restore_hash" == "$source_hash" ]] || fail "Restored fixture checksum differs from the source fixture."

completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
rto_seconds=$((SECONDS - restore_started_seconds))
printf 'restore_sha256=%s\ncompleted_at=%s\nrto_seconds=%s\nresult=passed\n' "$restore_hash" "$completed_at" "$rto_seconds" >> "${report_dir}/result.txt"
kubectl get pvc -n "$test_namespace" -o json > "${report_dir}/test-pvcs.json"
kubectl get volumesnapshot -n "$test_namespace" -o json > "${report_dir}/test-volume-snapshots.json"
kubectl get volumes.longhorn.io -n "$LONGHORN_NAMESPACE" -o json > "${report_dir}/longhorn-volume-inventory-after.json"

echo "[PASS] Backup and restore rehearsal completed. Source and restored checksums match."
echo "[INFO] RPO evidence: the backup contains the fixture written immediately before backup creation."
echo "[INFO] Observed RTO: ${rto_seconds}s from test start to restored workload verification."
echo "[INFO] Evidence: ${report_dir}/result.txt"
echo "[INFO] Retained artifacts: namespace=${test_namespace}, snapshot-class=${snapshot_class}, snapshot-content=${snapshot_content}"

if [[ "$CLEANUP" == true ]]; then
  kubectl delete namespace "$test_namespace" --wait=true
  kubectl delete volumesnapshotclass "$snapshot_class"
  echo "[OK] Test namespace and test VolumeSnapshotClass deleted. The retained VolumeSnapshotContent and external backup are intentionally preserved."
else
  echo "[INFO] Test resources are retained for review. Re-run with --cleanup only after recording the evidence."
fi
