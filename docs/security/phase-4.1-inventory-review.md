# Phase 4.1 Live Inventory Review

> **Collection:** 2026-08-14
>
> **Initial report ID:** `20260814143740-27325`
>
> **Expanded report ID:** `20260814144328-31798` (regular, init, and ephemeral containers)
>
> **Status:** Live inventory captured. Privileged-access and exposure/RBAC review remains in progress; do not enforce Kyverno or broad NetworkPolicies yet.

## Collected baseline

The read-only collector completed successfully twice against Kubernetes context `default`. The expanded second run includes regular, init, and ephemeral containers. Its full redacted workstation evidence remains outside Git under:

```text
artifacts/platform-security-baseline/20260814144328-31798/
```

The first report did not include init/ephemeral containers. Do not compare its container totals directly to the expanded report.

| Measure | Observed value | Interpretation |
|---|---:|---|
| Namespaces | 13 | Classify each namespace as platform, application, stateful, or temporary. |
| Running/observed Pods | 65 | Inventory includes live Pod security context; rerun before enforcement because Pods change. |
| Externally exposed Services | 6 | Every LoadBalancer/NodePort/external-IP Service needs owner and exposure classification. |
| NetworkPolicies | 4 | Existing policy count is not proof of enforcement or sufficient segmentation. |
| ClusterRoles | 93 | Expected with Kubernetes/controllers; review high-risk wildcard/binding paths rather than treating count as a finding. |
| Containers missing requests or limits, expanded run | 74 | Union of containers missing at least one resource setting; prioritize by namespace and workload criticality. |
| Largest resource-governance groups | Longhorn 37, monitoring 15, logging 8 | Mostly platform/chart-managed workloads; review chart values before changing resource settings. |
| Application-level resource gap | Garmin 2 | Small, low-blast-radius candidate for the first workload-specific remediation. |
| Detected CNI Pods | 0 | Inconclusive. K3s can run network components as integrated processes; a disposable allow/deny test is required before relying on NetworkPolicy. |

## Externally exposed Service classification

All six exposures are MetalLB `LoadBalancer` Services. A LoadBalancer IP is LAN exposure, not automatic internet exposure, but it is still a security boundary. The corresponding NodePorts may also be reachable on K3s node addresses; later network/firewall design must account for both paths.

| Service | LAN IP | Classification | Required action before segmentation/enforcement |
|---|---|---|---|
| `argocd/argocd-server` | `192.168.178.213` | Required administration endpoint | Keep private to approved operators; verify TLS, Argo CD authentication, and anonymous-access settings. |
| `health/health-dashboard` | `192.168.178.216` | Required internal health-data endpoint | Confirm intended users and authentication/privacy controls; do not treat health data as a public demo. |
| `kube-system/traefik` | `192.168.178.210` | Needs investigation | Repository documentation describes Traefik as incomplete while direct MetalLB Services are used. Confirm active routes; remove/restrict this exposure if it has no approved use. |
| `longhorn-system/longhorn-frontend-lb` | `192.168.178.211` | High-value administration endpoint | Longhorn UI changes storage operations. Restrict to approved operators and decide on authenticated ingress/private access before broader policy work. |
| `monitoring/grafana-lb` | `192.168.178.212` | Required observability administration endpoint | Verify TLS, Grafana authentication, and disabled anonymous access; restrict LAN/operator access. |
| `ring-health/victoriametrics` | `192.168.178.214` | High-priority needs investigation | Direct metrics API exposure can disclose or accept telemetry. Confirm a documented external client; otherwise migrate to `ClusterIP` and use authenticated/private access. |

No Service should be removed or changed directly from this table. Each outcome becomes a Git-reviewed manifest change after functional dependencies and rollback are established.

## Observed platform exceptions

The first inventory found host access and added Linux capabilities in platform namespaces only. These are expected candidates for exact future policy exceptions, not automatically approved permanent exceptions.

| Component | Observed behavior | Initial assessment | Required follow-up |
|---|---|---|---|
| MetalLB speaker | Three Pods use `hostNetwork`; speaker adds `NET_RAW` | Expected for Layer 2 advertisements | Confirm chart/version and create an exact Kyverno exception after audit policy exists. |
| Prometheus node exporter | Three Pods use `hostNetwork` and host paths (`proc`, `sys`, `root`) | Expected for node-level host metrics | Restrict to the generated node-exporter workload; verify read-only mounts and chart security settings. |
| Longhorn | CSI, manager, engine-image, and instance-manager Pods use host paths; Longhorn engine/CSI/manager Pods are privileged; CSI adds `SYS_ADMIN` | Expected class of storage-driver requirement, but highest local node-escape blast radius | Verify against Longhorn 1.12.0 documentation, scope exact policy exceptions, retain separate upgrade/restore testing. |
| CoreDNS | Adds `NET_BIND_SERVICE` | Expected to bind DNS service port | Exact platform exception if policy requires drop-all capabilities. |

No application namespace privilege, host networking, host paths, or added capability was shown in this summary. That conclusion must be rechecked from `pods.json` before policy enforcement because the summary is not a long-term source of truth.

## Wildcard RBAC binding review

The expanded inventory maps every wildcard ClusterRole to a named Kubernetes user, ServiceAccount, or administrator group. The result is not an unauthorized-user finding, but wildcard access remains a review signal rather than a permanent approval.

| Classification | Observed bindings | Decision / follow-up |
|---|---|---|
| Expected control-plane identities | `k3s-cloud-controller-manager`, `kube-apiserver`, `system:kube-controller-manager`, and Kubernetes controller ServiceAccounts | Retain. They are cluster control-plane identities; verify their access only during K3s upgrade/architecture review. |
| Expected installed-controller identities | Argo CD application controller/server, Longhorn service account, MetalLB speaker, Prometheus Operator, and local-path provisioner | Retain pending vendor version/purpose evidence. Scope Kyverno policy exceptions to workloads, not these RBAC bindings. |
| Administrator boundary | `system:masters` is bound to `cluster-admin` | Expected Kubernetes administrative group. Keep kubeconfig/operator access restricted; do not add users or ServiceAccounts to this group. |
| High-priority investigation | `kube-system/helm-traefik` and `kube-system/helm-traefik-crd` ServiceAccounts each bind to `cluster-admin` | Initial evidence confirms K3s-bundled Traefik/CRD charts at `39.0.7`, completed Helm install Jobs, and enabled token automount. The identities are not in a currently running Pod, but remain relevant for reconciliation/upgrades. Determine whether K3s requires/recreates the bindings before narrowing or deleting them. |
| High-priority investigation | `longhorn-system/longhorn-support-bundle` ServiceAccount binds to `cluster-admin` | Initial evidence found no support-bundle Job and `automountServiceAccountToken` unset, which inherits the Kubernetes default when a Pod is created. Treat it as an on-demand vendor workflow; do not run it, remove the binding, or alter token behavior before checking Longhorn version-specific support-bundle behavior. |

Safe follow-up commands that do not print Secret values or mutate the cluster:

```bash
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.serviceAccountName == "helm-traefik" or .spec.serviceAccountName == "helm-traefik-crd" or .spec.serviceAccountName == "longhorn-support-bundle") | "\(.metadata.namespace)/\(.metadata.name) serviceAccount=\(.spec.serviceAccountName) phase=\(.status.phase)"'
```

```bash
kubectl get helmchart -n kube-system -o json | jq '[.items[] | select(.metadata.name == "traefik" or .metadata.name == "traefik-crd") | {name: .metadata.name, chart: .spec.chart, version: .spec.version, repo: .spec.repo, targetNamespace: .spec.targetNamespace}]'
```

```bash
kubectl get serviceaccount -n kube-system helm-traefik helm-traefik-crd -o json | jq '[.items[] | {namespace: .metadata.namespace, name: .metadata.name, automountServiceAccountToken: .automountServiceAccountToken}]' && kubectl get serviceaccount -n longhorn-system longhorn-support-bundle -o json | jq '[.items[] | {namespace: .metadata.namespace, name: .metadata.name, automountServiceAccountToken: .automountServiceAccountToken}]'
```

## Application resource-governance finding

The expanded inventory identified two Garmin containers without resource settings:

```text
garmin-fetch-data regular container: no requests or limits
garmin-influxdb init-influxdb-permissions: no requests or limits
```

The InfluxDB main container already has requests and limits. The init container deliberately runs as UID 0 to initialize Longhorn PVC ownership; it is a candidate for a future exact policy exception, not a reason to exempt the namespace. The Garmin fetch image is currently referenced with `:latest`, which is a separate Phase 4.5 supply-chain finding.

A `kubectl top` point-in-time observation on 2026-08-14 measured the fetcher at `0m` CPU and `73Mi` memory; InfluxDB measured `2m` CPU and `101Mi` memory. The Git-managed initial remediation adds fetcher requests of `25m`/`128Mi` and limits of `250m`/`256Mi`. Observe a successful scheduled Garmin fetch after Argo CD reconciliation; raise values only from evidence, through Git.

The one-shot ownership init remains without resource settings for now. Updating the `garmin-influxdb` Deployment template would trigger its `Recreate` strategy and restart the stateful InfluxDB Pod. Defer that non-urgent change until the Synology Longhorn restore rehearsal succeeds and a stateful maintenance window is approved.

## Security interpretation

```text
Expected vendor privilege is not the same as safe-by-default application access.
Longhorn and node-level monitoring are intentionally powerful platform components.
Application workloads should not inherit their exceptions.
Kyverno must begin in Audit mode and target application namespaces first.
NetworkPolicy must be proven with a disposable connectivity test before deployment.
```

The Longhorn results reinforce the Phase 3 decision to defer stateful pruning until the Synology restore rehearsal passes. Storage components require privileged node integration and must have a tested recovery path before major policy or upgrade changes.

## Required review commands

Classify the six externally exposed Services:

```bash
jq . artifacts/platform-security-baseline/20260814144328-31798/services.json
```

Group containers missing resource requests or limits by namespace:

```bash
jq '[.[] | . as $pod | $pod.containers[] | select((.resourceRequests | length) == 0 or (.resourceLimits | length) == 0) | $pod.namespace] | sort | group_by(.) | map({namespace: .[0], containers: length})' artifacts/platform-security-baseline/20260814144328-31798/pods.json
```

List containers that may run as root or do not explicitly set non-root execution:

```bash
jq -r '.[] | . as $pod | $pod.containers[] | select(.runAsNonRoot != true) | "\($pod.namespace)/\($pod.name) \(.containerType):\(.name) runAsNonRoot=\(.runAsNonRoot) runAsUser=\(.runAsUser)"' artifacts/platform-security-baseline/20260814144328-31798/pods.json
```

Review NetworkPolicy coverage without printing Secret data:

```bash
jq . artifacts/platform-security-baseline/20260814144328-31798/networkpolicies.json
```

Map wildcard ClusterRoles to their bound subjects before classifying them as expected controller access or an actionable issue:

```bash
jq --slurpfile roles artifacts/platform-security-baseline/20260814144328-31798/clusterroles.json '[ $roles[0][] | select(any(.rules[]?; ((.verbs | index("*")) != null) or ((.resources | index("*")) != null) or ((.apiGroups | index("*")) != null))) | .name ] as $wildcards | .[] | select(.roleRef.kind == "ClusterRole") | .roleRef.name as $role | select($wildcards | index($role)) | {binding: .name, role: $role, subjects: .subjects}' artifacts/platform-security-baseline/20260814144328-31798/clusterrolebindings.json
```

## Remaining Phase 4.1 gates

```text
[ ] Classify all six external Services and identify owner/exposure purpose.
[ ] Confirm active use and upstream/K3s purpose of the Traefik Helm and Longhorn support-bundle `cluster-admin` bindings; document retain/narrow/remove decision.
[ ] Group and prioritize missing resource requests/limits.
[ ] Controlled remediation of the K3s embedded NetworkPolicy controller. The 2026-08-14 disposable probe `networkpolicy-probe-20260814151536-16664` proved baseline Pod connectivity but its deny-ingress policy remained reachable for 60 seconds. Root cause is the live master configuration `disable-network-policy: true`; `flannel-backend: host-gw` remains intentional. The flag was a historical response to cross-node connectivity failures, so do not change it until the restore/maintenance gates in `docs/runbooks/k3s-networkpolicy-controller-remediation.md` pass. NetworkPolicy must not protect workloads until a fresh `reachable -> denied -> reachable` test passes. The initial delete request completed after the original 60-second wait; explicit follow-up confirmed no test namespace remained, and a second failed probe completed cleanup successfully.
[ ] Verify Longhorn, MetalLB, node-exporter, and CoreDNS exception scope/version evidence.
[ ] Revisit the InfluxDB ownership-init resource settings after the Synology Longhorn restore rehearsal passes and a stateful maintenance window is approved.
[ ] Add concrete findings, owners, dates, and decisions to docs/security-findings.md.
[ ] Update this review after the above evidence is collected.
```
