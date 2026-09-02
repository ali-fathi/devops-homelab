# Runbook: Longhorn Weekly Volume and System Backups

## Purpose

This runbook explains the backup policy for the five-node K3s cluster, how the
policy is delivered, what it protects, how to verify it, and how to respond to
failure. It is intentionally separate from the one-time disaster-recovery
rehearsal in [`longhorn-backup-restore-rehearsal.md`](longhorn-backup-restore-rehearsal.md).

The policy has two independent Longhorn recurring jobs:

```text
Sunday 01:00  -> back up every Longhorn volume to the external NFS BackupTarget
Sunday 01:30  -> back up Longhorn's system configuration and storage metadata
Retention     -> keep two completed backups in each job
```

The two retained backups represent approximately two weekly recovery points.
They are not a two-calendar-week guarantee if a scheduled run fails. Monitor
freshness and investigate failures before the next scheduled run.

## Recovery design

```text
                    Git repository / Argo CD
                   manifests and configuration
                              |
                              v
+----------------+     +-------------+     +-----------------------------+
| K3s workloads  | --> | Longhorn    | --> | Synology NFS backup target   |
| PVC data       |     | snapshots   |     | 192.168.178.120:/srv/...     |
+----------------+     +-------------+     +-----------------------------+
                              |
                              +--> volume backups: application bytes
                              +--> system backup: Longhorn resources/settings

Azure Key Vault --> External Secrets Operator --> runtime Kubernetes Secrets
```

Longhorn is the owner of volume data backups and their retention. Argo CD/Git
is the owner of declarative Kubernetes configuration. Azure Key Vault is the
owner of secret values. Keeping these ownership boundaries avoids pretending
that one backup mechanism can restore every layer of the platform.

## Protected scope

### Volume data

All seven current Longhorn volumes are assigned to the `default` recurring-job
group. This currently covers:

| Namespace | PVC/data |
|---|---|
| `garmin` | InfluxDB data |
| `garmin` | Garmin token/cache data |
| `logging` | Loki data |
| `monitoring` | Alertmanager data |
| `monitoring` | Grafana data |
| `monitoring` | Prometheus data |
| `ring-health` | VictoriaMetrics data |

The group is selected by the volume label:

```text
recurring-job-group.longhorn.io/default=enabled
```

Do not select volumes by hard-coded PVC names in the recurring job. The group
makes newly-created Longhorn volumes eligible when they receive the same
standard label, while the health gate detects any current volume that is not
covered.

### Longhorn system configuration

The system-backup job uploads a Longhorn system backup bundle to the default
BackupTarget. Longhorn documents the bundle as including Longhorn-operated:

```text
BackingImages, ClusterRoles, ClusterRoleBindings, ConfigMaps, CRDs,
DaemonSets, Deployments, EngineImages, PersistentVolumes, PersistentVolumeClaims,
RecurringJobs, Roles, RoleBindings, Settings, Services, ServiceAccounts,
StorageClasses, and Volumes.
```

This is why the system backup protects Longhorn Settings and recurring-job
configuration in addition to the volume data. The system backup does not back
up Kubernetes `Nodes`, arbitrary application resources, application Secret
values, or the contents of the Git repository.

The scheduled system job uses:

```text
volume-backup-policy: if-not-present
```

This allows Longhorn to create a current volume backup when one is absent or
outdated while creating the system bundle. The dedicated volume job remains the
clear, authoritative weekly data-backup schedule.

## Source-controlled configuration

The complete desired state is in:

```text
kubernetes/infrastructure/longhorn/config/backup-target.yaml
kubernetes/infrastructure/longhorn/config/settings.yaml
kubernetes/infrastructure/longhorn/config/recurringjob-weekly-volume-backup.yaml
kubernetes/infrastructure/longhorn/config/recurringjob-weekly-system-backup.yaml
kubernetes/gitops/argocd/applications/longhorn-config.yaml
```

Argo CD Application `longhorn-config` watches that directory and applies it to
namespace `longhorn-system`. Its automated policy is self-heal enabled and
prune disabled. The old manually-created `2week` job was removed after both
new jobs became Healthy and Synced.

The two manifests deliberately use different times:

```yaml
# volume data
cron: "0 1 * * SUN"
task: backup
retain: 2
groups:
  - default

# Longhorn system state
cron: "30 1 * * SUN"
task: system-backup
retain: 2
parameters:
  volume-backup-policy: if-not-present
```

The cron expression is interpreted by Longhorn's recurring-job controller. Use
the cluster's documented controller timezone when changing it; the operational
records for this cluster use UTC.

## External BackupTarget

The active target is a dedicated Synology NFSv4.1 export:

```text
nfs://192.168.178.120:/srv/longhorn_backups
```

Only the five K3s node addresses are allowed by the NAS export ACL:

```text
192.168.178.80
192.168.178.81
192.168.178.82
192.168.178.83
192.168.178.84
```

The target uses no Kubernetes credential Secret. The NAS export ACL and network
controls provide access control. NFS is used only as the external backup and
restore target; it is not mounted as an application runtime filesystem.

Before relying on a run, check status without printing any Secret data:

```bash
kubectl -n longhorn-system get backuptarget.longhorn.io default -o json \
  | jq '{available: .status.available, lastSyncedAt: .status.lastSyncedAt}'
```

Expected:

```text
available: true
```

If the target is unavailable, do not delete Longhorn volumes, backups, or
BackupTarget resources. Check the NAS NFS service, export path, ACL, firewall,
node reachability, and Longhorn manager logs.

## Installation and change procedure

Use the normal reviewed workflow. Do not make the recurring-job manifests a
one-off `kubectl apply` configuration:

```text
feature branch
  -> pull request
  -> YAML/schema/security checks
  -> review
  -> squash merge to main
  -> Argo CD sync
  -> read-only health gate
```

After a merge, wait for the `longhorn-config` Application to become `Synced`
and `Healthy`, then inspect the jobs:

```bash
kubectl -n argocd get application longhorn-config \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

kubectl -n longhorn-system get recurringjobs.longhorn.io \
  -o custom-columns='NAME:.metadata.name,TASK:.spec.task,CRON:.spec.cron,RETAIN:.spec.retain,CONCURRENCY:.spec.concurrency,GROUPS:.spec.groups'
```

Expected jobs:

```text
weekly-volume-backup-2week   backup         0 1 * * SUN    2   1   [default]
weekly-system-backup-2week   system-backup   30 1 * * SUN   2   1   []
```

If a legacy `2week` job is found, do not leave both schedules active. Confirm
the two GitOps jobs are healthy, then remove only the obsolete recurring-job
object. Removing a recurring-job object does not delete existing volume data:

```bash
kubectl -n longhorn-system delete recurringjob.longhorn.io 2week
```

Record that manual migration in the change review. Do not delete volumes,
replicas, snapshots, or backup objects as part of this migration.

## Verification commands

The standard read-only gate checks the backup policy as well as workloads:

```bash
./scripts/verify-gitops-health.sh
```

The Longhorn section must report:

```text
BackupTarget/default is configured and available
weekly volume backup is scheduled for the default group with retain=2
weekly system backup is scheduled with retain=2 and if-not-present policy
all current Longhorn volumes are assigned to the default backup group
obsolete manually-created 2week job is absent
```

Inspect volume coverage without displaying data or secrets:

```bash
kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns='VOLUME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,BACKUP-GROUP:.metadata.labels.recurring-job-group\\.longhorn\\.io/default'
```

Inspect completed backup state:

```bash
kubectl -n longhorn-system get backupvolumes.longhorn.io \
  -o custom-columns='BACKUP-VOLUME:.metadata.name,LAST-BACKUP:.status.lastBackupName,LAST-BACKUP-AT:.status.lastBackupAt'

kubectl -n longhorn-system get backups.longhorn.io \
  -o custom-columns='BACKUP:.metadata.name,STATE:.status.state,TARGET:.spec.backupTargetName,CREATED:.metadata.creationTimestamp'
```

Inspect system backups:

```bash
kubectl -n longhorn-system get systembackups.longhorn.io \
  -o custom-columns='NAME:.metadata.name,VERSION:.status.version,STATE:.status.state,SYNCED:.status.lastSyncedAt'
```

Do not treat the presence of a `Backup` object as proof of recoverability. The
backup must be in a completed/ready state on the external target, and the
restore rehearsal must pass.

## Testing strategy

### Policy and schedule test

The health gate validates the exact production task, cron, retention, group,
and target fields. A separate short-lived recurring job was executed during
the rollout against the `default` group. It reached `executionCount=1` and was
then deleted. This tests the controller path without leaving a second
production schedule behind.

A schedule test does not wait for Sunday. It proves the controller accepts the
job and can execute it; it does not replace an end-to-end restore test.

### System-backup test

A temporary `SystemBackup` with `volumeBackupPolicy: disabled` was created,
waited to `Ready`, and deleted after verification. This proved that Longhorn
could upload a system configuration bundle without forcing a large set of
volume backups during the policy rollout.

The production system recurring job uses `if-not-present`, as documented above.

### End-to-end restore test

Run the isolated rehearsal after target or CSI changes:

```bash
./scripts/rehearse-longhorn-backup-restore.sh --confirm --cleanup
```

The recorded baseline passed on 2026-09-01:

```text
SHA-256: 8bf45156cd7a49bd3dbfd166e6a76184feb0f76dc5e3183e39e5524021c7a03c
Backup duration: 11 seconds
Observed restore RTO: 77 seconds
Evidence: artifacts/longhorn-rehearsal/20260901151703-11241/result.txt
```

The fixture result is evidence for the backup path, not an application-specific
RTO. The application restore drill is implemented by
`scripts/rehearse-application-restores.sh`. It restores the newest completed
backup for every current stateful application PVC into a separate namespace,
uses one Longhorn replica to limit capacity, mounts each restored volume
read-only, runs a workload-specific filesystem validation, records the source
backup and elapsed restore time, and removes only its temporary resources when
`--cleanup` is used.

The full seven-volume drill passed on 2026-09-02:

```text
Run: artifacts/application-restore-drills/20260902095006-11538
Grafana: passed, 72s
Alertmanager: passed, 39s
Loki: passed, 138s
Prometheus: passed, 381s
Garmin InfluxDB: passed, 73s
Garmin tokens/cache: passed, 39s
VictoriaMetrics: passed, 40s
```

These are isolated data/filesystem restore results. They do not stop or
reconfigure production workloads. A future deeper drill may start each
application against its restored PVC and run database-native consistency and
query checks during a maintenance window.

## What is backed up elsewhere

| Critical item | Protection | Recovery source |
|---|---|---|
| Application PVC bytes | Weekly Longhorn volume backup, retain 2 | Synology NFS BackupTarget |
| Longhorn Settings and storage metadata | Weekly Longhorn system backup, retain 2 | Longhorn system backup on default target |
| Kubernetes and Argo CD manifests | Git history and Argo CD | Reviewed Git branch/merge history |
| Alerting and workload secret values | Azure Key Vault and External Secrets definitions | Key Vault plus Git manifests |
| Operator kubeconfig | Encrypted workstation backup procedure | `scripts/backup-kubeconfig.sh`, age key kept separately |
| K3s embedded-etcd state | Weekly Ansible-managed snapshot copy | Synology NFS `k3s-etcd/<control-plane>/` directories |

Longhorn system backup does not make a full cluster backup. In particular, it
does not include Kubernetes Nodes or external systems such as the NAS, GitHub,
Azure Key Vault, or the operator workstation. The K3s etcd gap is addressed for
this homelab by the Ansible-managed service and timer described below. The NAS
is intentionally the single external backup location; a second copy is not
part of this homelab's current risk acceptance.

## K3s etcd snapshot export

K3s embedded-etcd snapshots contain Kubernetes control-plane state and may
contain Kubernetes Secret data. They are therefore copied only to the restricted
NAS export and must not be printed, committed, or exposed to application Pods.
The Ansible playbook installs a temporary NFSv4.1 mount, creates a fresh K3s
snapshot, copies it into a host-specific NAS directory, writes a checksum sidecar,
removes files older than 14 days, unmounts NFS, and enables a systemd timer.
NFS is never configured as an application runtime mount.

Install or reconcile the host configuration from `ansible/`:

```bash
ansible-playbook playbooks/manage-k3s-etcd-nfs-backup.yml \
  -e k3s_etcd_backup_confirm=true
```

The timer runs Sunday at 02:30 with a random delay of up to 15 minutes, after
the Longhorn volume and system backup windows. It runs independently on all
three control-plane nodes, so the NAS contains a snapshot copy from each
embedded-etcd member:

```text
/srv/longhorn_backups/k3s-etcd/k3s-master/
/srv/longhorn_backups/k3s-etcd/k3s-master2/
/srv/longhorn_backups/k3s-etcd/k3s-master3/
```

Verify only filenames and checksums:

```bash
ansible k3s_control_plane -b -m shell -a \
  'systemctl is-enabled k3s-etcd-nfs-backup.timer && systemctl is-active k3s-etcd-nfs-backup.timer'
```

A manual test run can be performed during an approved maintenance window:

```bash
ansible k3s_control_plane -b -m command -a \
  'systemctl start k3s-etcd-nfs-backup.service'
```

Then mount the export temporarily and run `sha256sum -c` against the `.sha256`
sidecars. Never copy or display the snapshot contents. K3s etcd restore is a
control-plane operation and must be rehearsed on an isolated cluster or under
the K3s restore procedure; it does not restore Longhorn volume bytes.

## Backup freshness and failure alerts

Prometheus scrapes the Longhorn backend through the GitOps-managed
`ServiceMonitor` in `kubernetes/observability/config/prometheusrules/longhorn-backup-monitoring.yaml`.
The alert rules use Longhorn's documented backup metrics and the existing
warning/critical Telegram route:

```text
LonghornBackupMetricsMissing              scrape unavailable for 15 minutes
LonghornBackupTargetScrapeFailed          backend target down for 15 minutes
LonghornBackupTargetUnavailable           BackupTarget status unavailable for 15 minutes
LonghornSystemBackupStale                 no Ready system backup for 10 days
LonghornSystemBackupFailed                system backup Error for 5 minutes
LonghornVolumeBackupStale                  last backup older than 8 days
LonghornVolumeBackupCriticallyStale        last backup older than 10 days
LonghornBackupFailed                       backup reports error/unknown for 5 minutes
LonghornBackupStuck                        pending/in-progress for 2 hours
```

The freshness warning is intentionally eight days rather than exactly seven:
it allows for the Sunday schedule, controller delay, and a short NAS outage.
The ten-day critical threshold leaves recovery time before the two-week policy
is exhausted. Backup failure and telemetry loss are critical because they
remove confidence in the recovery point.

Validate alert ingestion without displaying credentials:

```bash
kubectl -n monitoring get servicemonitor longhorn-backend
kubectl -n monitoring get prometheusrule longhorn-backup-alerts
```

The rollout test confirmed five healthy Longhorn scrape targets, all backup
metrics present, no active freshness/failure alerts after the current backups,
and a temporary critical alert reached both Prometheus and Alertmanager before
being removed.

### Telegram delivery

Alertmanager receives Prometheus alerts after their configured `for` period.
Alerts labeled `severity=warning` or `severity=critical` are grouped by alert
name and severity, wait one minute for grouping, and are sent to the Telegram
receiver. Messages include the alert name, severity, summary, description,
workload/volume context where available, and the runbook link. A resolved
message is sent when the condition clears; repeated firing alerts are limited
to one notification per 24 hours. `Watchdog` and unclassified alerts are not
sent.

The bot token and chat ID are mounted from the Azure Key Vault-backed
`telegram-alerts` Secret. Confirm the integration without printing credentials:

```bash
kubectl -n monitoring get secret telegram-alerts
kubectl -n monitoring get secret alertmanager-monitoring-kube-prometheus-alertmanager \\
  -o jsonpath='{.data.alertmanager\\.yaml}' | base64 -d | grep -E \\
  'receiver:|send_resolved|severity=~'
```

### Grafana dashboard

Open Grafana and select **Homelab / Homelab - Cluster Health & Recovery**.
The dashboard refreshes every 30 seconds and includes:

```text
Ready nodes, firing/pending alert names and labels, critical alert count,
unavailable deployments, non-ready pods, Bound PVCs, BackupTarget status,
system-backup age and state, oldest volume-backup age, healthy Longhorn volumes,
node CPU/memory, Longhorn disk usage, and backup-age trends.
```

Its GitOps source is
`kubernetes/observability/monitoring/dashboards/custom/homelab-cluster-health.json`
and its automatically provisioned ConfigMap is
`kubernetes/observability/config/homelab-cluster-health-dashboard.yaml`.

## Failure response

### BackupTarget unavailable

1. Stop manual backup retries.
2. Check the NAS service, export path, ACL, firewall, and node routes.
3. Confirm `BackupTarget/default` returns `available=true`.
4. Check Longhorn manager events/logs without displaying Secrets.
5. Run the isolated rehearsal after recovery if the outage could have affected
   backup integrity.

### Recurring job reports an error

1. Capture the job name, schedule, and non-secret status.
2. Check Longhorn recurring-job events and failed job history.
3. Check volume attachment and robustness; do not force-detach healthy volumes.
4. Check free space on the NAS and Longhorn disks.
5. Correct the root cause, wait for the target to be available, and perform a
   controlled test run.
6. Verify that the retained backup count and latest backup timestamps recover.

### NAS capacity or retention issue

Longhorn owns backup-object deletion and incremental-chain lifecycle. Do not
independently delete individual files from the export. For additional NAS
snapshots, Hyper Backup, immutability, or off-site replication, treat that as a
secondary copy and test restoration separately.

## Operational checklist

```text
[ ] BackupTarget/default is available.
[ ] weekly-volume-backup-2week is present: backup, Sunday 01:00, retain 2.
[ ] weekly-system-backup-2week is present: system-backup, Sunday 01:30, retain 2.
[ ] All current Longhorn volumes have the default group label enabled.
[ ] No obsolete 2week recurring job exists.
[ ] Latest backup objects are Completed and visible on the external target.
[ ] Latest system backup is Ready.
[ ] verify-gitops-health.sh reports zero failures and zero warnings.
[ ] The latest restore rehearsal evidence is available.
[ ] NAS capacity and its single-copy risk acceptance are reviewed.
[ ] K3s etcd timer is enabled on all three control-plane nodes.
[ ] Application-specific restore drills have current evidence.
```
