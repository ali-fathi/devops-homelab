# Runbook: Longhorn Backup and Restore Rehearsal

This runbook performs Phase 3 Task 3.8 without touching an application PVC. It proves that Longhorn can write a backup to an **external** backup target and provision a new PVC from that backup.

## Status

```text
Task status: implemented; live rehearsal required for verification
Longhorn chart assumed by this runbook: 1.12.0
Test scope: isolated 1 GiB Longhorn PVC and deterministic non-secret fixture
```

Do not enable Argo CD pruning for stateful Applications based only on a successful YAML or script review. The task is verified only after the live command returns `[PASS]` and its evidence has been reviewed.

## Goal and non-goals

### Goal

```text
Create isolated data -> create off-cluster Longhorn backup -> restore new PVC
-> mount restored PVC -> compare SHA-256 checksum -> record observed RPO/RTO.
```

### Non-goals

```text
Do not back up or restore a live application during this first rehearsal.
Do not overwrite a source PVC, PV, or Longhorn volume.
Do not change a BackupTarget, its credential Secret, or Longhorn global settings.
Do not print backup target credentials, Secret data, or full backup URLs.
Do not enable Argo CD pruning as part of this task.
```

A Longhorn snapshot alone resides in the cluster's storage domain. It is useful for local rollback but is not a disaster-recovery backup. This rehearsal requires an available Longhorn `BackupTarget` and uses a CSI `VolumeSnapshotClass` with `type: bak`, which makes Longhorn upload the snapshot to the external backupstore.

## Architecture and ownership

```text
Operator workstation
  -> scripts/rehearse-longhorn-backup-restore.sh
  -> isolated namespace longhorn-rehearsal-<run-id>
      -> source PVC (StorageClass: longhorn)
      -> writer Pod creates deterministic fixture + SHA-256
      -> CSI VolumeSnapshot (type: bak)
          -> Longhorn BackupTarget (external Azure Blob, S3-compatible store, NFS, or SMB)
      -> restored PVC sourced from the VolumeSnapshot
      -> reader Pod verifies the restored SHA-256
```

| Object | Owner | Notes |
|---|---|---|
| Longhorn Helm release | Terraform | Chart version is pinned in `terraform/longhorn.tf`. |
| Existing application PVCs and volumes | Their workload/controller | This rehearsal must not modify them. |
| Backup target credentials | Azure Key Vault and External Secrets Operator | Never commit `AZBLOB_ACCOUNT_KEY`, S3 keys, NFS credentials, or Secret data. |
| Longhorn `BackupTarget` | Longhorn operator configuration | Must already exist as `default` and report `status.available: true`. |
| Rehearsal namespace, PVCs, Pods, VolumeSnapshot, and VolumeSnapshotClass | Explicit operator script | Created with a unique run ID; not Argo CD or Terraform managed. |
| Evidence files | Operator workstation | Written beneath ignored `artifacts/longhorn-rehearsal/`; no secret values or full backup URL are recorded. |

## Backup target prerequisite

Longhorn 1.12.0 supports external NFS, SMB/CIFS, Azure Blob Storage, and S3-compatible backupstores. For this Azure-based homelab, Azure Blob is the preferred target when a dedicated storage account/container is available. The target must be independent of Longhorn disks and the K3s nodes; a Longhorn volume, node-local path, or PVC is not a disaster-recovery target.

Use a dedicated backup container and a least-privilege storage identity. For Azure Blob, Longhorn needs only the target account name and a key/credential with the ability to read, write, list, and delete objects in that dedicated container. Store the credential in Azure Key Vault and sync it to a Kubernetes Secret in `longhorn-system` through External Secrets Operator. Configure Longhorn to reference the Secret by name; never place its values in Git, command history, script arguments, terminal output, or this runbook.

Longhorn manages backup retention itself. Do **not** add a storage-account lifecycle policy that independently deletes Longhorn backup objects, because it can break incremental backup chains.

Verify only non-secret target status before starting:

```bash
kubectl get backuptargets.longhorn.io default -n longhorn-system -o json | jq '{name: .metadata.name, available: .status.available, lastSyncedAt: .status.lastSyncedAt, conditions: .status.conditions}'
```

Expected result:

```text
name: default
available: true
```

If the target is missing or unavailable, stop. Diagnose it without displaying the credential Secret:

```bash
kubectl describe backuptargets.longhorn.io default -n longhorn-system
```

```bash
kubectl get pods -n longhorn-system
```

```bash
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=200
```

Do not run the rehearsal against a local MinIO test installation or an in-cluster backup target and call it disaster recovery. Those are useful development tests, not evidence that data survives loss of the cluster or Longhorn disks.

## Preflight and inventory

The script fails closed unless all of these are true:

```text
The active kubeconfig can access the Kubernetes API.
StorageClass longhorn exists.
CSI VolumeSnapshot CRDs exist.
Longhorn BackupTarget default exists and is available.
The operator explicitly passes --confirm.
```

Check the active context first:

```bash
kubectl config current-context
```

Capture a human-readable inventory before the run. This command reads metadata and status only; it does not print Secret values:

```bash
kubectl get pvc -A -o custom-columns='NAMESPACE:.metadata.namespace,PVC:.metadata.name,PHASE:.status.phase,STORAGECLASS:.spec.storageClassName,PV:.spec.volumeName'
```

```bash
kubectl get volumes.longhorn.io -n longhorn-system -o custom-columns='VOLUME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,SIZE:.spec.size'
```

## Execute the isolated rehearsal

Review the script before executing it:

```bash
sed -n '1,360p' scripts/rehearse-longhorn-backup-restore.sh
```

Run from the repository root. This is a mutating command, but it creates only uniquely named test objects. `--cleanup` removes the test namespace and its test-only `VolumeSnapshotClass` after a pass; it intentionally preserves the CSI snapshot content and external backup for evidence and explicit lifecycle review.

```bash
./scripts/rehearse-longhorn-backup-restore.sh --confirm --cleanup
```

The default timeout for each asynchronous step is 30 minutes. For a slower backup target, set an explicit per-step timeout:

```bash
./scripts/rehearse-longhorn-backup-restore.sh --confirm --cleanup --timeout 3600
```

Expected success output includes:

```text
[OK] Preconditions and non-secret inventory recorded
[OK] PVC source-... is Bound
[OK] external Longhorn backup is ready
[OK] PVC restore-... is Bound
[PASS] Backup and restore rehearsal completed. Source and restored checksums match.
```

The script writes a non-secret evidence file under:

```text
artifacts/longhorn-rehearsal/<run-id>/result.txt
```

It records the run ID, timestamps, source/restored SHA-256 values, backup duration, and end-to-end observed RTO. It does not record Secret data or the full backup URL.

## Integrity, RPO, and RTO interpretation

A pass proves all of the following for the fixture written by the script:

```text
Longhorn accepted the external BackupTarget.
A full backup completed and became CSI-ready.
The CSI driver created a new Longhorn volume/PVC from that backup.
The restored filesystem mounted successfully.
The restored fixture checksum exactly matched the source checksum.
```

The script's **observed RTO** is its elapsed time from submission of the restored PVC until the restored reader Pod verifies the checksum. Record it as a baseline, not a production promise: it excludes backup creation and operator decision time, and a larger volume, a busy backup target, or recovery to a new cluster can take longer.

The script's **fixture RPO** is near zero because it writes the fixture immediately before backup creation. That does not establish an RPO for Grafana, Prometheus, Loki, Alertmanager, InfluxDB, or VictoriaMetrics. Define each workload's production RPO from its recurring backup cadence and its RTO from a workload-specific restore exercise.

Initial targets until application-specific rehearsals exist:

| Workload class | Initial RPO target | Initial RTO target | Notes |
|---|---:|---:|---|
| Low-risk application metadata | 24 hours | 4 hours | Confirm acceptable with the workload owner. |
| Grafana dashboards/configuration | 24 hours | 4 hours | Git-managed dashboards are recoverable separately from PVC data. |
| Metrics and logs | 24 hours | 8 hours | Retention and data size may make full restore impractical. |
| Garmin InfluxDB / Ring VictoriaMetrics | 24 hours | 4 hours | Require their own data-consistency rehearsal before relying on these targets. |
| Alertmanager | 24 hours | 4 hours | Routing configuration and credentials have separate Git/Key Vault recovery paths. |

These are planning targets, not verified service-level objectives.

## Failure handling and rollback

The script leaves all test artifacts on a failure so an operator can investigate. It does not delete or roll back any existing workload. Find the run ID in the final error message, then inspect only that isolated namespace:

```bash
kubectl get all,pvc,volumesnapshot -n longhorn-rehearsal-<run-id>
```

```bash
kubectl describe volumesnapshot backup-<run-id> -n longhorn-rehearsal-<run-id>
```

```bash
kubectl get volumesnapshotcontent
```

```bash
kubectl get volumes.longhorn.io -n longhorn-system -o custom-columns='VOLUME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness'
```

| Symptom | Likely cause | Safe response |
|---|---|---|
| `BackupTarget` unavailable | Bad endpoint, missing ESO Secret, network/DNS issue, or target authorization failure | Fix the target configuration and wait for `available: true`; do not expose Secret data. |
| Source PVC stays Pending | Longhorn disk/node scheduling or StorageClass issue | Inspect PVC events and Longhorn volume state; do not delete any application PVC. |
| VolumeSnapshot never becomes ready | CSI snapshot controller missing, backup target unavailable, or backup operation failed | Inspect the VolumeSnapshot, VolumeSnapshotContent, Longhorn manager logs, and target status. |
| Restored PVC stays Pending | Restore/provisioning failure or insufficient Longhorn capacity | Inspect PVC events and restored volume state; preserve source evidence. |
| Checksum mismatch | Backup/restore data-integrity failure | Stop; preserve all artifacts, do not enable pruning, and investigate Longhorn support logs before retrying. |

After evidence is recorded, remove the test namespace and test-only `VolumeSnapshotClass` if the script was run without `--cleanup`:

```bash
kubectl delete namespace longhorn-rehearsal-<run-id> --wait=true
```

```bash
kubectl delete volumesnapshotclass longhorn-rehearsal-backup-<run-id>
```

The rehearsal uses `deletionPolicy: Retain`; the associated `VolumeSnapshotContent` and external backup remain intentionally. Delete a retained rehearsal backup only through Longhorn's backup lifecycle after recording the result. Do not use a broad `kubectl delete backups --all`, delete the Longhorn system namespace, or delete application PVCs as cleanup.

## Follow-up recovery exercises

A successful isolated test is the gate for the next, workload-specific rehearsals, not permission to delete stateful resources. For each stateful workload:

```text
1. Freeze or quiesce writes according to the application's documented procedure.
2. Record the application-level integrity check before backup.
3. Back up to the same external target.
4. Restore to a new namespace/PVC/workload; never overwrite the source first.
5. Run the application-level integrity check and compare results.
6. Record actual data size, backup time, restore time, RPO, RTO, and rollback steps.
7. Only then decide whether the workload can tolerate pruning or a major upgrade.
```

## Files changed for Task 3.8

```text
scripts/rehearse-longhorn-backup-restore.sh
  Explicit, opt-in isolated backup/restore test with checksum verification.

scripts/README.md
  Script entry point and mutation/safety boundary.

.gitignore
  Keeps workstation rehearsal evidence out of Git.

docs/runbooks/longhorn-backup-restore-rehearsal.md
  This operational procedure, target configuration boundary, validation, RPO/RTO, cleanup, and rollback guidance.

kubernetes/infrastructure/longhorn/README.md
  Links platform storage documentation to this rehearsal runbook.

docs/expansion-plan-phase-3.md
  Marks Task 3.8 implemented until a live pass is recorded.
```

## References

- Longhorn 1.12.0: [Create a Backup](https://longhorn.io/docs/1.12.0/snapshots-and-backups/backup-and-restore/create-a-backup/)
- Longhorn 1.12.0: [Restore from a Backup](https://longhorn.io/docs/1.12.0/snapshots-and-backups/backup-and-restore/restore-from-a-backup/)
- Longhorn 1.12.0: [CSI VolumeSnapshot Associated with Longhorn Backup](https://longhorn.io/docs/1.12.0/snapshots-and-backups/csi-snapshot-support/csi-volume-snapshot-associated-with-longhorn-backup/)
- Longhorn 1.12.0: [Set a Backup Target](https://longhorn.io/docs/1.12.0/snapshots-and-backups/backup-and-restore/set-backup-target/)
