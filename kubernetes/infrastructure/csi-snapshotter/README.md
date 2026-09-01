# CSI Snapshot Support

This directory vendors the official Kubernetes CSI external snapshotter CRDs and common snapshot controller at `v8.5.0`, matching the Longhorn 1.12.1 CSI snapshotter family.

The controller is required by the Longhorn backup/restore rehearsal and is deployed through the `csi-snapshotter` Argo CD Application. It does not create backups by itself; Longhorn's `VolumeSnapshotClass` selects the external NFS `BackupTarget/default`.

Validate:

```bash
kubectl get crd volumesnapshots.snapshot.storage.k8s.io volumesnapshotcontents.snapshot.storage.k8s.io volumesnapshotclasses.snapshot.storage.k8s.io
kubectl rollout status deployment/snapshot-controller -n kube-system
```

Keep the CRDs and controller on the same external-snapshotter release line. Do not delete snapshot content or external backups as broad cleanup.
