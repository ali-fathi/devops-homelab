#!/bin/bash
#
# verify-cluster.sh — Operator access verification
#
# Checks that the Kubernetes cluster is reachable and the operator CLI tools
# are installed. This verifies OPERATOR ACCESS, not application health.
# For application health also check: kubectl get pods -A, argocd app list.
#
# Used by the DevContainer postStartCommand to report cluster status on
# every container start.

set -uo pipefail  # no -e: a failed check should report, not abort

echo "Checking Kubernetes cluster..."

# Check kubectl exists first, then try the cluster (fail gracefully)
if command -v kubectl >/dev/null 2>&1; then
  if kubectl get nodes 2>/dev/null; then
    echo ""
    echo "[OK] Kubernetes cluster reachable."
  else
    echo ""
    echo "[WARN] Kubernetes cluster NOT reachable from this environment."
    echo "       Check: kubeconfig path, server address, VPN/LAN, K3s API."
    echo "       Manual: curl -k https://192.168.178.80:6443"
  fi
else
  echo "[WARN] kubectl not installed."
fi

echo ""
echo "Checking installed tools..."

for tool in "kubectl:version --client" "helm:version" "terraform:version" "ansible:--version"; do
  cmd="${tool%%:*}"
  flags="${tool#*:}"
  if command -v "$cmd" >/dev/null 2>&1; then
    v=$("$cmd" $flags 2>/dev/null | head -1)
    echo "[OK] $cmd: $v"
  else
    echo "[WARN] $cmd: NOT INSTALLED"
  fi
done

echo ""
echo "Verification complete."
exit 0
