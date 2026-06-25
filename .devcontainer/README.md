# DevContainer

This folder contains the development environment used to manage the homelab.

The DevContainer provides a consistent environment across:

- macOS (Apple Silicon)
- Linux x86_64

Installed tools:

- kubectl
- helm
- terraform
- ansible
- git
- kustomize

The DevContainer connects to the remote K3s cluster using a mounted kubeconfig file.
