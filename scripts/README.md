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
