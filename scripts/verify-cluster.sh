#!/bin/bash

echo "Checking Kubernetes cluster..."

kubectl get nodes

echo ""
echo "Checking installed tools..."

kubectl version --client
helm version
terraform version
ansible --version

echo ""
echo "Verification complete."
