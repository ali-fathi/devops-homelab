#!/usr/bin/env bash
# Collect a read-only, redacted Kubernetes security baseline.
#
# The report intentionally excludes Secrets, ConfigMaps, Pod environment values,
# annotations, and all raw manifests. It never modifies cluster resources.

set -Eeuo pipefail
umask 077

REPORT_ROOT="${PWD}/artifacts/platform-security-baseline"

usage() {
  cat <<'EOF'
Usage: collect-platform-security-inventory.sh [--report-dir <path>]

Collects a non-secret security inventory from the active Kubernetes context.
The script is read-only: it does not apply, patch, delete, restart, or exec
into cluster resources. Reports are written beneath the ignored artifacts/
directory unless --report-dir is provided.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report-dir)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--report-dir needs a path." >&2; exit 2; }
      REPORT_ROOT="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for command in kubectl jq; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required command not found: $command" >&2; exit 2; }
done

capture() {
  local file="$1"
  local filter="$2"
  shift 2
  kubectl "$@" -o json | jq "$filter" > "${report_dir}/${file}"
}

run_id="$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
report_dir="${REPORT_ROOT}/${run_id}"
mkdir -p "$report_dir"

context="$(kubectl config current-context)"
printf 'run_id=%s\ncollected_at=%s\nkubernetes_context=%s\n' "$run_id" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$context" > "${report_dir}/metadata.txt"

# Metadata, names, security-relevant spec fields, and status only. No
# annotations or `.data` fields are persisted.
capture namespaces.json '[.items[] | {name: .metadata.name, podSecurityLabels: ((.metadata.labels // {}) | with_entries(select(.key | startswith("pod-security.kubernetes.io/"))))}]' get namespaces
capture serviceaccounts.json '[.items[] | {namespace: .metadata.namespace, name: .metadata.name, automountServiceAccountToken: .automountServiceAccountToken}]' get serviceaccounts -A
capture pods.json '
  def summarizeContainer($containerType; $podSecurity):
    . as $container
    | (.securityContext // {}) as $containerSecurity
    | {
        name: .name,
        containerType: $containerType,
        image: (if (.image | contains("@") and (contains("@sha256:") | not)) then "<redacted-image-reference>" else .image end),
        privileged: ($containerSecurity.privileged // false),
        allowPrivilegeEscalation: ($containerSecurity.allowPrivilegeEscalation // null),
        readOnlyRootFilesystem: ($containerSecurity.readOnlyRootFilesystem // null),
        runAsNonRoot: ($containerSecurity.runAsNonRoot // $podSecurity.runAsNonRoot // null),
        runAsUser: ($containerSecurity.runAsUser // $podSecurity.runAsUser // null),
        capabilitiesAdd: ($containerSecurity.capabilities.add // []),
        resourceRequests: (.resources.requests // {}),
        resourceLimits: (.resources.limits // {})
      };
  [.items[]
   | (.spec.securityContext // {}) as $podSecurity
   | {
       namespace: .metadata.namespace,
       name: .metadata.name,
       phase: .status.phase,
       ownerKinds: [.metadata.ownerReferences[]?.kind],
       serviceAccountName: (.spec.serviceAccountName // "default"),
       hostNetwork: (.spec.hostNetwork // false),
       hostPID: (.spec.hostPID // false),
       hostIPC: (.spec.hostIPC // false),
       hostPathVolumes: [.spec.volumes[]? | select(.hostPath != null) | .name],
       containers: (
         ([.spec.initContainers[]? | summarizeContainer("init"; $podSecurity)] +
          [.spec.containers[]? | summarizeContainer("container"; $podSecurity)] +
          [.spec.ephemeralContainers[]? | summarizeContainer("ephemeral"; $podSecurity)])
       )
     }
  ]' get pods -A
capture services.json '
  [.items[]
   | select(.spec.type == "LoadBalancer" or .spec.type == "NodePort" or ((.spec.externalIPs // []) | length > 0))
   | {
       namespace: .metadata.namespace,
       name: .metadata.name,
       type: .spec.type,
       externalIPs: (.spec.externalIPs // []),
       loadBalancerIPs: [.status.loadBalancer.ingress[]? | .ip // .hostname],
       ports: [.spec.ports[]? | {name: .name, port: .port, nodePort: .nodePort, protocol: .protocol}]
     }
  ]' get services -A
capture networkpolicies.json '
  [.items[] | {
    namespace: .metadata.namespace,
    name: .metadata.name,
    podSelector: (.spec.podSelector // {}),
    policyTypes: (.spec.policyTypes // []),
    ingressRuleCount: (.spec.ingress // [] | length),
    egressRuleCount: (.spec.egress // [] | length)
  }]' get networkpolicies -A
capture clusterroles.json '
  [.items[] | {
    name: .metadata.name,
    rules: [(.rules // [])[] | {
      apiGroups: (.apiGroups // []),
      resources: (.resources // []),
      resourceNames: (.resourceNames // []),
      nonResourceURLs: (.nonResourceURLs // []),
      verbs: (.verbs // [])
    }]
  }]' get clusterroles
capture roles.json '
  [.items[] | {
    namespace: .metadata.namespace,
    name: .metadata.name,
    rules: [(.rules // [])[] | {
      apiGroups: (.apiGroups // []),
      resources: (.resources // []),
      resourceNames: (.resourceNames // []),
      verbs: (.verbs // [])
    }]
  }]' get roles -A
capture rolebindings.json '
  [.items[] | {
    namespace: .metadata.namespace,
    name: .metadata.name,
    roleRef: .roleRef,
    subjects: [(.subjects // [])[] | {kind: .kind, name: .name, namespace: .namespace}]
  }]' get rolebindings -A
capture clusterrolebindings.json '
  [.items[] | {
    name: .metadata.name,
    roleRef: .roleRef,
    subjects: [(.subjects // [])[] | {kind: .kind, name: .name, namespace: .namespace}]
  }]' get clusterrolebindings
capture cni-pods.json '
  [.items[] | {
    namespace: .metadata.namespace,
    name: .metadata.name,
    containers: [.spec.containers[]? | {name: .name, image: (if (.image | contains("@") and (contains("@sha256:") | not)) then "<redacted-image-reference>" else .image end)}]
  } | select((.name + " " + ([.containers[].image] | join(" "))) | test("cilium|calico|flannel|kube-router|weave"; "i"))]' get pods -n kube-system

kubectl api-resources --verbs=list --namespaced=true > "${report_dir}/namespaced-api-resources.txt"
kubectl version -o json | jq '{clientVersion: .clientVersion.gitVersion, serverVersion: .serverVersion.gitVersion}' > "${report_dir}/kubernetes-version.json"

jq -n \
  --slurpfile namespaces "${report_dir}/namespaces.json" \
  --slurpfile pods "${report_dir}/pods.json" \
  --slurpfile services "${report_dir}/services.json" \
  --slurpfile policies "${report_dir}/networkpolicies.json" \
  --slurpfile clusterroles "${report_dir}/clusterroles.json" \
  --slurpfile cni "${report_dir}/cni-pods.json" \
  '{
    namespaces: ($namespaces[0] | length),
    pods: ($pods[0] | length),
    externalServices: ($services[0] | length),
    networkPolicies: ($policies[0] | length),
    clusterRoles: ($clusterroles[0] | length),
    hostNetworkPods: ([$pods[0][] | select(.hostNetwork == true) | {namespace, name}] ),
    hostPathPods: ([$pods[0][] | select((.hostPathVolumes | length) > 0) | {namespace, name, hostPathVolumes}] ),
    privilegedContainers: ([$pods[0][] | . as $pod | $pod.containers[] | select(.privileged == true) | {namespace: $pod.namespace, pod: $pod.name, container: .name}] ),
    addedCapabilities: ([$pods[0][] | . as $pod | $pod.containers[] | select((.capabilitiesAdd | length) > 0) | {namespace: $pod.namespace, pod: $pod.name, container: .name, capabilitiesAdd}] ),
    containersWithoutRequests: ([$pods[0][] | . as $pod | $pod.containers[] | select((.resourceRequests | length) == 0) | {namespace: $pod.namespace, pod: $pod.name, container: .name}] | length),
    containersWithoutLimits: ([$pods[0][] | . as $pod | $pod.containers[] | select((.resourceLimits | length) == 0) | {namespace: $pod.namespace, pod: $pod.name, container: .name}] | length),
    detectedCniPods: $cni[0]
  }' > "${report_dir}/summary.json"

cat > "${report_dir}/README.txt" <<EOF
Platform security baseline inventory
====================================

This directory contains redacted metadata and security-context evidence only.
It intentionally excludes Secrets, ConfigMaps, annotations, Pod environment
values, raw manifests, and any command that mutates the cluster.

Review order:
1. summary.json
2. services.json and networkpolicies.json
3. pods.json for privileged/host-network/capability/resource exceptions
4. roles, clusterroles, and bindings for RBAC review
5. cni-pods.json only as discovery evidence; validate policy enforcement with
   the Phase 4.3 disposable connectivity test before enforcing NetworkPolicy.
EOF

echo "[PASS] Read-only platform security inventory collected."
echo "[INFO] Kubernetes context: ${context}"
echo "[INFO] Report directory: ${report_dir}"
echo "[INFO] Review ${report_dir}/summary.json first."
