# Runbook: Add K3s HA Control-Plane Servers with Ansible

## Purpose and ownership

This runbook adds `k3s-master2` and then `k3s-master3` to the embedded-etcd K3s
control plane through the Kube-VIP API endpoint. It deliberately uses Ansible,
not Terraform:

```text
Ansible   -> hosts, SSH automation user, packages, K3s server installation
Terraform -> bootstrap infrastructure APIs
Argo CD   -> Kubernetes platform and application manifests
```

Ansible is the single owner of `/etc/rancher/k3s/config.yaml` on the new
servers. Argo CD owns the Kube-VIP DaemonSet; do not use this runbook to modify
Kube-VIP, MetalLB, Longhorn, or application manifests.

## Safety boundaries

```text
- Join exactly one server per run: master2 first, then master3.
- Do not print, commit, or pass the K3s server token as an extra variable.
- The playbook reads the existing token over Ansible from k3s-master with no_log.
- Kube-VIP must be Synced/Healthy and its authenticated VIP readiness check must pass.
- Preserve host-gw, disable-network-policy: true, and disable: [servicelb].
- Never use cluster-init on a joining server.
- Do not join the second server until the first passes all post-join gates.
```

The current intentionally disabled NetworkPolicy controller is copied to new
servers for cluster configuration consistency. This does **not** enable policy
enforcement. Its separate, gated remediation remains documented in
[`k3s-networkpolicy-controller-remediation.md`](k3s-networkpolicy-controller-remediation.md).

## Files

```text
ansible/inventory/hosts.yml
ansible/inventory/group_vars/k3s_cluster.yml
ansible/playbooks/bootstrap-ansible-user.yml
ansible/playbooks/join-k3s-ha-control-plane.yml
ansible/templates/k3s-server-config.yaml.j2
```

The inventory groups are:

```text
k3s_master              -> existing k3s-master only; maintenance-sensitive
k3s_new_control_plane   -> k3s-master2 and k3s-master3
k3s_control_plane       -> all current/future control-plane servers
k3s_workers             -> existing workers
k3s_cluster             -> every node
```

## Prerequisites

Before any mutation:

```text
[ ] The Kube-VIP API is healthy at https://192.168.178.85:6443.
[ ] DNS k3s-api.home.arpa resolves to 192.168.178.85.
[ ] The VIP is reserved outside DHCP and excluded from MetalLB.
[ ] A fresh embedded-etcd snapshot and its off-host copy exist.
[ ] k3s-master2 and k3s-master3 are clean hosts with static .83/.84 addresses.
[ ] An existing administrator account can SSH to the new hosts and use sudo.
[ ] The Ansible controller has $HOME/.ssh/my_ansible_homelab.pub available.
[ ] The pull request containing this automation has been reviewed and merged.
```

The bootstrap playbook is the only unavoidable initial-access step. It creates
the dedicated `ansible` user, installs the existing controller public key, and
creates a validated passwordless-sudo file. It never handles private keys or
passwords. If the existing administrator requires sudo authentication, Ansible
will prompt locally; do not put a password on the command line.

## 1. Review the effective inventory

From `ansible/`:

```bash
ansible-inventory --graph
```

Expected control-plane shape:

```text
k3s_control_plane
├── k3s-master
├── k3s-master2
└── k3s-master3
```

## 2. Bootstrap the automation user on both new hosts

Use the existing bootstrap administrator only for this command. Replace
`master` only if a different existing administrator account is used:

```bash
ansible-playbook playbooks/bootstrap-ansible-user.yml --limit k3s_new_control_plane -e ansible_user=master --ask-become-pass
```

Verify the permanent automation account without interactive SSH setup:

```bash
ansible k3s_new_control_plane -m ping
```

## 3. Run master2 audit-only preflight

This makes no host changes:

```bash
ansible-playbook playbooks/join-k3s-ha-control-plane.yml --limit k3s-master2
```

It checks the target hostname/address, `ens18` route to the VIP, NTP, memory,
root capacity, existing K3s state, incompatible K3s agent state, and the
existing server version. It also refuses a non-one-server limit.

## 4. Join master2

Only after reviewing the preflight and confirming the off-host snapshot copy:

```bash
ansible-playbook playbooks/join-k3s-ha-control-plane.yml --limit k3s-master2 -e k3s_join_confirm=true
```

The mutation run installs only required packages, enables `iscsid`, writes a
root-only K3s configuration, installs the pinned K3s version, waits for Node
Ready, waits for the Kube-VIP DaemonSet rollout, and verifies authenticated API
readiness through the VIP.

## 5. Required master2 validation

Run from the repository checkout before joining master3:

```bash
kubectl get nodes -o wide
```

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip-ds -o wide
```

```bash
kubectl get volumes.longhorn.io -n longhorn-system -o json | jq '[.items[] | {name: .metadata.name, state: .status.state, robustness: .status.robustness}]'
```

```bash
./scripts/verify-gitops-health.sh
```

All Nodes must be Ready, Kube-VIP must have a Ready Pod on both control-plane
servers, all Longhorn volumes must be `attached` and `healthy`, and the health
gate must have zero failures and warnings.

## 6. Join and validate master3

Repeat the audit and mutation only after master2 validation succeeds:

```bash
ansible-playbook playbooks/join-k3s-ha-control-plane.yml --limit k3s-master3
```

```bash
ansible-playbook playbooks/join-k3s-ha-control-plane.yml --limit k3s-master3 -e k3s_join_confirm=true
```

Then repeat every validation command in step 5 and create a fresh etcd snapshot
with an off-host copy.

## Failure handling

```text
Preflight fails: correct the host and rerun audit-only mode; no K3s change occurred.
Installer/join fails: do not reuse the token manually or run cluster-init; inspect Ansible output.
Node not Ready: stop before master3; inspect K3s service, node conditions, and VIP readiness.
Longhorn/GitOps regression: stop the expansion; do not force-detach resources or alter host-gw.
```

The existing `k3s-master` direct API remains available during a failed join.
Do not remove the new server's K3s state, modify the embedded etcd data, or run
`k3s-killall.sh` as a generic remediation.
