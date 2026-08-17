# Homelab Helper Scripts

This directory contains small workstation-side scripts for repeatable operations.

Scripts are helpers, not a replacement for GitOps or documented change management.

For the broad platform guide:

```text
docs/homelab-study-guide.md
```

---

## Scripts

```text
backup-kubeconfig.sh
install-tools.sh
verify-cluster.sh
verify-gitops-health.sh
collect-platform-security-inventory.sh
audit-ci-repository-governance.sh
verify-networkpolicy-enforcement.sh
configure-longhorn-synology-nfs-backup-target.sh
rehearse-longhorn-backup-restore.sh
```

Inspect a script before running it:

```bash
sed -n '1,200p' scripts/<script-name>.sh
```

Make executable when needed:

```bash
chmod +x scripts/<script-name>.sh
```

---

## `backup-kubeconfig.sh`

This file is currently a placeholder and contains no implementation yet. The intended purpose is to create a secure backup of the local Kubernetes configuration.

Kubeconfig contains cluster credentials. Any future implementation must store backups securely and never commit them.

Recommended manual checks:

```bash
ls -l ~/.kube/k3s-config
chmod 600 ~/.kube/k3s-config
```

---

## `install-tools.sh`

This file is currently a placeholder and contains no implementation yet. Its intended purpose is to install or prepare local management tools.

The DevContainer is the preferred tool installation method because it provides a consistent environment. Do not assume this placeholder installs anything.

---

## `verify-gitops-health.sh`

This is the read-only post-sync platform health gate. It checks the root and child Argo CD Applications, Pod readiness, PVC binding, important Service endpoints, ExternalSecret readiness, and core monitoring/logging resources.

Run:

```bash
./scripts/verify-gitops-health.sh
```

The script exits non-zero when a required check fails. It never applies, synchronizes, patches, restarts, or deletes Kubernetes resources, and it never prints Secret values.

Read the full operating procedure and troubleshooting guidance:

```text
docs/runbooks/gitops-post-sync-verification.md
```

---

## `collect-platform-security-inventory.sh`

This is the Phase 4.1 **read-only** security baseline collector. It writes redacted workload security-context, RBAC, network-policy, externally exposed-Service, namespace, and CNI discovery evidence to ignored workstation artifacts. It does not query Secret or ConfigMap data, persist annotations/Pod environment values, or modify cluster resources.

Run:

```bash
./scripts/collect-platform-security-inventory.sh
```

Review `summary.json` first, classify findings, and do not enforce Kyverno or NetworkPolicy controls from an unreviewed inventory. Full procedure:

```text
docs/runbooks/platform-security-baseline.md
```

---

## `audit-ci-repository-governance.sh`

This is the Phase 4.4 **read-only** GitHub Actions and repository-governance baseline collector. It records curated repository/ruleset/Actions-policy metadata and local workflow action references/declared permissions under ignored `artifacts/ci-repository-governance/`. It never reads or prints GitHub Secrets, tokens, or workflow variables, and never changes repository settings, branches, workflows, or cluster resources.

Run:

```bash
./scripts/audit-ci-repository-governance.sh
```

Read the full evidence, review order, and remediation guardrails:

```text
docs/runbooks/ci-repository-governance-audit.md
```

---

## `verify-networkpolicy-enforcement.sh`

This is the Phase 4.1 **confirmation-gated mutating** test for Kubernetes NetworkPolicy enforcement. It creates a unique temporary namespace with two BusyBox Pods, proves Pod-to-Pod HTTP works, proves a deny-ingress policy blocks it, proves a client-only allow policy restores it, and then deletes the namespace on every exit path.

Run only after reading the runbook and confirming the intended Kubernetes context:

```bash
./scripts/verify-networkpolicy-enforcement.sh --confirm
```

It does not touch application resources or print Secret data. A pass proves only the isolated ingress allow/deny behavior; it does not authorize default-deny rollout. Full procedure, evidence, cleanup, and failure handling:

```text
docs/runbooks/networkpolicy-enforcement-test.md
```

---

## `configure-longhorn-synology-nfs-backup-target.sh`

This is an explicit, guarded **mutating** setup helper for a dedicated Synology NFSv4.1 export. It configures only `longhorn-system/BackupTarget/default`, uses no Kubernetes credential Secret, and refuses to replace a non-empty target unless `--replace-default` is supplied.

Run only after DSM NFS permissions and the all-node NFS mount/write probe pass:

```bash
./scripts/configure-longhorn-synology-nfs-backup-target.sh --server <synology-ip-or-dns> --export /volume1/longhorn-backups --confirm
```

Full NAS, node, target, recovery, and maintenance instructions:

```text
docs/runbooks/synology-nfs-longhorn-backup-target-setup.md
```

---

## `rehearse-longhorn-backup-restore.sh`

This is an explicit, opt-in **mutating** Longhorn disaster-recovery rehearsal. It creates a new isolated PVC, writes a non-secret deterministic fixture, creates an external Longhorn backup with the Kubernetes CSI snapshot API, restores a second new PVC, and compares SHA-256 checksums.

It requires an already configured and available external Longhorn `BackupTarget`; it never creates or changes the backup target, its credential Secret, an existing volume, or an application PVC. `--confirm` is required, and `--cleanup` deletes the successful test namespace and its test-only `VolumeSnapshotClass`.

Run:

```bash
./scripts/rehearse-longhorn-backup-restore.sh --confirm --cleanup
```

The script stores non-secret inventory and timing evidence in the ignored `artifacts/longhorn-rehearsal/` directory. It must be run and return `[PASS]` before Task 3.8 is marked verified or stateful GitOps pruning is reconsidered.

Read the full target, safety, cleanup, rollback, and RPO/RTO procedure:

```text
docs/runbooks/longhorn-backup-restore-rehearsal.md
```

---

## `verify-cluster.sh`

The verification script checks:

```text
Kubernetes nodes
kubectl client
Helm
Terraform
Ansible
```

Run:

```bash
./scripts/verify-cluster.sh
```

This verifies operator access, not application health. For application health also check:

```bash
kubectl get pods -A
kubectl get pvc -A
kubectl get svc -A
argocd app list
```

---

## Script safety

Before executing a shell script:

```text
Read it.
Confirm the kubeconfig/context.
Confirm target IPs and namespaces.
Understand whether it changes or deletes resources.
Run with shell tracing only when secrets will not be printed.
```

Use:

```bash
kubectl config current-context
kubectl auth can-i get pods -A
```

Never add passwords or tokens directly to scripts.
