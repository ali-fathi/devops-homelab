# 🤖 Ansible Homelab Management

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
| k3s-master | Control Plane | 192.168.178.80 |
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
| 192.168.178.80 Master    |
| 192.168.178.81 Worker 1  |
| 192.168.178.82 Worker 2  |
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
│   └── hosts.ini
│
├── group_vars/
│   └── k3s_cluster.yml
│
├── playbooks/
│   ├── check-cluster.yml
│   └── check-cluster-detailed.yml
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
for host in 192.168.178.80 192.168.178.81 192.168.178.82; do
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
ansible/inventory/hosts.ini
```

```ini
[k3s_master]
k3s-master ansible_host=192.168.178.80

[k3s_workers]
k3s-worker1 ansible_host=192.168.178.81
k3s-worker2 ansible_host=192.168.178.82

[k3s_cluster:children]
k3s_master
k3s_workers
```

---

## Group Variables

File:

```text
ansible/group_vars/k3s_cluster.yml
```

```yaml
---
ansible_user: ansible

ansible_ssh_private_key_file: /home/vscode/.ssh/my_ansible_homelab

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

inventory = inventory/hosts.ini

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
Connected successfully to k3s-worker1
Connected successfully to k3s-worker2
```

---

# Detailed Health Check

File:

```text
playbooks/check-cluster-detailed.yml
```

Run:

```bash
ansible-playbook playbooks/check-cluster-detailed.yml
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
k3s-master    Ready    control-plane
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
