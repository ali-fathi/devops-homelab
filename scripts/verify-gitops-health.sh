#!/usr/bin/env bash
#
# verify-gitops-health.sh — Read-only post-sync health gate
#
# Verifies the GitOps control plane and essential homelab workloads after an
# Argo CD synchronization. It never applies, syncs, patches, deletes, restarts,
# or prints Secret values. A non-zero exit code means at least one check failed.

set -uo pipefail

readonly APPS=(
  homelab-applications
  kube-vip
  monitoring
  loki
  alloy
  observability-config
  garmin
  ring-health-tracker
  health-dashboard
)

readonly POD_NAMESPACES=(argocd monitoring logging garmin ring-health health)

readonly PVC_NAMESPACES=(monitoring logging garmin ring-health)

readonly SERVICES=(
  "monitoring/monitoring-grafana"
  "monitoring/monitoring-kube-prometheus-prometheus"
  "monitoring/monitoring-kube-prometheus-alertmanager"
  "logging/loki"
  "logging/loki-gateway"
  "logging/alloy"
  "garmin/garmin-influxdb"
  "ring-health/victoriametrics"
  "health/health-dashboard"
)

checks=0
failures=0
warnings=0

pass() {
  checks=$((checks + 1))
  printf '[OK] %s\n' "$1"
}

fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf '[FAIL] %s\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf '[WARN] %s\n' "$1"
}

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "required command available: $1"
    return 0
  fi

  fail "required command is unavailable: $1"
  return 1
}

check_application() {
  local app="$1"
  local sync_status health_status

  if ! kubectl -n argocd get application "$app" >/dev/null 2>&1; then
    fail "Argo CD Application/$app is missing from namespace argocd"
    return
  fi

  sync_status=$(kubectl -n argocd get application "$app" -o json | jq -r '.status.sync.status // "Unknown"')
  health_status=$(kubectl -n argocd get application "$app" -o json | jq -r '.status.health.status // "Unknown"')

  if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
    pass "Application/$app is Synced and Healthy"
  else
    fail "Application/$app is sync=$sync_status health=$health_status"
  fi
}

check_pods() {
  local namespace="$1"
  local bad_pods pod_count

  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    fail "namespace/$namespace is missing"
    return
  fi

  pod_count=$(kubectl -n "$namespace" get pods -o json | jq '.items | length')
  if [[ "$pod_count" == "0" ]]; then
    warn "namespace/$namespace has no Pods to verify"
    return
  fi

  bad_pods=$(kubectl -n "$namespace" get pods -o json | jq -r '
    .items[]
    | select(
        .status.phase != "Succeeded"
        and (
          .status.phase != "Running"
          or ([.status.containerStatuses[]? | select(.ready != true)] | length > 0)
        )
      )
    | "\(.metadata.name) phase=\(.status.phase // "Unknown")"
  ')

  if [[ -z "$bad_pods" ]]; then
    pass "all non-completed Pods in namespace/$namespace are Running and Ready"
  else
    fail "unready Pods in namespace/$namespace: $(tr '\n' ';' <<<"$bad_pods")"
  fi
}

check_pvcs() {
  local namespace="$1"
  local bad_pvcs pvc_count

  pvc_count=$(kubectl -n "$namespace" get pvc -o json | jq '.items | length')
  if [[ "$pvc_count" == "0" ]]; then
    pass "namespace/$namespace has no PVCs"
    return
  fi

  bad_pvcs=$(kubectl -n "$namespace" get pvc -o json | jq -r '.items[] | select(.status.phase != "Bound") | "\(.metadata.name) phase=\(.status.phase // "Unknown")"')

  if [[ -z "$bad_pvcs" ]]; then
    pass "all PVCs in namespace/$namespace are Bound"
  else
    fail "unbound PVCs in namespace/$namespace: $(tr '\n' ';' <<<"$bad_pvcs")"
  fi
}

check_service_endpoints() {
  local reference="$1"
  local namespace="${reference%%/*}"
  local service="${reference#*/}"
  local endpoint_count

  if ! kubectl -n "$namespace" get service "$service" >/dev/null 2>&1; then
    fail "Service/$service is missing from namespace/$namespace"
    return
  fi

  endpoint_count=$(kubectl -n "$namespace" get endpointslices.discovery.k8s.io -l "kubernetes.io/service-name=$service" -o json | jq '[.items[]?.endpoints[]? | select(.conditions.ready != false) | .addresses[]?] | length')
  if (( endpoint_count > 0 )); then
    pass "Service/$service in namespace/$namespace has $endpoint_count ready EndpointSlice address(es)"
  else
    fail "Service/$service in namespace/$namespace has no ready EndpointSlice addresses"
  fi
}

check_external_secrets() {
  local bad_external_secrets count

  if ! kubectl get crd externalsecrets.external-secrets.io >/dev/null 2>&1; then
    warn "ExternalSecret CRD is unavailable; skipping secret synchronization checks"
    return
  fi

  count=$(kubectl get externalsecret -A -o json | jq '.items | length')
  if [[ "$count" == "0" ]]; then
    warn "no ExternalSecrets found"
    return
  fi

  bad_external_secrets=$(kubectl get externalsecret -A -o json | jq -r '
    .items[]
    | select((.status.conditions // [] | map(select(.type == "Ready" and .status == "True")) | length) == 0)
    | "\(.metadata.namespace)/\(.metadata.name)"
  ')

  if [[ -z "$bad_external_secrets" ]]; then
    pass "all $count ExternalSecret resource(s) report Ready=True"
  else
    fail "ExternalSecrets without Ready=True: $(tr '\n' ';' <<<"$bad_external_secrets")"
  fi
}

check_prometheus_resource() {
  local kind="$1"
  local name="$2"
  local available

  if ! kubectl -n monitoring get "$kind" "$name" >/dev/null 2>&1; then
    fail "$kind/$name is missing from namespace/monitoring"
    return
  fi

  available=$(kubectl -n monitoring get "$kind" "$name" -o json | jq -r '.status.availableReplicas // 0')
  if (( available >= 1 )); then
    pass "$kind/$name reports $available available replica(s)"
  else
    fail "$kind/$name reports no available replicas"
  fi
}

check_statefulset() {
  local namespace="$1"
  local name="$2"
  local ready

  if ! kubectl -n "$namespace" get statefulset "$name" >/dev/null 2>&1; then
    fail "StatefulSet/$name is missing from namespace/$namespace"
    return
  fi

  ready=$(kubectl -n "$namespace" get statefulset "$name" -o json | jq -r '.status.readyReplicas // 0')
  if (( ready >= 1 )); then
    pass "StatefulSet/$name in namespace/$namespace reports $ready ready replica(s)"
  else
    fail "StatefulSet/$name in namespace/$namespace reports no ready replicas"
  fi
}

check_daemonset() {
  local namespace="$1"
  local name="$2"
  local desired available

  if ! kubectl -n "$namespace" get daemonset "$name" >/dev/null 2>&1; then
    fail "DaemonSet/$name is missing from namespace/$namespace"
    return
  fi

  desired=$(kubectl -n "$namespace" get daemonset "$name" -o json | jq -r '.status.desiredNumberScheduled // 0')
  available=$(kubectl -n "$namespace" get daemonset "$name" -o json | jq -r '.status.numberAvailable // 0')
  if (( desired > 0 && desired == available )); then
    pass "DaemonSet/$name in namespace/$namespace is available on all $desired scheduled node(s)"
  else
    fail "DaemonSet/$name in namespace/$namespace desired=$desired available=$available"
  fi
}

main() {
  printf '%s\n' '=== Homelab GitOps post-sync health gate ==='
  printf '%s\n' 'Read-only: no resources will be changed.'
  printf '\n%s\n' '--- Prerequisites ---'

  if ! require_command kubectl || ! require_command jq; then
    printf '\n%s\n' 'Cannot run health checks until required commands are installed.'
    exit 2
  fi

  if kubectl get nodes >/dev/null 2>&1; then
    pass "Kubernetes API is reachable (context: $(kubectl config current-context 2>/dev/null || echo unknown))"
  else
    fail 'Kubernetes API is not reachable with the active kubeconfig/context'
    exit 2
  fi

  printf '\n%s\n' '--- Argo CD Application status ---'
  for app in "${APPS[@]}"; do
    check_application "$app"
  done

  printf '\n%s\n' '--- Pod readiness ---'
  for namespace in "${POD_NAMESPACES[@]}"; do
    check_pods "$namespace"
  done

  printf '\n%s\n' '--- PersistentVolumeClaim status ---'
  for namespace in "${PVC_NAMESPACES[@]}"; do
    check_pvcs "$namespace"
  done

  printf '\n%s\n' '--- Service endpoints ---'
  for service in "${SERVICES[@]}"; do
    check_service_endpoints "$service"
  done

  printf '\n%s\n' '--- External Secrets ---'
  check_external_secrets

  printf '\n%s\n' '--- Control-plane networking ---'
  check_daemonset kube-system kube-vip-ds

  printf '\n%s\n' '--- Observability resources ---'
  check_prometheus_resource prometheus monitoring-kube-prometheus-prometheus
  check_prometheus_resource alertmanager monitoring-kube-prometheus-alertmanager
  check_statefulset logging loki
  check_daemonset logging alloy

  printf '\n=== Summary ===\n'
  printf 'Checks: %s | Failures: %s | Warnings: %s\n' "$checks" "$failures" "$warnings"

  if (( failures > 0 )); then
    printf '%s\n' 'GitOps health gate FAILED. Inspect the [FAIL] lines and follow the linked runbook.'
    exit 1
  fi

  printf '%s\n' 'GitOps health gate PASSED.'
}

main "$@"
