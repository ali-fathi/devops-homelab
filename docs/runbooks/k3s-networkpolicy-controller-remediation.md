# Runbook: K3s Embedded NetworkPolicy Controller Remediation

## Status and decision

On 2026-08-14, the isolated Phase 4.1 probe proved this cluster does **not** enforce NetworkPolicy:

```text
Baseline client -> server: reachable
Deny-ingress policy: remained reachable for 60 seconds
```

The K3s server configuration explains the result:

```yaml
disable-network-policy: true
flannel-backend: host-gw
```

`host-gw` is intentionally retained. The security gap is the disabled embedded K3s NetworkPolicy controller.

K3s provides an embedded controller based on kube-router's NetworkPolicy library; it does not appear as a CNI DaemonSet. K3s disables it with `--disable-network-policy` or `disable-network-policy: true`. Source: [K3s Networking Services](https://docs.k3s.io/networking/networking-services#network-policy-controller).

## Historical risk

The controller was intentionally disabled after a prior cross-node networking incident involving stale/conflicting `KUBE-ROUTER`, `KUBE-NWPLCY`, and `KUBE-POD-FW` iptables/nftables rules. The incident affected worker-to-master DNS and platform webhooks. This history is retained in [K3s Baseline Networking](../k3s-baseline-networking.md).

Therefore this is **not** a one-line production change. Re-enabling the controller may again affect cross-node DNS, Longhorn, MetalLB, and webhook traffic. The Synology Longhorn restore rehearsal is still blocked, so do not perform the control-plane change until a maintenance window is approved and the operator accepts the recovery gap.

## Ownership boundary

```text
Ansible owns the K3s server configuration and service lifecycle.
Terraform does not manage node configuration.
Argo CD does not manage /etc/rancher/k3s/config.yaml.
The NetworkPolicy probe creates only an isolated temporary namespace.
```

The explicit playbook is:

```text
ansible/playbooks/configure-k3s-network-policy-controller.yml
```

It manages only the `disable-network-policy` scalar on the control-plane node. It does not alter Flannel, worker services, CNI software, iptables/nftables state, Kubernetes workloads, or existing NetworkPolicies.

## Preconditions

All conditions must be true before a change:

```text
[ ] Synology Longhorn restore rehearsal has passed, or the operator explicitly accepts the recovery risk.
[ ] A maintenance window is approved; a single control-plane restart briefly interrupts Kubernetes API reconciliation.
[ ] All three Nodes are Ready and no Longhorn volume is degraded/faulted.
[ ] The current configuration and historical cross-node failure are reviewed.
[ ] A rollback operator and the current disabled setting are available.
[ ] No stateful migration, restore, Longhorn upgrade, or Terraform apply is in progress.
[ ] The Ansible playbook has been committed and reviewed.
```

Read-only preflight commands:

```bash
kubectl get nodes && kubectl get volumes.longhorn.io -n longhorn-system -o json | jq '[.items[] | {name: .metadata.name, state: .status.state, robustness: .status.robustness}]'
```

```bash
./scripts/verify-gitops-health.sh
```

Inspect existing kube-router-related rules without printing configuration secrets. Run on all nodes; output is expected to be empty while the controller is disabled, but any output must be reviewed as historical state:

```bash
for host in 192.168.178.80 192.168.178.81 192.168.178.82; do echo "== ${host} =="; ssh -o BatchMode=yes ansible@"${host}" 'sudo iptables-save | grep -E "KUBE-ROUTER|KUBE-NWPLCY|KUBE-POD-FW" || true; sudo ip6tables-save | grep -E "KUBE-ROUTER|KUBE-NWPLCY|KUBE-POD-FW" || true'; done
```

Do not run `k3s-killall.sh`, manually flush iptables/nftables, remove chains, or alter Flannel as part of this initial enablement. Those are outage-level recovery actions, not a policy-controller rollout.

## Audit-only playbook run

This confirms the current non-secret setting without changing the node:

```bash
cd ansible && ansible-playbook playbooks/configure-k3s-network-policy-controller.yml
```

Expected result:

```text
disable-network-policy: true
Audit complete. No change was made.
```

If Ansible is unavailable in the current environment, do not replace it with an unrecorded `ssh` edit. Use the approved DevContainer/automation environment or repair Ansible first.

## Controlled enablement

Only during the approved window, after all preconditions pass:

```bash
cd ansible && ansible-playbook playbooks/configure-k3s-network-policy-controller.yml -e k3s_network_policy_confirm=true -e k3s_network_policy_enabled=true
```

The playbook:

```text
1. Backs up the remote K3s config using Ansible's root-owned backup mechanism.
2. Changes only disable-network-policy to false.
3. Restarts only the k3s server service on k3s-master.
4. Checks the local service and API /readyz endpoint.
5. Does not restart workers, alter host-gw, or clean firewall state.
```

## Required validation

Do not create application policies after the service restart. First run:

```bash
./scripts/verify-gitops-health.sh
```

Then run the only valid NetworkPolicy proof:

```bash
./scripts/verify-networkpolicy-enforcement.sh --confirm
```

Success requires this exact sequence:

```text
reachable -> denied -> reachable
```

Then validate cross-node health before proceeding with Phase 4.3:

```bash
kubectl get nodes -o wide && kubectl get pods -A -o wide && kubectl get volumes.longhorn.io -n longhorn-system -o json | jq '[.items[] | {name: .metadata.name, state: .status.state, robustness: .status.robustness}]'
```

Record the result in:

```text
docs/security/phase-4.1-inventory-review.md
docs/security-findings.md
```

## Rollback

If Node readiness, DNS, webhook, Longhorn, MetalLB, or GitOps health regresses, stop further policy work and restore the controller's prior disabled state through Ansible:

```bash
cd ansible && ansible-playbook playbooks/configure-k3s-network-policy-controller.yml -e k3s_network_policy_confirm=true -e k3s_network_policy_enabled=false
```

Then run the GitOps health gate. K3s documents that disabling the policy controller does not automatically remove existing kube-router policy rules. Do **not** run `k3s-killall.sh` or manually remove iptables/nftables chains as an automatic rollback. Escalate with captured Node, workload, Longhorn, and firewall evidence before any firewall-state cleanup.

## Exit criteria

```text
[ ] K3s configuration is declaratively controlled through the reviewed Ansible playbook.
[ ] The controller is enabled only after preconditions and maintenance approval.
[ ] GitOps health remains healthy after the restart.
[ ] The isolated test passes reachable -> denied -> reachable.
[ ] Cross-node DNS and Longhorn volume health are verified.
[ ] The original NetworkPolicy enforcement finding is resolved with live evidence.
[ ] Application policy design remains audit-first and namespace-scoped.
```
