# DevContainer Operator Workstation

The DevContainer is the reproducible management workstation for this homelab.

It runs locally in Docker, but the Kubernetes cluster runs remotely on the K3s nodes.

```text
VS Code
  → DevContainer
  → mounted kubeconfig and SSH keys
  → kubectl / Helm / Ansible / Terraform / Argo CD
  → remote K3s cluster
```

The container is not the Kubernetes cluster. It is an operator environment.

For the repository-wide study guide, read:

```text
docs/homelab-study-guide.md
```

---

## Files

```text
.devcontainer/
├── Dockerfile
├── devcontainer.json
└── README.md
```

`devcontainer.json` defines:

- the image build;
- mounted kubeconfig (**read-only**);
- mounted SSH directory (**read-only**);
- `KUBECONFIG` environment variable;
- VS Code extensions;
- the `vscode` remote user;
- `postCreateCommand` (backup reminder on create/rebuild);
- `postStartCommand` (cluster verification on every start).

`Dockerfile` installs the operator tools.

---

## Installed tools

```text
kubectl       Kubernetes API client
helm          Kubernetes package manager
kustomize     Kubernetes manifest customization
argocd        Argo CD CLI
terraform     Infrastructure as Code
ansible       SSH-based host automation
az            Azure CLI for Key Vault operations
yq            YAML/JSON command-line processing
kubeseal      Sealed Secrets CLI
k9s           Terminal Kubernetes UI
jq            JSON processing
yamllint      YAML linting
```

Check tools inside the container:

```bash
kubectl version --client
helm version
kustomize version
argocd version --client
terraform version
ansible --version
az version
```

---

## Host prerequisites

Install on macOS or Linux:

```text
Docker Desktop or Docker Engine
Visual Studio Code
Dev Containers extension
```

Verify:

```bash
docker --version
code --version
```

---

## Kubeconfig mount

The DevContainer expects:

```text
~/.kube/k3s-config
```

The file is mounted as (**read-only** — the container can read your kubeconfig but never modify or delete it):

```text
/home/vscode/.kube/config
```

The container sets:

```text
KUBECONFIG=/home/vscode/.kube/config
```

Prepare the file on the workstation:

```bash
mkdir -p ~/.kube
chmod 600 ~/.kube/k3s-config
```

The K3s server address must be reachable from the workstation:

```yaml
server: https://192.168.178.80:6443
```

Do not commit kubeconfig files. They contain cluster credentials.

Verify before opening the DevContainer:

```bash
kubectl --kubeconfig ~/.kube/k3s-config get nodes
```

---

## SSH mount

The DevContainer mounts (**read-only** — the container can read your SSH keys but never modify or delete them):

```text
~/.ssh → /home/vscode/.ssh
```

Ansible uses the mounted private key configured in:

```text
ansible/group_vars/k3s_cluster.yml
```

The expected key path inside the container is currently:

```text
/home/vscode/.ssh/my_ansible_homelab
```

Protect private keys:

```bash
chmod 600 ~/.ssh/my_ansible_homelab
chmod 600 ~/.ssh/config
```

---

## Start the environment

1. Open the repository in VS Code:

```bash
cd /path/to/devops-homelab
code .
```

2. Run:

```text
Dev Containers: Reopen in Container
```

3. Verify Kubernetes:

```bash
kubectl get nodes
```

4. Verify SSH/Ansible:

```bash
cd ansible
ansible k3s_cluster -m ping
```

---

## Startup hooks

The DevContainer runs two hooks:

```text
postCreateCommand  →  on first create / rebuild:
                      reminder to run ./scripts/backup-kubeconfig.sh

postStartCommand   →  on EVERY container start:
                      ./scripts/verify-cluster.sh
                      (reports cluster reachability + tool versions)
```

The `postStart` hook exits 0 even when the cluster is unreachable — it is a **notification**, not a startup blocker. If you see `[WARN] Kubernetes cluster NOT reachable`, check:

```text
kubeconfig exists on host          ls -l ~/.kube/k3s-config
server address correct             https://192.168.178.80:6443
VPN/LAN reachable                  ping 192.168.178.80
K3s API running                    curl -k https://192.168.178.80:6443
```

---

## Rebuild the container

Rebuild after changing `.devcontainer/Dockerfile` or `devcontainer.json`:

```text
Dev Containers: Rebuild Container
```

A rebuild downloads tool versions defined by the Dockerfile. Pin important tools when reproducibility is more important than automatically receiving the newest version.

---

## Troubleshooting

### kubeconfig mount fails

Check the source file:

```bash
ls -l ~/.kube/k3s-config
```

Check the container path:

```bash
ls -l /home/vscode/.kube/config
printenv KUBECONFIG
```

### Kubernetes API is unreachable

```bash
ping 192.168.178.80
curl -k https://192.168.178.80:6443
kubectl cluster-info
```

Common causes:

```text
wrong server address
VPN/LAN unavailable
firewall
expired or invalid kubeconfig certificate
K3s API not running
```

### SSH fails

```bash
ssh -i ~/.ssh/my_ansible_homelab ansible@192.168.178.80
ansible k3s_cluster -m ping -vvv
```

Check key permissions, username, sudo, and node IP addresses.

### Docker cannot build the DevContainer

```bash
docker info
docker system df
```

Check Docker Desktop resources and internet access for tool downloads.
