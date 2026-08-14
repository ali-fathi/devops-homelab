# NAS-Backup-setup

> **Resume point for Synology NAS + Longhorn backup setup.**
>
> Do not run these steps until the Synology NAS is ready. This repository is prepared; no NAS, K3s-node, Longhorn BackupTarget, or existing application data has been changed by the preparation work.

## Exact setup order

```text
1. Configure the dedicated Synology NFSv4.1 share and its restricted node ACL.
2. Run the all-node NFS client/mount/write probe with Ansible.
3. Configure Longhorn BackupTarget/default with the guarded script.
4. Confirm the target is available.
5. Run the isolated Longhorn backup-and-restore checksum rehearsal.
6. Record the result before considering stateful GitOps pruning.
```

## Step 1 — Synology DSM

Follow every DSM, security, ACL, retention, rollback, and off-site-copy step in:

```text
docs/runbooks/synology-nfs-longhorn-backup-target-setup.md
```

Required intended state:

```text
Dedicated shared folder: longhorn-backups
NFS version: NFSv4.1
Allowed K3s clients only: 192.168.178.80, 192.168.178.81, 192.168.178.82
Longhorn target form: nfs://<synology-ip-or-dns>:/volume1/longhorn-backups
Kubernetes credential Secret: none (NFS export ACL controls access)
```

## Step 2 — Test every K3s node's NFS access

```bash
cd ansible && ansible-playbook playbooks/prepare-longhorn-synology-nfs.yml -e longhorn_nfs_confirm=true -e longhorn_nfs_backup_server=<synology-ip-or-dns> -e longhorn_nfs_backup_export=/volume1/longhorn-backups -e longhorn_nfs_run_probe=true
```

Do not continue unless `.80`, `.81`, and `.82` each pass the temporary NFSv4.1 mount/write/remove/unmount probe.

## Step 3 — Configure Longhorn

```bash
./scripts/configure-longhorn-synology-nfs-backup-target.sh --server <synology-ip-or-dns> --export /volume1/longhorn-backups --confirm
```

If another non-empty Longhorn target already exists, inspect it first and use `--replace-default` only after confirming replacement is intended.

## Step 4 — Confirm target health

```bash
kubectl get backuptargets.longhorn.io default -n longhorn-system -o json | jq '{name: .metadata.name, target: .spec.backupTargetURL, available: .status.available, lastSyncedAt: .status.lastSyncedAt, conditions: .status.conditions}'
```

Required result:

```text
available: true
```

## Step 5 — Prove backup and restore

```bash
./scripts/rehearse-longhorn-backup-restore.sh --confirm --cleanup
```

Required result:

```text
[PASS] Backup and restore rehearsal completed. Source and restored checksums match.
```

Review the resulting non-secret evidence under:

```text
artifacts/longhorn-rehearsal/<run-id>/result.txt
```

## Safety rules

```text
Never use an application PVC as the first rehearsal source.
Never print or commit NAS credentials or Kubernetes Secret values.
Never use a Kubernetes PVC or Longhorn disk as the backup target.
Never permit the whole LAN when only the three K3s node IPs are needed.
Never let NAS cleanup delete individual Longhorn backup objects.
Never enable stateful Argo CD pruning until the rehearsal has passed and evidence is recorded.
```

## Supporting files

```text
ansible/playbooks/prepare-longhorn-synology-nfs.yml
scripts/configure-longhorn-synology-nfs-backup-target.sh
scripts/rehearse-longhorn-backup-restore.sh
kubernetes/infrastructure/longhorn/backup-target-synology-nfs.yaml.template
docs/runbooks/synology-nfs-longhorn-backup-target-setup.md
docs/runbooks/longhorn-backup-restore-rehearsal.md
```
