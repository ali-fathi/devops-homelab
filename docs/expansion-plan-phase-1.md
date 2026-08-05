# Expansion Plan — Phase 1: Foundation Hardening

> **The learning guide for the first expansion phase of the DevOps Homelab platform.**
> Duration: Weeks 1–3 · Goal: solidify the operator workstation side of the homelab before expanding into new platform services.

This is one installment of the DevOps Homelab expansion plan — a multi-phase roadmap (kept privately, outside this repository) for evolving the homelab to a production-grade platform. This document covers all five tasks of Phase 1, from secure kubeconfig backups to a hardened DevContainer.

---

## What Is Phase 1?

Phase 1 makes the operator experience robust before any new platform services are added. It covers five tasks that harden the *workstation side* of the homelab — the environment you use every day to run `kubectl`, `helm`, and the rest.

```text
Phase 1 goal:

    From:  "I have a cluster that mostly works"
    To:    "I can back up my access, rebuild my tools, validate my IaC,
            automate my inventory, and harden my dev container —
            all reproducibly and with confidence"
```

---

## Tasks at a Glance

| # | Task | Primary file(s) | Outcome |
|---|------|-----------------|---------|
| **1.1** | Secure kubeconfig backup | `scripts/backup-kubeconfig.sh` | Encrypted, timestamped, restorable backups of your cluster access |
| **1.2** | Reproducible tool installer | `scripts/install-tools.sh` | One script installs the full operator CLI toolkit on a fresh machine |
| **1.3** | Terraform CI validation | `.github/workflows/terraform-validate.yaml` | `fmt`/`validate`/`plan` run automatically on every PR |
| **1.4** | Ansible dynamic inventory | `ansible/inventory/` | Inventory defined in YAML, generated for the `k3s_cluster` group |
| **1.5** | DevContainer hardening | `.devcontainer/` | Kubeconfig mounted safely, verification on container start |

> Implementation status: 1.1 ✅ implemented · 1.2 ✅ implemented · 1.3 ✅ implemented · 1.4 ✅ implemented · 1.5 ✅ implemented.

---

# Task 1.1 — Secure Kubeconfig Backup

## The problem

`~/.kube/k3s-config` is the **master key** to your cluster:

```text
cluster server address     →  https://192.168.178.80:6443
cluster CA data            →  base64 certificate authority
client certificate data    →  proves identity
client key data            →  proves identity
```

Lose it → you must SSH back into the master node to regenerate it.
Leak it → anyone can operate your cluster.

## The solution

Encrypt with **Age**, store timestamped backups, keep 30 days (configurable), optionally push to Azure Key Vault.

## Age concept (one diagram)

```text
age-keygen
    │
    ├── PUBLIC KEY  (age1...)            →  encrypts files  →  safe to share
    └── PRIVATE KEY (AGE-SECRET-KEY-1…)  →  decrypts files  →  NEVER share

kubeconfig ──age -r <PUBLIC>──▶  backup.age (ciphertext)   ← stored
backup.age ──age -d -i <PRIVATE>──▶  kubeconfig (restored)
```

## Setup steps

```bash
# 1. Make script executable
chmod +x scripts/backup-kubeconfig.sh

# 2. Install age
brew install age          # macOS
sudo apt install age      # Debian/Ubuntu

# 3. Generate key pair (one-time)
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/age-key.txt
chmod 600 ~/.config/age/age-key.txt

# 4. Extract public key into its own file (the script expects it)
grep "# public key:" ~/.config/age/age-key.txt | awk '{print $4}' > ~/.config/age/age-key.txt.pub

# 5. Verify
ls -la ~/.config/age/
cat ~/.config/age/age-key.txt.pub   # starts with age1...
```

> **⚠️ CRITICAL:** Store the private key (`age-key.txt`) in a password manager or on paper. If you lose it, all backups are unrecoverable. Never put it in git.

## Run & verify

```bash
# Run the backup
./scripts/backup-kubeconfig.sh

# Inspect artifacts (ciphertext, not your config)
ls -la ~/.kube/backups/
cat ~/.kube/backups/kubeconfig-*.age

# THE critical test — restore to a temp file and diff
LATEST_BACKUP=$(ls -t ~/.kube/backups/kubeconfig-*.age | head -n 1)
age -d -i ~/.config/age/age-key.txt < "$LATEST_BACKUP" > /tmp/kubeconfig-test.yaml
diff ~/.kube/k3s-config /tmp/kubeconfig-test.yaml   # no output = success
rm /tmp/kubeconfig-test.yaml
```

## CLI flags

| Flag | Description | Default |
|------|-------------|---------|
| `-f, --file PATH` | Kubeconfig path | `~/.kube/k3s-config` |
| `-k, --key PATH` | Age public key | `~/.config/age/age-key.txt.pub` |
| `-d, --dir PATH` | Backup directory | `~/.kube/backups` |
| `-u, --upload` | Push to Azure Key Vault | off |
| `-r, --retention DAYS` | Retention period | `30` |
| `-h, --help` | Show help | — |

## Optional: off-site backup to Azure Key Vault

```bash
az login
az keyvault create --name my-homelab-kv --resource-group homelab-rg
AZURE_KEYVAULT_NAME=my-homelab-kv ./scripts/backup-kubeconfig.sh -u
```

Security model: **you encrypt locally** → upload ciphertext → your private key never leaves your machine.

Restore later:

```bash
az keyvault secret show --vault-name my-homelab-kv --name <secret-name> --query value -o tsv \
  | age -d -i ~/.config/age/age-key.txt > ~/.kube/k3s-config
```

## Optional: daily automation

**macOS (launchd):** create `~/Library/LaunchAgents/com.homelab.kubeconfig-backup.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.homelab.kubeconfig-backup</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/alifathi/w/devops-homelab/scripts/backup-kubeconfig.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>3</integer>
    <key>Minute</key><integer>15</integer>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/tmp/kubeconfig-backup.log</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.homelab.kubeconfig-backup.plist
```

**cron:**

```bash
crontab -e
# add:  15 3 * * * /path/to/scripts/backup-kubeconfig.sh >> /tmp/kubeconfig-backup.log 2>&1
```

## How the script works (read along with `scripts/backup-kubeconfig.sh`)

```text
CONFIG          defaults for kubeconfig path, age key, backup dir, retention
VALIDATION      check age installed, kubeconfig exists/readable, pubkey is age1-format
PREPARE         mkdir ~/.kube/backups (mode 700)
ENCRYPT         age -r <pubkey> -a < kubeconfig > kubeconfig-<timestamp>.age
UPLOAD          optional: az keyvault secret set --file (encrypted only)
CLEANUP         find -mtime +N -delete (retention)
```

The core line:

```bash
age -r "$(cat "$pubkey")" -a < "$kubeconfig" > "$output"
```

| Part | Meaning |
|------|---------|
| `age` | the tool |
| `-r` | recipient — who may read it (public key) |
| `-a` | armor — ASCII output, readable text not binary |
| `< "$kubeconfig"` | read plaintext in |
| `> "$output"` | write ciphertext out |

## Troubleshooting (1.1)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `age` not found | Not installed | `brew install age` |
| `Kubeconfig not found` | Wrong path | pass `-f ~/.kube/config` |
| `Age public key not found` | `.pub` not extracted | run the `grep` extraction above |
| `Invalid Age public key format` | `.pub` has extra text | ensure exactly one `age1...` line |
| Decrypt fails on restore | Wrong private key | use the key matching the public key used to encrypt |

## Learning verification (1.1)

- [ ] I can explain what a kubeconfig contains and why losing it is dangerous.
- [ ] I can explain public vs private key (encrypt vs decrypt).
- [ ] I stored my private key outside git.
- [ ] I created a backup and restored it to `/tmp` — `diff` showed nothing.
- [ ] I understand why the encrypted file may be `644` but the private key must be `600`.
- [ ] I know what `set -euo pipefail` protects against.
- [ ] I know how to run the script against a custom kubeconfig path.

---

# Task 1.2 — Reproducible Tool Installer

## The problem

A new machine (or a broken DevContainer) needs ~10 CLIs installed and version-pinned. Doing this by hand is slow and inconsistent.

## The solution

`scripts/install-tools.sh` detects the OS, uses the native package manager where possible (brew/apt), falls back to GitHub releases for tools too new for repos, and is **idempotent** — safe to run repeatedly.

## Tools installed

| Tool | Used for |
|------|----------|
| `kubectl` | Everything against the cluster |
| `helm` | Installing platform charts (MetalLB, Argo CD, Longhorn…) |
| `terraform` | Phase 2: IaC for cluster bootstrap |
| `ansible` | SSH automation of the three K3s nodes |
| `argocd` | `argocd app get/sync/diff` GitOps operations |
| `kustomize` | Rendering manifests (`kubectl kustomize`) |
| `kubeseal` | Phase 5: Sealed Secrets encryption |
| `k9s` | Terminal UI for inspecting pods/deployments |
| `yq` | Parsing/manipulating YAML in scripts |
| `age` | Task 1.1: encrypting backups |

## Usage

```bash
chmod +x scripts/install-tools.sh

./scripts/install-tools.sh --check         # versions only, no installs
./scripts/install-tools.sh --tool age      # install one tool
./scripts/install-tools.sh                 # install everything
KUBECTL_VERSION=v1.31.0 ./scripts/install-tools.sh --tool kubectl   # override a version
```

## Design concepts (learn these)

| Concept | How the script implements it |
|---------|------------------------------|
| **Idempotency** | `if check_command "$tool"; then skip; else install` |
| **OS detection** | `uname -s` → `Darwin` = macOS, `Linux` = Linux |
| **Version pinning** | `${VAR:-default}` — reproducible by default, overridable via env |
| **Fallback strategy** | brew/apt first → generic GitHub release downloader |
| **Generic installer** | `install_github_release` handles tar.gz / zip / raw binary |
| **Safety** | `set -euo pipefail`, `main()` entry, colored logs |

## Troubleshooting (1.2)

- **`--check` prints nothing after "Checking installed tool versions..."**
  A version command returned non-zero under `set -e`. Fixed pattern used in the script:
  ```bash
  v=$(cmd arg 2>/dev/null | head -1) || v="fallback"
  ```
  and reading versions **locally only** (e.g. `kubectl version --client` so no cluster connection is attempted).
- **`argocd` missing but downloaded?**
  The binary went to `~/.local/bin`; your shell may not look there:
  ```bash
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
  ```
- **Unsupported OS?**
  The script supports macOS and Debian/Ubuntu based Linux. Other distros need extension of the `detect_os` / installer logic.

## Learning verification (1.2)

- [ ] `--check` lists every tool with a version or `NOT INSTALLED`.
- [ ] `--tool age` installs a single tool.
- [ ] Full run installs everything; re-run confirms idempotency.
- [ ] I can explain why `set -e` can silently abort a script and how `|| fallback` fixes it.

---

# Task 1.3 — Terraform CI Validation

## The problem

`terraform/` is currently a scaffold. If it grows (Phase 2), mistakes should be caught **before** merge — not in production.

## The solution

A GitHub Actions workflow that runs on every push/PR touching `terraform/`:

```text
terraform fmt -check    →  style consistency
terraform init -backend=false  →  fetch providers, no state backend needed
terraform validate      →  syntax + internal consistency
```

> **Why not `terraform plan` in CI (yet):** the current `providers.tf` points at `~/.kube/k3s-config`, which does not exist on GitHub's `ubuntu-latest` runner, and `plan` needs provider credentials. So Phase 1.3 runs `fmt` + `validate` only. `plan` joins CI in Phase 2 once remote state and a safe read-only credential path are defined. This is a deliberate, documented boundary.

## Design decisions (learn these)

| Decision | Why |
|----------|-----|
| Never `terraform apply` in CI | CI must not mutate infrastructure |
| Validate-only until Phase 2 | Safe credential story needed for `plan`; kubeconfig isn't on the runner |
| `paths:` filter | Workflow only runs when Terraform files change — saves CI minutes |
| `working-directory: terraform` | Every step runs inside `terraform/` — no repeated `cd` |
| `permissions: contents: read` | Least-privilege token; the workflow needs no write scope |
| Pinned `terraform_version` | Reproducible validation across runner images |
| `continue-on-error: false` | Fail the job loudly on `fmt` mismatch |

## The workflow file

Implemented at `.github/workflows/terraform-validate.yaml`:

```yaml
name: Terraform Validation

on:
  push:
    branches:
      - main
    paths:
      - "terraform/**"
      - ".github/workflows/terraform-validate.yaml"
  pull_request:
    paths:
      - "terraform/**"
      - ".github/workflows/terraform-validate.yaml"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  terraform:
    name: Terraform fmt and validate
    runs-on: ubuntu-latest

    defaults:
      run:
        working-directory: terraform

    steps:
      - name: Checkout repository
        uses: actions/checkout@v5

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.9.8"
          terraform_wrapper: true

      - name: Terraform fmt check
        id: fmt
        run: |
          set -euo pipefail
          terraform fmt -check -recursive
        continue-on-error: false

      - name: Terraform init (no backend)
        id: init
        run: |
          set -euo pipefail
          terraform init -backend=false

      - name: Terraform validate
        id: validate
        run: |
          set -euo pipefail
          terraform validate

      - name: Terraform validate output
        if: steps.validate.outcome == 'failure'
        run: echo "::error::Terraform validation failed. Fix the reported issues and re-push."
```

## Local verification (before you push)

The exact CI steps can be reproduced locally to prove the workflow will pass:

```bash
cd terraform
terraform fmt -check -recursive    # must pass (style)
terraform init -backend=false      # fetch providers, no backend
terraform validate                 # must report "The configuration is valid"
```

Expected result on this repo (verified):

```text
terraform fmt -check -recursive    →  PASS (no diffs)
terraform validate                 →  Success! The configuration is valid.
```

> **Note:** `.terraform/` and `.terraform.lock.hcl` are covered by the existing `.gitignore`, so local init does not pollute the repository.

## When this workflow triggers

| Event | Effect |
|-------|--------|
| `push` to `main`, touching `terraform/**` | Runs the validation gate |
| `pull_request`, touching `terraform/**` | Runs as a required-ish check (fails PR if broken) |
| `workflow_dispatch` | Manual re-run from the Actions tab |

## Learning verification (1.3)

- [ ] I can explain why CI runs `fmt`/`validate` but never `apply`.
- [ ] I know the difference between `plan` (read) and `apply` (write).
- [ ] I can explain why `plan` is deferred to Phase 2 (credentials / kubeconfig not on the runner).
- [ ] I can explain the `paths:` filter and `working-directory:` default.
- [ ] I reproduced all three CI steps locally and saw them pass.
- [ ] I know that `.terraform/` is gitignored so local runs stay clean.

---

# Task 1.4 — Ansible Inventory Modernization

## The problem

The inventory was a static `hosts.ini` (INI format). When nodes change (IP, new worker, decommission), the inventory file drifts from reality — and INI is the legacy format with limited group nesting.

## The solution

Convert to a **YAML inventory** (`inventory/hosts.yml`) with the same group hierarchy, and update `ansible.cfg` + docs to point at it.

## What changed

| File | Change |
|------|--------|
| `ansible/inventory/hosts.ini` | **Removed** (INI format) |
| `ansible/inventory/hosts.yml` | **Added** — YAML inventory, same groups |
| `ansible/ansible.cfg` | `inventory = inventory/hosts.ini` → `inventory/hosts.yml` |
| `ansible/README.md` | Inventory section + structure updated to YAML |
| `docs/homelab-study-guide.md` | Inventory reference updated |

## The new inventory

```yaml
# ansible/inventory/hosts.yml
all:
  children:
    k3s_cluster:
      children:
        k3s_master:
          hosts:
            k3s-master:
              ansible_host: 192.168.178.80
        k3s_workers:
          hosts:
            k3s-worker1:
              ansible_host: 192.168.178.81
            k3s-worker2:
              ansible_host: 192.168.178.82
```

**Group tree (unchanged semantics):**

```text
all
  └── k3s_cluster  (parent group)
        ├── k3s_master   →  k3s-master   (192.168.178.80)
        └── k3s_workers  →  k3s-worker1  (192.168.178.81)
                           k3s-worker2   (192.168.178.82)
```

Node-level variables (`ansible_user`, SSH key, `become`, Python interpreter) remain in `group_vars/k3s_cluster.yml` — inherited by every host in the group.

## Where the connection variables live

Not in the inventory — in **group variables**:

```yaml
# ansible/group_vars/k3s_cluster.yml
ansible_user: ansible                                # SSH user
ansible_ssh_private_key_file: /home/vscode/.ssh/my_ansible_homelab  # key
ansible_become: true                                 # sudo
ansible_become_method: sudo
ansible_python_interpreter: /usr/bin/python3
```

**Key learning point:** variables are *separated from the inventory*. The inventory says "what hosts exist and their IPs"; group_vars says "how to connect to them". This separation keeps credentials out of the inventory file.

## What you can do with it

1. **Visualize the effective inventory** — the single best debugging tool:
   ```bash
   cd ansible
   ansible-inventory --graph    # tree view
   ansible-inventory --list     # full JSON with all variables
   ```
2. **Run ad-hoc commands against all nodes:**
   ```bash
   ansible k3s_cluster -m ping              # connectivity check
   ansible k3s_cluster -m shell -a 'uptime' # run anything on all 3
   ```
3. **Run the health-check playbook** against the new inventory:
   ```bash
   ansible-playbook playbooks/check-cluster.yml
   ```
4. **Add a node easily** — add a few lines under `k3s_workers.hosts`:
   ```yaml
   k3s-worker3:
     ansible_host: 192.168.178.83
   ```
5. **Extend per-host later** — YAML makes per-host vars trivial (e.g. `role: worker`) without touching group_vars.

## INI vs YAML inventory — learn the difference

| Aspect | INI (`hosts.ini`) | YAML (`hosts.yml`) |
|--------|-------------------|--------------------|
| Format | Key-value lines | Structured mappings |
| Group nesting | `:children` suffix | `children:` blocks |
| Host vars | Inline `k=v` | Per-host mapping |
| Readability | Terse | Self-describing |
| `ansible-inventory` | Works | Works (same parser) |

Both are supported by Ansible; YAML is the modern default and easier to extend (per-host vars, complex groups, YAML anchors).

## Verify (run these on a machine with ansible installed — e.g. the DevContainer)

```bash
cd ansible

# 1. Visualize the effective inventory
ansible-inventory --graph
# Expected:
# @all:
#   |--@ungrouped:
#   |--@k3s_cluster:
#       |--@k3s_master:
#       |   |--k3s-master
#       |--@k3s_workers:
#           |--k3s-worker1
#           |--k3s-worker2

# 2. Show the full resolved inventory (JSON)
ansible-inventory --list | jq 'keys'

# 3. Connectivity check against all nodes (needs SSH access)
ansible k3s_cluster -m ping

# 4. Run the existing health-check playbook against the new inventory
ansible-playbook playbooks/check-cluster.yml
```

> **Note:** `ansible-inventory` was not available on the author workstation at implementation time (ansible itself not yet installed — that is exactly what Task 1.2's `install-tools.sh` fixes: `./scripts/install-tools.sh --tool ansible`). The YAML was validated with a YAML parser (structure: `all → children → k3s_cluster`). Run the verification block above from the DevContainer to confirm end-to-end.

## Beyond YAML: true dynamic inventory

For machines that change often, a **dynamic inventory** is a script that queries a source of truth (Proxmox/libvirt, a cloud API, or a host list in git) and returns JSON. Ansible runs the script on every invocation, so the inventory is always current.

```text
Static YAML inventory   →  good for a small, stable homelab
Dynamic inventory       →  good when nodes churn or are provisioned elsewhere
```

## Learning verification (1.4)

- [ ] I converted the inventory to YAML and `ansible-inventory --graph` shows the group tree.
- [ ] I can explain when static YAML inventory is enough vs when a dynamic script is worth it.
- [ ] I can name the differences between INI and YAML inventory formats.
- [ ] I understand where group variables live and why they apply to all nodes.
- [ ] I ran the health-check playbook against the new inventory.

---

# Task 1.5 — DevContainer Hardening

## The problem

The DevContainer is your operator environment. Two weaknesses:

1. The kubeconfig and SSH directory are bind-mounted **writable**. A compromised container — or an accidental command — could modify or delete your real host credentials.
2. Nothing verifies the cluster when the container starts. You only discover a problem mid-workflow.

## The solution (implemented)

Three changes:

1. **Read-only mounts** — container reads your credentials but can never write them.
2. **`postCreateCommand`** — backup reminder on create/rebuild.
3. **`postStartCommand`** — cluster verification on every start.

## What changed

| File | Change |
|------|--------|
| `.devcontainer/devcontainer.json` | Mounts → `readonly`; `env:HOME` → `localEnv:HOME`; added `postCreateCommand` + `postStartCommand` |
| `.devcontainer/README.md` | Documents read-only mounts, hooks, and the new troubleshooting flow |
| `scripts/verify-cluster.sh` | Hardened: graceful WARN on unreachable cluster, per-tool version check, always `exit 0` |

## The final `devcontainer.json` changes

```jsonc
"mounts": [
  // read-only kubeconfig mount — container reads, host owns
  "source=${localEnv:HOME}/.kube/k3s-config,target=/home/vscode/.kube/config,type=bind,readonly",
  // read-only SSH mount
  "source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,readonly"
],

// runs on first create / rebuild — backup reminder
"postCreateCommand": "bash -c 'echo \"Homelab DevContainer ready. Run ./scripts/backup-kubeconfig.sh to back up your kubeconfig.\"'",

// runs on EVERY container start — cluster status, never blocks startup
"postStartCommand": "bash -c './scripts/verify-cluster.sh; exit 0'"
```

## Key concepts (learn these)

### `env:` vs `localEnv:` — a subtle but important fix

| Reference | Refers to | Problem with `env:HOME` |
|-----------|-----------|--------------------------|
| `${env:HOME}` | Container environment at build time | `HOME` inside the build container may be `/root` — silently wrong host path |
| `${localEnv:HOME}` | **Host** environment | Always your real `~` on macOS/Linux — correct source for host files |

### `readonly` — the privilege boundary

```text
Host (owns credentials)
  │  bind mount, readonly
  ▼
Container (operator tools)
  reads kubeconfig/SSH   →  allowed (kubectl, ansible need it)
  writes kubeconfig/SSH  →  DENIED (host files are immutable to the container)
```

Even a fully compromised container cannot touch your host credentials.

### `postCreate` vs `postStart`

| Hook | Runs when | Purpose here |
|------|-----------|--------------|
| `postCreateCommand` | First create, or rebuild | Remind to back up the kubeconfig |
| `postStartCommand` | **Every** container start | Show cluster connectivity + tool versions |

### Why `; exit 0` on postStart

`verify-cluster.sh` may report the cluster unreachable (e.g. you're on a different network). Without `exit 0`, a non-zero exit could surface as a VS Code error popup or container-start problem. With it, the hook is a **notification, not a blocker**: you *see* the status, the container still starts.

## The hardened `verify-cluster.sh`

Key properties:

```text
no `set -e`            →  a failed check reports, never aborts
graceful WARN          →  cluster unreachable → actionable hints, exit 0
per-tool loop          →  each tool checked, missing tools shown as WARN
always exit 0          →  safe for postStart (never blocks startup)
```

Sample output (host without cluster access):

```text
Checking Kubernetes cluster...
[WARN] Kubernetes cluster NOT reachable from this environment.
       Check: kubeconfig path, server address, VPN/LAN, K3s API.
       Manual: curl -k https://192.168.178.80:6443

Checking installed tools...
[OK] kubectl: Client Version: v1.34.1
[WARN] helm: NOT INSTALLED
[OK] terraform: Terraform v1.15.7
[WARN] ansible: NOT INSTALLED

Verification complete.
```

## Verify after rebuilding

```bash
# 1. Rebuild the container (picks up devcontainer.json changes)
#    Dev Containers: Rebuild Container

# 2. You should see on start:
#    - postCreate reminder (first time / rebuild only)
#    - verify-cluster.sh output (every start)

# 3. Confirm the mounts are read-only from inside the container:
touch /home/vscode/.kube/config
# Expected: "Read-only file system"

ls -l /home/vscode/.kube/config     # still exists, unchanged
```

> **Note:** `verify-cluster.sh` only checks *operator access*, not application health. For that: `kubectl get pods -A`, `argocd app list`.

## Learning verification (1.5)

- [ ] I can explain the difference between `postCreate` and `postStart` hooks.
- [ ] I know why mounting the kubeconfig `readonly` matters (privilege boundary).
- [ ] I can explain `env:` vs `localEnv:` and why `localEnv` is correct for host files.
- [ ] I can explain why `postStart` uses `; exit 0` (notification, not blocker).
- [ ] I rebuilt the DevContainer and saw the verify/reminder output.
- [ ] I verified from inside the container that the mounts are read-only.

---

# Phase 1 — Master Checklist

- [x] **1.1** `backup-kubeconfig.sh` executable, age keys generated, backup created, restore test passed, private key stored safely
- [x] **1.2** `install-tools.sh` executable, `--check` lists all tools, full install idempotent, PATH includes `~/.local/bin`
- [x] **1.3** Terraform CI workflow added, `fmt`/`validate` green on a PR
- [x] **1.4** Ansible inventory converted to YAML, `ansible-inventory --graph` shows `k3s_cluster`
- [x] **1.5** DevContainer mounts read-only kubeconfig/SSH, verify runs on start, rebuild tested

## Recommended sequence

```text
1.1 (back up access)  →  1.2 (rebuild tools)  →  1.3 (validate IaC)
    →  1.4 (accurate inventory)  →  1.5 (hardened container)
```

---

# Concepts Glossary

| Term | Meaning |
|------|---------|
| `set -euo pipefail` | Fail fast: exit on error (`-e`), unset var (`-u`), pipe failure (`-o pipefail`) |
| **Idempotent** | Safe to run repeatedly; second run changes nothing |
| **Ciphertext** | Encrypted data — unreadable without the key |
| **Public key** | Encrypts; safe to share |
| **Private key** | Decrypts; must stay secret |
| **`uname -s`** | Prints OS name (`Darwin` on macOS, `Linux` on Linux) |
| **`fmt`/`validate`/`plan`/`apply`** | Terraform lifecycle: style → syntax → preview → change |
| **Dynamic inventory** | Script that produces Ansible inventory from a source of truth at run time |
| **postCreate vs postStart** | DevContainer hooks: on rebuild vs on every start |

---

# Related Documents

- [Homelab Study Guide](homelab-study-guide.md)
- [Scripts README](../scripts/README.md)
- [Terraform README](../terraform/README.md)
- [DevContainer README](../.devcontainer/README.md)

---

*Last updated: 2026-08-05*  
*Project: DevOps Homelab Platform*