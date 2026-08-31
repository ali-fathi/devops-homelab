# Runbook: K3s HA Control-Plane Expansion with Ansible

## Status and execution record

**Implemented and executed on 2026-08-24.** The K3s control plane was expanded
from one embedded-etcd server to three servers through the Kube-VIP API endpoint.

Final observed topology:

| Host | LAN address | Kubernetes roles | K3s version |
|---|---:|---|---|
| `k3s-master` | `192.168.178.80` | `control-plane,etcd` | `v1.35.5+k3s1` |
| `k3s-master2` | `192.168.178.83` | `control-plane,etcd` | `v1.35.5+k3s1` |
| `k3s-master3` | `192.168.178.84` | `control-plane,etcd` | `v1.35.5+k3s1` |
| `k3s-worker1` | `192.168.178.81` | worker | `v1.35.5+k3s1` |
| `k3s-worker2` | `192.168.178.82` | worker | `v1.35.5+k3s1` |

The observed master-two acceptance gates passed before master three was joined:

```text
- k3s-master2 was Ready.
- Kube-VIP Pods were Ready on k3s-master and k3s-master2.
- All seven Longhorn volumes were attached and healthy.
- GitOps health gate at execution time: 35 checks, 0 failures, 0 warnings. The gate now also checks Kube-VIP.
```

After any future expansion or recovery work, repeat the final validation in
[Final cluster acceptance](#final-cluster-acceptance) and record the result.

## Goal, non-goals, and ownership

### Goal

Add one clean Ubuntu host at a time as a K3s **server** to the existing
embedded-etcd cluster without exposing the server token or disrupting the API,
Longhorn, MetalLB, or GitOps workloads.

```text
New server
  -> Ansible host preflight and configuration
  -> Kube-VIP API endpoint (192.168.178.85:6443)
  -> embedded etcd member and control-plane node
  -> Kube-VIP DaemonSet replica on the new server
```

### Non-goals

```text
- Do not deploy Kube-VIP Service LoadBalancer mode; MetalLB owns that role.
- Do not enable the K3s NetworkPolicy controller during a server join.
- Do not change Flannel away from host-gw.
- Do not run cluster-init on a joining server.
- Do not use Terraform to configure Linux hosts or K3s system services.
- Do not directly apply the Kube-VIP manifests with kubectl.
```

### Ownership boundary

| Layer | Owner | Scope |
|---|---|---|
| Linux hosts and K3s server lifecycle | Ansible | SSH user, packages, K3s configuration and installation |
| Kube-VIP Kubernetes resources | Argo CD | ServiceAccount, Role, RoleBinding, DaemonSet |
| Platform/application Kubernetes resources | Terraform or Argo CD | Existing declared ownership boundaries remain unchanged |
| DHCP, Pi-hole, VM provisioning | Operator / infrastructure platform | VIP reservation, DNS, static hosts |

Ansible is the only tool that manages `/etc/rancher/k3s/config.yaml` on joined
servers. The K3s join token is read at runtime from the existing primary server
and is never committed, printed, put in inventory, or supplied as an extra
variable.

## Architecture and required baseline

### API endpoint and DNS

```text
API VIP:       192.168.178.85
DNS name:      k3s-api.home.arpa
API port:      6443
LAN interface: ens18
Kube-VIP mode: ARP, leader election, control-plane-only
```

The VIP must be reserved or excluded from DHCP, must not be allocated by
MetalLB, and must resolve through Pi-hole:

```text
k3s-api.home.arpa -> 192.168.178.85
```

Kube-VIP is deliberately separate from MetalLB:

```text
Kube-VIP -> Kubernetes API control-plane endpoint only
MetalLB  -> Kubernetes Service type LoadBalancer addresses only
```

### K3s networking configuration on every server

The Ansible server template writes the following compatible configuration to
each joining server:

```yaml
server: https://192.168.178.85:6443
token: <runtime-only server token>
node-ip: <the inventory address for this host>
tls-san:
  - k3s-api.home.arpa
  - 192.168.178.85
disable-network-policy: true
flannel-backend: host-gw
disable:
  - servicelb
```

Meanings:

```text
host-gw                 Flannel pod-network backend; direct LAN routing.
hostNetwork             Used by Kube-VIP only, not a Flannel backend.
disable-network-policy  Retains the existing non-enforcing historical baseline.
disable servicelb        Prevents K3s ServiceLB from competing with MetalLB.
```

`disable-network-policy: true` is retained only for configuration consistency
with the current cluster. It does **not** enforce Kubernetes NetworkPolicies.
Its separate risk-gated remediation is documented in
[`k3s-networkpolicy-controller-remediation.md`](k3s-networkpolicy-controller-remediation.md).

## Automation source

| File | Purpose |
|---|---|
| `ansible/inventory/hosts.yml` | Defines primary, future control-plane, worker, and full-cluster groups |
| `ansible/inventory/group_vars/k3s_cluster.yml` | Non-secret baseline: endpoint, version, interface, packages, network settings |
| `ansible/playbooks/bootstrap-ansible-user.yml` | Creates the dedicated `ansible` user and key-based access on a clean host |
| `ansible/playbooks/join-k3s-ha-control-plane.yml` | Audit-only preflight and explicitly confirmed one-server join |
| `ansible/templates/k3s-server-config.yaml.j2` | Root-only K3s server configuration template |
| `scripts/verify-gitops-health.sh` | Read-only platform acceptance gate |

Inventory groups:

```text
k3s_master              Existing k3s-master only; maintenance-sensitive tasks.
k3s_new_control_plane   k3s-master2 and k3s-master3 before/while joining.
k3s_control_plane       Every K3s server after the expansion.
k3s_workers             Existing worker nodes.
k3s_cluster             Every Kubernetes node.
```

### Why group variables live under `inventory/`

Use this exact location:

```text
ansible/inventory/group_vars/k3s_cluster.yml
```

`ansible-playbook` discovers group variables relative to the inventory or
playbook location. Keeping the file in the historical `ansible/group_vars/`
location can make variables visible to ad-hoc `ansible-inventory` commands but
unavailable inside a playbook. The inventory-adjacent location prevents that
inconsistent behavior.

## Security controls

```text
- The automation private key is outside Git at $HOME/.ssh/my_ansible_homelab.
- The bootstrap playbook reads only $HOME/.ssh/my_ansible_homelab.pub.
- /home/ansible/.ssh/authorized_keys is mode 0600.
- /etc/sudoers.d/ansible is mode 0440 and validated with visudo.
- /etc/rancher/k3s/config.yaml is root-owned mode 0600.
- Token-reading, token rendering, and install output use Ansible no_log.
- No password or token is provided through command-line variables.
- Kube-VIP drops all Linux capabilities except NET_ADMIN and NET_RAW.
```

Do not print any of these files:

```text
$HOME/.ssh/my_ansible_homelab
/var/lib/rancher/k3s/server/token
/etc/rancher/k3s/config.yaml
```

## Before starting a join

### 1. Review and merge the automation change

Use the normal feature-branch, pull-request, CI, review, and squash-merge
workflow. Do not run an unreviewed local change against the control plane.

Confirm the effective inventory:

```bash
cd ansible && ansible-inventory --graph
```

Confirm the target host receives the baseline variables:

```bash
cd ansible && ansible-inventory --host k3s-master2 -y
```

Expected values include:

```text
k3s_version: v1.35.5+k3s1
k3s_api_endpoint: https://192.168.178.85:6443
k3s_lan_interface: ens18
k3s_flannel_backend: host-gw
k3s_disable_network_policy: true
```

### 2. Verify Kube-VIP before joining anything

```bash
kubectl -n argocd get application kube-vip
```

Expected:

```text
kube-vip   Synced   Healthy
```

Verify authenticated API access through both VIP forms:

```bash
kubectl --server=https://192.168.178.85:6443 get --raw=/readyz
```

```bash
kubectl --server=https://k3s-api.home.arpa:6443 get --raw=/readyz
```

Expected for both:

```text
ok
```

Verify the VIP owner and DaemonSet:

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip-ds -o wide
```

```bash
ssh master@192.168.178.80 'ip addr show dev ens18 | grep -F 192.168.178.85'
```

The mutation run installs only required packages, including the Longhorn iSCSI
initiator (`open-iscsi` on Debian or `iscsi-initiator-utils` on Red Hat), enables
its `iscsid` service, verifies `iscsiadm -V`, writes a root-only K3s
configuration, installs the pinned K3s version, waits for Node Ready, waits for
the Kube-VIP DaemonSet rollout, and verifies authenticated API readiness through
the VIP.

A plain unauthenticated curl can return `401 Unauthorized`; that still proves
TCP/TLS reached the Kubernetes API. Use the authenticated `kubectl --raw`
checks above as the readiness decision.

### 3. Verify VIP allocation and new-host network paths

```text
[ ] DHCP reserves or excludes 192.168.178.85.
[ ] Pi-hole resolves k3s-api.home.arpa to 192.168.178.85.
[ ] MetalLB's pool excludes the VIP.
[ ] Each new server uses ens18 to route to the VIP.
```

For each candidate server:

```bash
ip route get 192.168.178.85
```

Expected shape:

```text
192.168.178.85 dev ens18 src <candidate LAN address>
```

### 4. Snapshot and protect the datastore

Before each server join, create an embedded-etcd snapshot on an existing
server and copy it to protected off-host/Synology storage.

```bash
sudo k3s etcd-snapshot save --name pre-k3s-server-join-$(date +%Y%m%d-%H%M%S)
```

```bash
sudo k3s etcd-snapshot ls
```

Do not start a join until the off-host copy has been verified. Snapshot warnings
about `cluster-init` in the existing conversion drop-in are benign for the
snapshot command; do not remove the conversion state or etcd data directories.

### 5. Create and verify the automation user

The preferred method is the bootstrap playbook. It requires an existing
administrator account on the new hosts and an Ansible controller that supports
password SSH when `--ask-pass` is used. `sshpass` is required on the controller
for password-based Ansible SSH.

```bash
cd ansible && ansible-playbook playbooks/bootstrap-ansible-user.yml --limit k3s_new_control_plane -e ansible_user=master --ask-pass --ask-become-pass
```

This creates:

```text
User:               ansible
Home:               /home/ansible
Authorized key:     /home/ansible/.ssh/authorized_keys
Sudo policy:        /etc/sudoers.d/ansible
```

If the bootstrap administrator has a forced/custom sudo prompt, Ansible may
time out waiting for its generated sudo prompt even when interactive sudo
works. In that case, bootstrap the account manually over an existing trusted
SSH session, then continue exclusively as `ansible`.

Manual fallback on each new host, after copying the **public** key line from
`$HOME/.ssh/my_ansible_homelab.pub`:

```bash
sudo useradd --create-home --shell /bin/bash ansible
```

```bash
sudo usermod -aG sudo ansible
```

```bash
sudo install -d -m 700 -o ansible -g ansible /home/ansible/.ssh
```

```bash
sudo tee /home/ansible/.ssh/authorized_keys >/dev/null
```

Paste the single public-key line and press `Ctrl+D`, then run:

```bash
sudo chown ansible:ansible /home/ansible/.ssh/authorized_keys && sudo chmod 600 /home/ansible/.ssh/authorized_keys
```

```bash
printf 'ansible ALL=(ALL) NOPASSWD: ALL\n' | sudo tee /etc/sudoers.d/ansible >/dev/null && sudo chmod 440 /etc/sudoers.d/ansible && sudo visudo -cf /etc/sudoers.d/ansible
```

If direct SSH falls back to a password, the public key was not accepted. Install
it through the existing account/password path, then test key-only access:

```bash
ssh-copy-id -i "$HOME/.ssh/my_ansible_homelab.pub" ansible@192.168.178.83
```

```bash
ssh -i "$HOME/.ssh/my_ansible_homelab" -o BatchMode=yes -o StrictHostKeyChecking=no ansible@192.168.178.83 'id ansible && sudo -n true && echo SUDO_OK'
```

Repeat for every new server. `SUDO_OK` and no password prompt are required.
Then verify through Ansible:

```bash
cd ansible && ansible k3s_new_control_plane -m ping
```

## Join procedure

### Step 1: Audit one server without mutation

Never target both future servers together. Start with `k3s-master2`:

```bash
cd ansible && ansible-playbook playbooks/join-k3s-ha-control-plane.yml --limit k3s-master2
```

The preflight checks:

```text
- One-host limit only.
- Existing primary server version matches the pinned target version.
- The candidate has no incompatible K3s agent service.
- Hostname equals the inventory name.
- Static inventory address exists on the host.
- ens18 exists and routes the VIP.
- NTP is synchronized.
- RAM is at least 4096 MiB.
- Root filesystem has at least 20480 MiB free.
- An existing K3s installation, if present, points to the reviewed VIP and node IP.
```

Current behavior: a successful audit prints `Preflight passed` and then exits
non-zero at the explicit confirmation assertion. This is intentional: the
playbook refuses to proceed without `k3s_join_confirm=true`. Treat the prior
successful assertions and the explicit `Preflight passed` message as the
read-only preflight result; no host mutation has occurred.

### Step 2: Join the approved server

Only after preflight review and snapshot/off-host-copy confirmation:

```bash
cd ansible && ansible-playbook playbooks/join-k3s-ha-control-plane.yml --limit k3s-master2 -e k3s_join_confirm=true
```

The confirmed playbook performs these actions in order:

```text
1. Installs ca-certificates, curl, nfs-common, and open-iscsi on Debian.
2. Enables and starts iscsid for Longhorn volume attachment support.
3. Reads the existing K3s server token from k3s-master with no_log.
4. Creates /etc/rancher/k3s and renders root-only config.yaml.
5. Downloads the official installer and installs the pinned K3s server version.
6. Enables and starts the k3s systemd service.
7. Waits for local API readiness.
8. Waits for the new Node Ready condition through k3s-master.
9. Waits for the Kube-VIP DaemonSet rollout.
10. Verifies authenticated API readiness through the VIP from the new server.
```

The playbook joins through:

```text
https://192.168.178.85:6443
```

It never uses `cluster-init` on a joining server.

### Step 3: Accept the first server before the second

Run all of these from the repository checkout. Do not join master three until
they are clean:

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

Acceptance criteria:

```text
- Every Node is Ready.
- The new server has control-plane,etcd roles.
- Kube-VIP has one Ready Pod per current control-plane server.
- Every Longhorn volume is attached and healthy.
- The GitOps health gate reports 0 failures and 0 warnings.
```

### Step 4: Snapshot again and repeat for master three

Create and protect another snapshot after master two passes acceptance:

```bash
sudo k3s etcd-snapshot save --name post-master2-join-$(date +%Y%m%d-%H%M%S)
```

Run the audit-only check for master three:

```bash
cd ansible && ansible-playbook playbooks/join-k3s-ha-control-plane.yml --limit k3s-master3
```

After the same preflight and off-host snapshot gate pass, join it:

```bash
cd ansible && ansible-playbook playbooks/join-k3s-ha-control-plane.yml --limit k3s-master3 -e k3s_join_confirm=true
```

## Final cluster acceptance

After the final server joins, run and record these checks:

```bash
kubectl get nodes -o wide
```

Expected server count:

```text
3 Ready control-plane,etcd servers
```

```bash
kubectl get nodes -l node-role.kubernetes.io/etcd
```

```bash
kubectl -n kube-system get daemonset kube-vip-ds
```

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip-ds -o wide
```

Expected Kube-VIP result:

```text
One Ready Kube-VIP Pod on each of k3s-master, k3s-master2, and k3s-master3.
```

```bash
kubectl --server=https://192.168.178.85:6443 get --raw=/readyz
```

```bash
kubectl --server=https://k3s-api.home.arpa:6443 get --raw=/readyz
```

Both readiness checks must print:

```text
ok
```

```bash
kubectl get volumes.longhorn.io -n longhorn-system -o json | jq '[.items[] | {name: .metadata.name, state: .status.state, robustness: .status.robustness}]'
```

```bash
./scripts/verify-gitops-health.sh
```

Finally, create a post-expansion etcd snapshot and verify its protected off-host
copy:

```bash
sudo k3s etcd-snapshot save --name post-three-server-ha-$(date +%Y%m%d-%H%M%S)
```

## Troubleshooting and safe stop points

| Symptom | Meaning | Safe response |
|---|---|---|
| Bootstrap cannot SSH as `master` | Controller lacks a valid password/key path | Fix only controller SSH authentication; no target mutation occurred |
| `sshpass` required | Password-based Ansible SSH was requested | Install `sshpass` on the controller or use an existing admin key |
| Ansible sudo-prompt timeout | Host custom sudo prompt overrides Ansible's generated prompt | Use the documented manual bootstrap fallback, then operate as `ansible` |
| `ansible` user password prompt | Public key is missing/rejected | Correct `authorized_keys`/ownership or use `ssh-copy-id`; require BatchMode verification |
| K3s variables undefined only in playbook | Group vars are in an invalid discovery location | Use `ansible/inventory/group_vars/k3s_cluster.yml` |
| Preflight fails | Host is not eligible | Correct the failed prerequisite; do not use the confirmation flag |
| Node not Ready after confirmed join | Join, service, network, or critical-config issue | Stop before the next server; collect service/node/VIP evidence |
| Longhorn or GitOps health regresses | Expansion acceptance failed | Stop; do not force-detach volumes, change host-gw, or run destructive cleanup |

Read-only diagnosis commands:

```bash
ansible k3s-master2 -m ping
```

```bash
ansible k3s-master2 -b -m command -a 'systemctl status k3s --no-pager'
```

```bash
kubectl describe node k3s-master2
```

```bash
kubectl -n kube-system logs daemonset/kube-vip-ds --tail=100
```

Do not use these as generic recovery actions:

```text
k3s-killall.sh
k3s-uninstall.sh
manual etcd data deletion
manual deletion of state.db.migrated
Longhorn force detach/delete
iptables or nftables chain flushing
```

A failed or incomplete join requires investigation before any server removal or
etcd-member operation. The direct API endpoint on `k3s-master` remains an
emergency administrative path while Kube-VIP is being investigated.

## Future maintenance guidance

```text
- Add or replace one control-plane server at a time.
- Take and protect an etcd snapshot before every membership change.
- Keep every server's critical K3s flags aligned.
- Upgrade K3s servers one at a time with etcd quorum and Kube-VIP health checks.
- Test Kube-VIP failover only after a fresh snapshot and an approved maintenance window.
- Do not enable the NetworkPolicy controller as part of an HA join.
- Keep MetalLB and Kube-VIP responsibilities separate.
```
