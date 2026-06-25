#!/bin/bash

echo "Adding Helm repositories..."

helm repo add metallb https://metallb.github.io/metallb
helm repo add longhorn https://charts.longhorn.io
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

echo "Repositories added successfully."
