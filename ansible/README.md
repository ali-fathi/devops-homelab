# 🤖 Ansible Homelab Management

For the repository-wide platform study guide, read:

```text
docs/homelab-study-guide.md
```

This directory contains all Ansible configuration, inventory files, playbooks, and future automation used to manage the K3s homelab environment.

The goal is to manage the entire Kubernetes infrastructure from a single location without manually logging into each server.

This setup follows Ansible and DevOps best practices:

- Dedicated automation user
- SSH key authentication
- Passwordless sudo
- Centralized inventory
- Group variables
- Reusable playbooks
- Infrastructure as Code principles

---

# 🎯 Purpose

This Ansible setup is used to:

- Verify node availability
- Verify SSH connectivity
- Collect system information
- Execute administrative tasks
- Automate infrastructure management
- Prepare for future cluster automation

Future use cases include:

- K3s upgrades
- OS patching
- User management
- Security hardening
- Longhorn maintenance
- Harbor deployment
- ArgoCD deployment
- Monitoring deployment
- Backup automation

---

# 🏗️ Infrastructure

Current Kubernetes cluster:

| Hostname | Role | IP Address |
|-----------|---------|------------|
| k3s-master | Control-plane and etcd server | 192.168.178.80 |
| k3s-master2 | Control-plane and etcd server | 192.168.178.83 |
| k3s-master3 | Control-plane and etcd server | 192.168.178.84 |
| k3s-worker1 | Worker Node | 192.168.178.81 |
| k3s-worker2 | Worker Node | 192.168.178.82 |

---

# 🏗️ Architecture

```text
VS Code
    │
    ▼
DevContainer
    │
    ▼
Ansible
    │
    ▼
SSH Key Authentication
    │
    ▼
+--------------------------+
|      K3s Cluster         |
+--------------------------+
| API VIP .85              |
| .80, .83, .84 Servers    |
| .81, .82 Workers          |
+--------------------------+
```

Ansible runs inside the DevContainer and connects to all nodes using SSH.

No Ansible software is required on the Kubernetes nodes.

Only:

- SSH access
- Python 3
- Sudo privileges

are required.

---

# 📂 Directory Structure

```text
ansible/
│
├── README.md
│
├── ansible.cfg
│
├── inventory/
│   └── hosts.yml
│
├── group_vars/
│   └── k3s_cluster.yml
│
├── playbooks/
│   ├── bootstrap-ansible-user.yml
│   ├── check-cluster.yml
│   ├── configure-k3s-network-policy-controller.yml
│   └── join-k3s-ha-control-plane.yml
│
├── roles/
│
└── group_vars/
```

---

# 🔐 Security Model

This project follows a secure Ansible model.

## ❌ Avoid

Using:

```text
root@server
```

Direct root login should be avoided whenever possible.

---

## ✅ Recommended

Using:

```text
ansible@server
```

with:

- SSH key authentication
- Sudo privileges
- Passwordless sudo

Benefits:

- Better security
- Easier auditing
- Easier key management
- Production-style setup

---

# 🚀 Initial Setup

Perform the following steps once on all cluster nodes.

---

# Step 1 – Create Ansible User

Run on:

- k3s-master
- k3s-master2
- k3s-master3
- k3s-worker1
- k3s-worker2

Create the user:

```bash
sudo useradd -m -s /bin/bash ansible
```

Verify:

```bash
id ansible
```

Example:

```text
uid=1001(ansible) gid=1001(ansible)
```

---

# Step 2 – Add User to Sudo Group

Ubuntu:

```bash
sudo usermod -aG sudo ansible
```

Verify:

```bash
groups ansible
```

Expected:

```text
ansible sudo
```

---

# Step 3 – Configure Passwordless Sudo

Create:

```bash
sudo visudo -f /etc/sudoers.d/ansible
```

Add:

```text
ansible ALL=(ALL) NOPASSWD:ALL
```

Save and exit.

Set permissions:

```bash
sudo chmod 440 /etc/sudoers.d/ansible
```

Verify:

```bash
sudo -l -U ansible
```

---

# Step 4 – Generate SSH Key

On your workstation:

```bash
ssh-keygen \
-t ed25519 \
-f ~/.ssh/my_ansible_homelab \
-C "ansible@homelab"
```

Files created:

```text
~/.ssh/my_ansible_homelab
~/.ssh/my_ansible_homelab.pub
```

---

# Step 5 – Copy SSH Key to All Nodes

Master:

```bash
ssh-copy-id \
-i ~/.ssh/my_ansible_homelab.pub \
ansible@192.168.178.80
```

Control-plane server 2:

```bash
ssh-copy-id \
-i ~/.ssh/my_ansible_homelab.pub \
ansible@192.168.178.83
```

Control-plane server 3:

```bash
ssh-copy-id \
-i ~/.ssh/my_ansible_homelab.pub \
ansible@192.168.178.84
```

Worker 1:

```bash
ssh-copy-id \
-i ~/.ssh/my_ansible_homelab.pub \
ansible@192.168.178.81
```

Worker 2:

```bash
ssh-copy-id \
-i ~/.ssh/my_ansible_homelab.pub \
ansible@192.168.178.82
```

---

## Optional: Copy Key to All Nodes Automatically

```bash
for host in 192.168.178.80 192.168.178.81 192.168.178.82 192.168.178.83 192.168.178.84; do
  ssh-copy-id \
    -i ~/.ssh/my_ansible_homelab.pub \
    ansible@$host
done
```

---

# Step 6 – Verify SSH Access

Test all nodes.

Master:

```bash
ssh -i ~/.ssh/my_ansible_homelab ansible@192.168.178.80
```

Control-plane server 2:

```bash
ssh -i ~/.ssh/my_ansible_homelab ansible@192.168.178.83
```

Control-plane server 3:

```bash
ssh -i ~/.ssh/my_ansible_homelab ansible@192.168.178.84
```

Worker 1:

```bash
ssh -i ~/.ssh/my_ansible_homelab ansible@192.168.178.81
```

Worker 2:

```bash
ssh -i ~/.ssh/my_ansible_homelab ansible@192.168.178.82
```

Expected:

```text
Connected without password prompt
```

---

# Step 7 – Configure SSH Client (Recommended)

Create:

```bash
nano ~/.ssh/config
```

Add:

```text
Host k3s-master
    HostName 192.168.178.80
    User ansible
    IdentityFile ~/.ssh/my_ansible_homelab

Host k3s-master2
    HostName 192.168.178.83
    User ansible
    IdentityFile ~/.ssh/my_ansible_homelab

Host k3s-master3
    HostName 192.168.178.84
    User ansible
    IdentityFile ~/.ssh/my_ansible_homelab

Host k3s-worker1
    HostName 192.168.178.81
    User ansible
    IdentityFile ~/.ssh/my_ansible_homelab

Host k3s-worker2
    HostName 192.168.178.82
    User ansible
    IdentityFile ~/.ssh/my_ansible_homelab
```

Set permissions:

```bash
chmod 600 ~/.ssh/config
```

Verify:

```bash
ssh k3s-master
```

```bash
ssh k3s-master2
```

```bash
ssh k3s-master3
```

```bash
ssh k3s-worker1
```

```bash
ssh k3s-worker2
```

---

# Step 8 – Mount SSH Keys in DevContainer

Update:

```json
"mounts": [
  "source=${env:HOME}/.kube/k3s-config,target=/home/vscode/.kube/config,type=bind",
  "source=${env:HOME}/.ssh,target=/home/vscode/.ssh,type=bind"
]
```

Rebuild the DevContainer:

```text
F1
→ Dev Containers: Rebuild Container
```

---

# Configuration Files

## Inventory

File:

```text
ansible/inventory/hosts.yml
```

```yaml
---
all:
  children:
    k3s_cluster:
      children:
        k3s_control_plane:
          children:
            k3s_master:
              hosts:
                k3s-master:
                  ansible_host: 192.168.178.80
            k3s_new_control_plane:
              hosts:
                k3s-master2:
                  ansible_host: 192.168.178.83
                k3s-master3:
                  ansible_host: 192.168.178.84
        k3s_workers:
          hosts:
            k3s-worker1:
              ansible_host: 192.168.178.81
            k3s-worker2:
              ansible_host: 192.168.178.82
```

Visualize the effective inventory:

```bash
cd ansible
ansible-inventory --graph
ansible-inventory --list
```

---

## Group Variables

File:

```text
ansible/inventory/group_vars/k3s_cluster.yml
```

```yaml
---
ansible_user: ansible

ansible_ssh_private_key_file: "{{ lookup('env', 'HOME') }}/.ssh/my_ansible_homelab"

ansible_become: true

ansible_become_method: sudo

ansible_python_interpreter: /usr/bin/python3
```

---

## Ansible Configuration

File:

```text
ansible/ansible.cfg
```

```ini
[defaults]

inventory = inventory/hosts.yml

host_key_checking = False

interpreter_python = auto_silent

timeout = 30

remote_user = ansible

[privilege_escalation]

become = True
become_method = sudo
```

---

# Verify Inventory

Navigate to the Ansible directory:

```bash
cd ansible
```

Verify inventory:

```bash
ansible-inventory --list
```

Expected:

```text
k3s_master
k3s_workers
k3s_cluster
```

---

# Verify Connectivity

Run:

```bash
ansible k3s_cluster -m ping
```

Expected:

```text
k3s-master | SUCCESS => {
    "ping": "pong"
}

k3s-master2 | SUCCESS => {
    "ping": "pong"
}

k3s-master3 | SUCCESS => {
    "ping": "pong"
}

k3s-worker1 | SUCCESS => {
    "ping": "pong"
}

k3s-worker2 | SUCCESS => {
    "ping": "pong"
}
```

---

# Cluster Connectivity Playbook

File:

```text
playbooks/check-cluster.yml
```

Run:

```bash
ansible-playbook playbooks/check-cluster.yml
```

Purpose:

- Verify SSH connectivity
- Verify node availability
- Display hostname

Example:

```text
Connected successfully to k3s-master
Connected successfully to k3s-master2
Connected successfully to k3s-master3
Connected successfully to k3s-worker1
Connected successfully to k3s-worker2
```

---

# K3s NetworkPolicy Controller

The live K3s server has `disable-network-policy: true`, a historical recovery setting that prevents Kubernetes NetworkPolicy enforcement. The Phase 4 disposable test confirmed it. The controller can affect cross-node traffic, so the opt-in playbook must not be run as a normal maintenance task.

```text
playbooks/configure-k3s-network-policy-controller.yml
```

Default execution is audit-only:

```bash
ansible-playbook playbooks/configure-k3s-network-policy-controller.yml
```

An explicit confirmed enablement restarts every control-plane K3s server sequentially and is permitted only after the runbook preconditions, restore gate, and maintenance approval:

```bash
ansible-playbook playbooks/configure-k3s-network-policy-controller.yml -e k3s_network_policy_confirm=true -e k3s_network_policy_enabled=true
```

Read the complete risk, validation, and rollback procedure first:

```text
docs/runbooks/k3s-networkpolicy-controller-remediation.md
```

# K3s HA Control-Plane Expansion

K3s server installation and host configuration belong to Ansible, not
Terraform. The controlled HA expansion creates the dedicated `ansible` user on
new hosts, configures the K3s server baseline, obtains the existing join token
at runtime without storing it in Git, and joins exactly one server at a time
through Kube-VIP. It preserves `host-gw`, `disable-network-policy: true`, and
K3s ServiceLB disablement; it does not enable NetworkPolicy enforcement.

Read the complete preflight, execution, validation, and rollback procedure:

```text
docs/runbooks/k3s-ha-control-plane-ansible-join.md
```

# Longhorn Synology NFS Backup Preparation

The deferred Longhorn backup setup uses a dedicated Synology NFSv4.1 export. The playbook installs the NFS client package on every K3s node and, when explicitly requested, mounts the export, writes/removes a probe file, and unmounts it. It does not configure Longhorn itself.

Read the NAS and recovery runbook before running it:

```text
docs/runbooks/synology-nfs-longhorn-backup-target-setup.md
```

From `ansible/`, run only after the Synology shared folder, NFSv4.1 service, and per-node export ACL are configured:

```bash
ansible-playbook playbooks/prepare-longhorn-synology-nfs.yml -e longhorn_nfs_confirm=true -e longhorn_nfs_backup_server=192.168.178.120 -e longhorn_nfs_backup_export=/srv/longhorn_backups -e longhorn_nfs_run_probe=true
```

# Longhorn Host Storage Baseline

The Longhorn host baseline is managed explicitly by Ansible. It installs the reviewed iSCSI/NFS prerequisites, keeps `iscsid` enabled, verifies that no multipath maps are active, and disables `multipathd` without rebooting or draining nodes:

```text
ansible/playbooks/manage-longhorn-host-baseline.yml
```

Run it only after reviewing the maintenance impact:

```bash
ansible-playbook playbooks/manage-longhorn-host-baseline.yml -e longhorn_host_baseline_confirm=true
```

# K3s Embedded-etcd NAS Backup

K3s embedded-etcd snapshots contain Kubernetes control-plane state and can contain Kubernetes Secrets. The following playbook installs a root-only systemd service and weekly timer on each control-plane node. At runtime it creates a temporary NFSv4.1 mount to the same reviewed Synology export used by Longhorn, creates a fresh K3s snapshot, copies it into a host-specific `k3s-etcd/<hostname>/` directory, writes a SHA-256 sidecar, removes copies older than 14 days, and unmounts NFS. NFS is never mounted into an application Pod or used as application runtime storage.

The playbook does not reboot or drain nodes. Review the full procedure and recovery boundary in:

```text
docs/runbooks/longhorn-recurring-backup-operations.md
```

Install or reconcile it only with explicit confirmation:

```bash
ansible-playbook playbooks/manage-k3s-etcd-nfs-backup.yml -e k3s_etcd_backup_confirm=true
```

Verify the timers without printing snapshot contents:

```bash
ansible k3s_control_plane -b -m shell -a 'systemctl is-enabled k3s-etcd-nfs-backup.timer && systemctl is-active k3s-etcd-nfs-backup.timer'
```

Run a controlled copy test and verify only checksum sidecars:

```bash
ansible k3s_control_plane -b -m command -a 'systemctl start k3s-etcd-nfs-backup.service'
```

The NAS is the accepted single external backup location for this homelab. Because etcd snapshots contain Secrets, protect the NAS share and any NAS encryption key as administrative credentials; never commit, paste, or print snapshot files.

# Detailed Health Check

The current detailed playbook is:

```text
playbooks/check-cluster.yml
```

Run:

```bash
ansible-playbook playbooks/check-cluster.yml
```

This playbook collects:

- Hostname
- IP Address
- Operating System
- CPU Information
- Memory Information
- Disk Usage

---

# Verify Kubernetes

After Ansible checks succeed:

```bash
kubectl get nodes
```

Expected:

```text
NAME          STATUS   ROLES
k3s-master    Ready    control-plane,etcd
k3s-master2   Ready    control-plane,etcd
k3s-master3   Ready    control-plane,etcd
k3s-worker1   Ready
k3s-worker2   Ready
```

---

# 🔄 Daily Workflow

Open repository:

```bash
code .
```

Start DevContainer:

```text
F1
→ Dev Containers: Reopen in Container
```

Move to Ansible directory:

```bash
cd ansible
```

Verify inventory:

```bash
ansible-inventory --list
```

Verify node connectivity:

```bash
ansible k3s_cluster -m ping
```

Run health check:

```bash
ansible-playbook playbooks/check-cluster.yml
```

Verify Kubernetes:

```bash
kubectl get nodes
```

Start working.

---

# 🔮 Future Automation

Planned automation includes:

- K3s upgrades
- Operating system patching
- User management
- Security hardening
- Longhorn administration
- Harbor deployment
- ArgoCD deployment
- Monitoring deployment
- Backup automation
- Cluster maintenance

---

# ✅ Summary

This Ansible setup provides:

- Dedicated automation user
- SSH key authentication
- Passwordless sudo
- Centralized inventory
- Group variables
- Reusable playbooks
- Production-style infrastructure management

Once configured, the entire K3s cluster can be managed directly from the DevContainer without manually logging into individual nodes.
