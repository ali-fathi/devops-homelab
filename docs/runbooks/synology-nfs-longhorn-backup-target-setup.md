# Runbook: Synology NFS Backup Target for Longhorn

Use this runbook when you are ready to configure the Synology NAS as Longhorn's external backupstore. It is intentionally written so that preparing this repository does not change the NAS, K3s nodes, or Longhorn. The only mutating steps require the NAS address/export chosen by the operator and an explicit `--confirm` or Ansible extra variable.

## Status and scope

```text
Status: implementation ready; NAS and live-cluster configuration pending
Longhorn release: chart 1.12.0
Protocol: NFSv4.1
Longhorn target: longhorn-system/BackupTarget named default
```

This configuration protects against loss of a Longhorn disk, K3s node, or the whole K3s cluster because the backup data is stored on the separate Synology NAS. It does **not** protect against a NAS failure, fire, theft, ransomware, or site loss. After this rehearsal is verified, add a separately tested Synology replication or off-site backup plan.

## Architecture and boundaries

```text
K3s nodes: 192.168.178.80, .81, .82, .83, .84
  -> NFSv4.1 mount to dedicated Synology share
  -> Longhorn BackupTarget/default
  -> Longhorn backupstore
  -> backup/restore rehearsal restores a new test PVC

Synology NAS is not a Kubernetes workload and is not GitOps-managed.
```

| Layer | Owner | Responsibility |
|---|---|---|
| Synology shared folder, NFS service, firewall, and export ACL | NAS operator | Dedicated storage and access limited to the five K3s nodes. |
| NFS client package and write/mount probe on K3s nodes | Ansible playbook | Confirms every node can use the export with NFSv4.1. |
| `BackupTarget/default` endpoint | Explicit operator script | Configures the Longhorn API only after the mount probe passes. |
| Existing application data | Application owners | Never altered by initial target setup or isolated rehearsal. |
| Test backup and restore | `rehearse-longhorn-backup-restore.sh` | Creates only uniquely named test resources. |

NFS authentication uses the export ACL and `AUTH_SYS`; there is no Kubernetes credential Secret for this target. Do not create an empty Secret, commit NAS administrator credentials, or pass them to any repository script.

## Values to decide before changing anything

Record these non-secret values in your operator notes. Do not add them to a credential file.

| Value | Recommended value | Reason |
|---|---|---|
| Synology name/IP | A DHCP-reserved LAN IP or internal DNS name | The backup target must remain reachable after router/DHCP changes. |
| Dedicated shared folder | `longhorn-backups` | Prevents Longhorn retention from mixing with personal, media, or Terraform-state files. |
| Export path | Usually `/volume1/longhorn-backups` | This is the path DSM displays for the NFS export; confirm it in DSM. |
| NFS clients | `192.168.178.80`, `192.168.178.81`, `192.168.178.82`, `192.168.178.83`, `192.168.178.84` | Least privilege: only K3s nodes may mount the backup share. |
| NFS version | NFSv4.1 | Required/supported by Longhorn backup operations. |
| Longhorn target name | `default` | The rehearsal script intentionally uses only the default target. |
| Poll interval | `300` seconds initially | Reasonable discovery interval for a small homelab; adjust after observation. |

The final target has this form:

```text
nfs://<synology-ip-or-dns>:/volume1/longhorn-backups
```

The `nfs://` scheme, server, colon, and absolute export path are all required. Do not point it at `/volume1/homes`, a USB share, a mounted cloud folder, an in-cluster MinIO service, a Kubernetes PVC, or the Terraform-state location.

## Stage 1 — Prepare the Synology NAS in DSM

### 1. Create a dedicated shared folder

1. Log in to DSM with an administrator account.
2. Open **Control Panel → Shared Folder → Create**.
3. Select the intended volume, normally `volume1`.
4. Name the share `longhorn-backups`.
5. Keep the share dedicated to Longhorn backups; do not put personal, application, or Terraform files in it.
6. Enable encryption at rest if it is operationally appropriate for this NAS and you have documented how the encryption key is recovered after NAS restart.
7. Record the displayed path, commonly `/volume1/longhorn-backups`.

If the NAS uses Btrfs, Synology snapshots of the **whole dedicated share** can provide a secondary recovery layer. Do not configure a NAS lifecycle/cleanup task that deletes individual Longhorn files: incremental backup chains are managed by Longhorn and can be damaged by independent deletion.

### 2. Enable NFSv4.1

1. Open **Control Panel → File Services → NFS**.
2. Enable NFS.
3. Enable NFSv4.1 support.
4. Apply the settings.
5. If DSM asks for an NFSv4 domain, record the chosen domain and use the DSM default unless your NAS identity design requires a specific one.

NFS with `AUTH_SYS` does not encrypt data on the wire. Keep the NAS and nodes on a trusted LAN/VLAN, do not expose NFS to the internet, and use Synology firewall rules to permit NFS only from the five node IPs.

### 3. Restrict the NFS export

1. Open **Control Panel → Shared Folder**.
2. Select `longhorn-backups`, select **Edit**, then open **NFS Permissions**.
3. Create one read/write rule for each K3s node: `192.168.178.80`, `192.168.178.81`, `192.168.178.82`, `192.168.178.83`, and `192.168.178.84`.
4. Select **Read/Write** privilege and **sys** security.
5. For this dedicated machine-to-machine backup share, use **Map all users to admin** to avoid `AUTH_SYS` UID/GID mismatch between Longhorn components and DSM. This is acceptable only because the share is dedicated and the client ACL is restricted to those five nodes.
6. Do not use `*`, `192.168.178.0/24`, or an internet-routable network unless there is a documented operational reason.
7. Leave guest/anonymous access disabled and do not enable access for untrusted networks.
8. Apply the rule and record the exact export path DSM shows.

If your DSM version uses slightly different labels, preserve the same outcome: NFSv4.1, read/write access from only `.80`, `.81`, `.82`, `.83`, `.84`, and a dedicated share that permits Longhorn's mounted workload identity to write.

## Stage 2 — Prepare and probe every K3s node

The playbook installs the distribution-appropriate NFS client package (`nfs-common` on Debian/Ubuntu and `nfs-utils` on Red Hat-family systems). When the optional probe is enabled, it mounts the export with NFSv4.1 on every node, writes and removes one empty unique probe file, then unmounts it in an `always` cleanup block.

Review the playbook first:

```bash
sed -n '1,260p' ansible/playbooks/prepare-longhorn-synology-nfs.yml
```

From the repository root, check Ansible connectivity:

```bash
cd ansible && ansible k3s_cluster -m ping
```

Run the prepare-and-probe playbook after substituting the NAS address and confirmed DSM export path. The command is intentionally explicit and mutating only on the five K3s nodes and the dedicated NAS share:

```bash
cd ansible && ansible-playbook playbooks/prepare-longhorn-synology-nfs.yml -e longhorn_nfs_confirm=true -e longhorn_nfs_backup_server=<synology-ip-or-dns> -e longhorn_nfs_backup_export=/volume1/longhorn-backups -e longhorn_nfs_run_probe=true
```

Expected per-node result:

```text
ok: NFS client package present
ok: NFSv4.1 mount succeeded
ok: unique probe file was written and removed
ok: temporary mount was unmounted
```

Stop if any node fails. A Longhorn backup can be scheduled on any eligible node, so a successful mount from only the control-plane node is not enough.

Common failures:

| Symptom | Cause | Safe correction |
|---|---|---|
| `access denied by server` | Missing/wrong NFS ACL or wrong DSM export path | Compare the node IP and export path to DSM NFS Permissions. |
| `mount.nfs: Protocol not supported` | NFSv4.1 disabled or client package/kernel support missing | Enable NFSv4.1 in DSM and install the node NFS client package. |
| `permission denied` when writing probe | UID/GID mapping or DSM share ACL problem | On the dedicated share, confirm the NFS rule and `Map all users to admin`; do not weaken access to the whole LAN. |
| one node works and another fails | Per-node firewall/VLAN/ACL difference | Fix the failed node specifically; do not configure Longhorn until all three pass. |

## Stage 3 — Configure Longhorn's default BackupTarget

The script creates or updates only `longhorn-system/BackupTarget/default`. It uses no Secret and sends no NAS credential over the Kubernetes API. It refuses to replace a non-empty existing target unless `--replace-default` is supplied.

Review it:

```bash
sed -n '1,280p' scripts/configure-longhorn-synology-nfs-backup-target.sh
```

The non-live manifest reference is available at:

```text
kubernetes/infrastructure/longhorn/backup-target-synology-nfs.yaml.template
```

Do not apply the template directly; it intentionally contains placeholders. Use the guarded script after the node probe passes:

```bash
./scripts/configure-longhorn-synology-nfs-backup-target.sh --server <synology-ip-or-dns> --export /volume1/longhorn-backups --confirm
```

If `default` already points to another non-empty target, inspect the existing non-secret metadata first:

```bash
kubectl get backuptargets.longhorn.io default -n longhorn-system -o json | jq '{target: .spec.backupTargetURL, credentialSecret: .spec.credentialSecret, pollInterval: .spec.pollInterval, available: .status.available, conditions: .status.conditions}'
```

Only after confirming that replacing it is intended, run:

```bash
./scripts/configure-longhorn-synology-nfs-backup-target.sh --server <synology-ip-or-dns> --export /volume1/longhorn-backups --confirm --replace-default
```

Expected result:

```text
[PASS] BackupTarget/default is available.
```

The script records non-secret previous/requested/status metadata under ignored `artifacts/longhorn-nfs-target/`. If it reports failure, it deliberately does not overwrite the target again or attempt an automatic rollback. Inspect the report, target status, and Longhorn manager logs instead:

```bash
kubectl describe backuptargets.longhorn.io default -n longhorn-system
```

```bash
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=200
```

## Stage 4 — Prove backup and restore

Only after `BackupTarget/default` reports `available: true`, run the isolated rehearsal:

```bash
./scripts/rehearse-longhorn-backup-restore.sh --confirm --cleanup
```

A pass proves the complete path:

```text
new Longhorn PVC -> full backup on Synology NFS -> new restored PVC -> checksum match
```

Review the result and timing evidence:

```bash
find artifacts/longhorn-rehearsal -name result.txt -print -exec cat {} \;
```

The test does not overwrite an existing application PVC. It is the prerequisite for later application-specific recovery tests for Grafana, Prometheus, Loki, Alertmanager, Garmin InfluxDB, and Ring VictoriaMetrics.

## Recovery, rollback, and maintenance

### If target configuration must be rolled back

The configuration script records previous non-secret target metadata before changing a non-empty target. Restore the prior endpoint through the Longhorn UI or run the script again with the prior server/export values and `--replace-default`. Do not invent or copy a previous credential Secret value; NFS must use an empty credential secret.

### If the NAS is unavailable

```text
Do not delete Longhorn volumes, PVCs, snapshots, or BackupTarget resources.
Do not enable Argo CD pruning.
Inspect NAS availability, DSM NFS service, firewall, export ACLs, and node network reachability.
Wait for BackupTarget/default to return available: true before retrying a backup.
```

### Retention and second copy

Longhorn controls deletion of individual backup objects and incremental chains. Keep Longhorn's own backup retention as the authoritative lifecycle. If you add Synology Snapshot Replication, Hyper Backup, immutable snapshots, or a second NAS/cloud copy, apply it to the dedicated share as a secondary copy and test recovery separately. Never assume a NAS replication job proves that Longhorn can restore a volume.

## Files added for deferred Synology setup

```text
ansible/playbooks/prepare-longhorn-synology-nfs.yml
  Installs NFS client packages and, only with explicit inputs, probes every node.

scripts/configure-longhorn-synology-nfs-backup-target.sh
  Safely configures Longhorn BackupTarget/default after NFS validation.

kubernetes/infrastructure/longhorn/backup-target-synology-nfs.yaml.template
  Human-review template; intentionally not directly applicable.

scripts/rehearse-longhorn-backup-restore.sh
  Existing isolated end-to-end backup/restore proof after target setup.
```

## Completion checklist

```text
[ ] Synology has a dedicated longhorn-backups share.
[ ] NFSv4.1 is enabled on the NAS.
[ ] Only 192.168.178.80, .81, .82, .83, and .84 have read/write NFS access.
[ ] NFS client/probe passes on every K3s node.
[ ] Longhorn BackupTarget/default reports available: true.
[ ] The isolated backup/restore script returns [PASS].
[ ] Result evidence and observed RTO are recorded.
[ ] Stateful Argo CD pruning remains disabled until workload-specific restores are tested.
[ ] A separate NAS/off-site recovery copy is planned and tested.
```
