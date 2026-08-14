#!/usr/bin/env bash
# Prove NetworkPolicy enforcement with an isolated, disposable allow/deny test.
#
# This script is intentionally mutating but creates only a uniquely named test
# namespace and two BusyBox Pods. It deletes that namespace on every exit path.
# It does not inspect Secrets, ConfigMaps, annotations, Pod environments, or
# application workloads.

set -Eeuo pipefail

CONFIRM=false
TIMEOUT_SECONDS=60
CLEANUP_TIMEOUT_SECONDS=180
IMAGE="busybox:1.36"
REPORT_ROOT="${PWD}/artifacts/networkpolicy-enforcement"

usage() {
  cat <<'EOF'
Usage: verify-networkpolicy-enforcement.sh --confirm [--timeout seconds] [--image image] [--report-dir directory]

Creates a unique temporary namespace, verifies baseline Pod-to-Pod HTTP,
adds a deny-all-ingress NetworkPolicy for the test server, verifies that the
request is denied, adds a client-only allow policy, and verifies that the
request succeeds again. The temporary namespace is deleted on success, failure,
or interruption.

Options:
  --confirm              Required acknowledgement that this changes the cluster.
  --timeout <seconds>    Timeout for Pod readiness and each probe state (default: 60).
  --image <reference>    BusyBox-compatible image for both isolated test Pods
                         (default: busybox:1.36).
  --report-dir <path>    Root directory for non-secret local test evidence.
  -h, --help             Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) CONFIRM=true ;;
    --timeout)
      [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || { echo "--timeout needs a positive integer." >&2; exit 2; }
      TIMEOUT_SECONDS="$2"
      shift
      ;;
    --image)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--image needs an image reference." >&2; exit 2; }
      IMAGE="$2"
      shift
      ;;
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

if [[ "$CONFIRM" != true ]]; then
  echo "Refusing to create disposable test resources without --confirm." >&2
  usage >&2
  exit 2
fi

for command in kubectl date; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required command not found: $command" >&2; exit 2; }
done

run_id="$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
namespace="networkpolicy-probe-${run_id}"
server_pod="server"
client_pod="client"
report_dir="${REPORT_ROOT}/${run_id}"
namespace_created=false

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

cleanup() {
  [[ "$namespace_created" == true ]] || return 0

  echo "[INFO] Cleaning up isolated namespace: ${namespace}"
  if ! kubectl delete namespace "$namespace" --wait=true --timeout="${CLEANUP_TIMEOUT_SECONDS}s" >/dev/null; then
    return 1
  fi
  namespace_created=false
  echo "[PASS] Cleanup completed: ${namespace}"
}

on_exit() {
  local original_status=$?
  local cleanup_status=0

  if [[ "$namespace_created" == true ]]; then
    set +e
    cleanup
    cleanup_status=$?
    set -e
    if (( cleanup_status != 0 )); then
      echo "[FAIL] Cleanup could not delete ${namespace} within ${CLEANUP_TIMEOUT_SECONDS}s. The delete request may still be progressing; inspect only that test namespace before rerunning." >&2
      if (( original_status == 0 )); then
        original_status=1
      fi
    fi
  fi

  exit "$original_status"
}
trap on_exit EXIT

for permission in "create namespaces" "delete namespaces"; do
  verb="${permission%% *}"
  resource="${permission##* }"
  [[ "$(kubectl auth can-i "$verb" "$resource" 2>/dev/null)" == "yes" ]] || fail "Current identity cannot ${verb} ${resource}."
done

mkdir -p "$report_dir"
printf 'run_id=%s\nstarted_at=%s\nkubernetes_context=%s\nimage=%s\n' "$run_id" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(kubectl config current-context)" "$IMAGE" > "${report_dir}/metadata.txt"

kubectl create namespace "$namespace" >/dev/null
namespace_created=true

for permission in "create pods" "create networkpolicies" "create pods/exec"; do
  verb="${permission%% *}"
  resource="${permission##* }"
  [[ "$(kubectl auth can-i "$verb" "$resource" -n "$namespace" 2>/dev/null)" == "yes" ]] || fail "Current identity cannot ${verb} in ${namespace}."
done

kubectl run "$server_pod" --namespace "$namespace" --restart=Never --image="$IMAGE" --labels="app=networkpolicy-probe,role=server" --command -- sh -c 'mkdir -p /www && printf ok >/www/index.html && httpd -f -p 8080 -h /www' >/dev/null
kubectl run "$client_pod" --namespace "$namespace" --restart=Never --image="$IMAGE" --labels="app=networkpolicy-probe,role=client" --command -- sh -c 'sleep 600' >/dev/null

kubectl wait --namespace "$namespace" --for=condition=Ready "pod/${server_pod}" --timeout="${TIMEOUT_SECONDS}s" >/dev/null
kubectl wait --namespace "$namespace" --for=condition=Ready "pod/${client_pod}" --timeout="${TIMEOUT_SECONDS}s" >/dev/null
server_ip="$(kubectl get pod "$server_pod" --namespace "$namespace" -o jsonpath='{.status.podIP}')"
[[ -n "$server_ip" ]] || fail "Test server did not receive a Pod IP."

probe_server() {
  kubectl exec --namespace "$namespace" "$client_pod" -- wget -q -T 5 -O /dev/null "http://${server_ip}:8080/" >/dev/null 2>&1
}

wait_for_probe_state() {
  local expected="$1"
  local description="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local actual="unknown"
  local last_progress_seconds=$SECONDS

  echo "[INFO] Waiting up to ${TIMEOUT_SECONDS}s for ${description}: expected ${expected}."
  while (( SECONDS < deadline )); do
    if probe_server; then
      actual="reachable"
    else
      actual="denied"
    fi

    if [[ "$actual" == "$expected" ]]; then
      printf '%s=%s\n' "$description" "$actual" >> "${report_dir}/result.txt"
      echo "[PASS] ${description}: ${actual}"
      return 0
    fi

    if (( SECONDS - last_progress_seconds >= 10 )); then
      echo "[INFO] ${description} is still ${actual}; waiting for policy propagation."
      last_progress_seconds=$SECONDS
    fi
    sleep 2
  done

  if [[ "$description" == "deny_ingress_policy" && "$actual" == "reachable" ]]; then
    fail "Deny ingress policy remained reachable for ${TIMEOUT_SECONDS}s. NetworkPolicy enforcement is absent or misconfigured; do not deploy application NetworkPolicies."
  fi
  fail "${description}: expected ${expected}, observed ${actual} after ${TIMEOUT_SECONDS}s."
}

wait_for_probe_state reachable "baseline_without_policy"

kubectl apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-server-ingress
  namespace: ${namespace}
spec:
  podSelector:
    matchLabels:
      role: server
  policyTypes:
    - Ingress
  ingress: []
EOF

wait_for_probe_state denied "deny_ingress_policy"

kubectl apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-to-server
  namespace: ${namespace}
spec:
  podSelector:
    matchLabels:
      role: server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: client
      ports:
        - protocol: TCP
          port: 8080
EOF

wait_for_probe_state reachable "client_allow_policy"
printf 'completed_at=%s\nresult=pass\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${report_dir}/result.txt"
echo "[PASS] NetworkPolicy ingress enforcement is proven by a disposable allow/deny test."
echo "[INFO] Non-secret report directory: ${report_dir}"
