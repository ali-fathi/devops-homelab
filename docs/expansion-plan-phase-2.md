# Expansion Plan — Phase 2: Infrastructure as Code Maturity

> **The learning guide for the second expansion phase of the DevOps Homelab platform.**
> Duration: Weeks 4–6 · Goal: make Terraform the source of truth for cluster bootstrap infrastructure (MetalLB, Longhorn, Argo CD), with remote state, modules, and CI plan checks.

This is the Phase 2 installment of the DevOps Homelab expansion plan. It walks through all tasks of Phase 2 — from Terraform modules to a `terraform plan` CI gate — with concepts, step-by-step setup, safety guardrails, and learning checklists.

---

## What Is Phase 2?

Phase 1 hardened the operator workstation. Phase 2 moves the **cluster bootstrap infrastructure** into Terraform — the IaC layer — with proper module structure, remote state with locking, and safe adoption of the live MetalLB/Longhorn/Argo CD resources.

```text
Phase 2 goal:

    From:  "MetalLB, Longhorn, Argo CD are applied manually via kubectl/helm"
    To:    "Cluster bootstrap is declared in Terraform, adopted safely,
            versioned, stateful (locked), and validated by CI"
```

---

## Tasks at a Glance

| # | Task | Primary files | Outcome |
|---|------|---------------|---------|
| **2.1** | Define Terraform modules | `terraform/modules/*` | Reusable module structure for all bootstrap components |
| **2.2** | Remote state with locking | `terraform/backend.tf` | Azure Storage backend, blob-lease locking, protected state |
| **2.3** | MetalLB via Terraform | `terraform/metallb.tf` | MetalLB IP pool + L2 advertisement adopted via import |
| **2.4** | Longhorn via Terraform | `terraform/longhorn.tf` | Longhorn chart adopted as `helm_release` |
| **2.5** | Argo CD via Terraform | `terraform/argocd.tf` | AppProject bootstrap; helm take-over deferred (safety) |
| **2.6** | `terraform plan` CI check | `.github/workflows/terraform-validate.yaml` | Plan as PR comment with read-only access |
| **2.7** | Documentation | `docs/expansion-plan-phase-2.md` | This document — records what actually happened |

> Implementation status: 2.1 ✅ implemented · 2.2 ✅ implemented · 2.3 ✅ implemented · 2.4–2.6 🟡 designed (built next) · 2.7 ✅ (this doc).

---

## The Ownership Boundary (the core design)

This answers the repo's explicit warning: *"Do not make Terraform and Argo CD manage the same Kubernetes fields without an ownership plan."*

### The boundary table

| Layer | Owner | Manages | Mechanics |
|-------|-------|---------|-----------|
| **Hosts / OS** | Ansible | SSH users, packages, K3s install | SSH, inventory |
| **Cluster bootstrap** | **Terraform** | MetalLB CRs, Longhorn chart, Argo CD AppProject | `kubernetes_manifest`, `helm_release` |
| **Platform + app manifests** | **Argo CD** | Everything under `kubernetes/applications/**`, observability, Application CRs | `Application` CRs with `prune: false` |
| **Azure (state backend)** | **az CLI (bootstrap) + Terraform (manage)** | Storage account, container | `az` one-time, `azurerm` ongoing |

### The single ownership rule

> **Terraform owns the *cluster's self* (the platform on which everything runs). Argo CD owns everything *running on* the platform. Ansible owns the *metal*.**

Three enforceable sub-rules:

1. **A resource has exactly one owner.** The app Application CRs (garmin, health-dashboard, ring-health-tracker) stay Argo CD-managed; Terraform never touches them.
2. **Never both `helm_release` and an Argo CD app target the same release name.** If adoption happens later, it's a documented *handover*, never both active.
3. **`prune: false` everywhere** until restore is proven — both Argo CD syncPolicy and Terraform's `kubernetes_manifest` with `prune: false`.

---

# Task 2.1 — Define Terraform Modules ✅

## The problem

`terraform/` was a flat scaffold: providers.tf, variables.tf, outputs.tf — no structure, no modules, and an empty `modules.yaml`. As Phase 2 adds MetalLB, Longhorn, Argo CD, and External Secrets, everything would get crammed into one unreadable main.tf.

## The solution

Create a **module structure** — five reusable, self-contained modules, each with a clear interface (variables in, outputs out):

```text
terraform/
├── providers.tf          ← provider configuration
├── variables.tf          ← inputs to the whole config
├── outputs.tf            ← what the whole config produces
└── modules/
    ├── k3s-bootstrap/    ← namespaces + bootstrap resources
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── metallb/          ← IPAddressPool + L2Advertisement
    ├── longhorn/         ← helm_release
    ├── argocd/           ← AppProject bootstrap (helm take-over deferred)
    └── external-secrets/ ← skeleton, adoption deferred (safety)
```

## What is a module? (learning point)

A module is a **reusable, self-contained folder of Terraform configuration** — like a function in programming:

```text
Without modules:  one giant main.tf, everything coupled
With modules:     small focused "functions", each with inputs and outputs
```

| Benefit | What it gives |
|---------|---------------|
| **Reusability** | The same `metallb` module could serve `homelab` and `dev` environments |
| **Separation of concerns** | Each platform service has its own folder |
| **Isolation** | `terraform plan` on one module without touching others |
| **Standard practice** | This is how real Terraform projects are structured |

## What was created

| Module | main.tf | variables | outputs | Status |
|--------|---------|-----------|---------|--------|
| `k3s-bootstrap` | `kubernetes_namespace_v1` (for_each) | `namespaces`, `environment` | `namespaces` | ✅ |
| `metallb` | `kubernetes_manifest` IP pool + L2 adv | `namespace`, `pool_name`, `pool_addresses`, `advertisement_name` | `pool_name`, `advertisement_name` | ✅ (resources filled in 2.3) |
| `longhorn` | `helm_release` | `release_name`, `repository`, `chart`, `chart_version`, `namespace`, `timeout`, `values` | `release_name`, `namespace` | ✅ (filled in 2.4) |
| `argocd` | `kubernetes_manifest` AppProject | `app_project_manifest`, `release_name`, `namespace`, `chart_version`, `values_file` | `app_project_name` | ✅ (filled in 2.5) |
| `external-secrets` | skeleton + deferral note | `namespace` | none | 🟡 deferred |

Plus `modules/modules.yaml` — a machine-readable module catalog with purpose + ownership scope for each module.

## Verify

```bash
cd terraform
terraform fmt -recursive        # style
terraform init -backend=false   # fetch providers
terraform validate              # "Success! The configuration is valid."
```

Verified: all 15 module files format clean, validation passes.

## Learning verification (2.1)

- [ ] I can explain what a module is and why it's like a function.
- [ ] I can list the 5 modules and what each will own.
- [ ] I understand `variables` (inputs) vs `outputs` (results).
- [ ] I understand why `external-secrets` adoption is deferred (fragile pipeline).
- [ ] I can explain the module boundary as a documentation of ownership.

---

# Task 2.2 — Remote State with Locking ✅ (implemented)

## The problem

Terraform state (`terraform.tfstate`) records what Terraform owns. Today it would be a **local file** — single-machine, easily lost, no locking, no team access. CI and the operator would have *different* states.

## The solution

**Azure Storage backend with blob-lease locking**:

```text
Operator / CI
    │  terraform init / plan / apply
    ▼
Azure Storage (blob: homelab.tfstate)
    ├── the state JSON (source of truth)
    └── blob lease = write lock (only one apply at a time)
```

## Bootstrap (exact commands — run once, on your machine)

```bash
# 1. Create the storage account in the EXISTING homelab RG (westeurope)
az storage account create \
  --name homelabtf \
  --resource-group homelab \
  --location westeurope \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false

# 2. Create the container holding the state blob
az storage container create \
  --name tfstate \
  --account-name homelabtf \
  --auth-mode login

# 3. (Recommended) soft-delete — protects against accidental blob deletion
az storage blob service-properties delete-policy update \
  --account-name homelabtf \
  --days-retained 7 \
  --enable true

# 4. Record the access key (needed for init/apply)
az storage account keys list \
  --account-name homelabtf \
  --resource-group homelab \
  --query "[0].value" -o tsv
```

**Store the key safely** (NOT in git) — put it in Key Vault (consistent with the homelab pattern):

```bash
az keyvault secret set \
  --vault-name kv-homelab-k3s \
  --name terraform-state-key \
  --value "<ACCESS_KEY_FROM_STEP_4>"
```

Then configure the backend and init:

```hcl
# terraform/backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "homelab"
    storage_account_name = "homelabtf"
    container_name       = "tfstate"
    key                  = "homelab.tfstate"
  }
}
```

```bash
export ARM_ACCESS_KEY="$(az keyvault secret show --vault-name kv-homelab-k3s --name terraform-state-key --query value -o tsv)"
terraform init -migrate-state
```

## State protection (learn + document)

- `terraform state list` + `terraform state pull > backup.tfstate` **before every apply**
- Blob soft-delete = 7-day accidental-deletion recovery window
- Encrypted snapshot in Key Vault as a second copy
- Never `terraform state rm` without understanding; never edit state by hand

## What was implemented

| File | Change |
|------|--------|
| `terraform/backend.tf` | **New** — azurerm backend (RG homelab, storage homelabtf, container tfstate, key homelab.tfstate) |
| `terraform/providers.tf` | Pinned `required_providers`: azurerm `~>4.0`, kubernetes `~>3.2`, helm `~>2.17` |
| `.gitignore` | Removed `.terraform.lock.hcl` so the lock file is committed (reproducible CI init) |

## Troubleshooting log — real issues hit during implementation

### Issue 1: `ARM_ACCESS_KEY` must be set in the SAME shell

```text
terraform state list → "No state file was found!"
```

Each terminal is its own world — an `export` in one shell dies with it. The key must be exported **in the same terminal** as the terraform commands:

```bash
export ARM_ACCESS_KEY="$(az keyvault secret show --vault-name kv-homelab-k3s --name terraform-state-key --query value -o tsv)"
echo "KEY LENGTH: ${#ARM_ACCESS_KEY}"   # must print > 0
terraform init
```

### Issue 2: `terraform init` sometimes silently skips the backend handshake

```text
"Initializing the backend..." then jumps to providers — no "Backend configured!"
```

The definitive fix is **explicit `-backend-config` flags**, which force a real Azure connection:

```bash
terraform init -reconfigure \
  -backend-config="storage_account_name=homelabtf" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=homelab.tfstate" \
  -backend-config="resource_group_name=homelab"
```

→ `Successfully configured the backend "azurerm"!` ← the proof it connected.

### Issue 3: `illegal base64 data at input byte 0`

```text
Error: Failed to get existing workspaces: ... decoding accountKey:
       illegal base64 data at input byte 0
```

Root cause: a **Unicode smart-quote `“` got copied into the Key Vault secret** alongside the real key (`“P9ZWBz...`). The azurerm backend needs the storage key as base64; the leading `“` breaks decoding.

**Fix — re-store the clean key via variables, never paste by hand:**

```bash
CLEAN_KEY=$(az storage account keys list --account-name homelabtf \
  --resource-group homelab --query "[0].value" -o tsv)
az keyvault secret set --vault-name kv-homelab-k3s \
  --name terraform-state-key --value "$CLEAN_KEY"
```

**Lessons:**
1. Never paste secrets by hand — pipe them via shell variables (`az ... -o tsv | az keyvault ... --value "$VAR"`)
2. Always verify a stored secret decodes: `az keyvault secret show ... | base64 -d`
3. "illegal base64 at byte 0" almost always = a mangled/extra character

### Issue 4: The locking proof

After a successful init, `terraform plan` shows:

```text
Acquiring state lock. This may take a few moments...
... Releasing state lock. This may take a few moments...
```

The "Acquiring/Releasing state lock" lines are the **proof the blob lease works**. A second concurrent `terraform plan` errors with `Error acquiring the state lock`.

## Learning verification (2.2)

- [x] I can explain what state is and why it's sensitive.
- [x] I understand blob-lease locking (one apply at a time).
- [x] I created the storage account + container via az CLI.
- [x] I stored the access key in Key Vault (not git).
- [x] I ran `terraform init` and saw the backend configured (via `-backend-config` fix).

---

# Task 2.3 — MetalLB via Terraform ✅ (implemented)

## The problem

MetalLB config (IPAddressPool `homelab-pool`, L2Advertisement `homelab-advertisement`) lives in `kubernetes/infrastructure/metallb/` and is applied via kubectl — not versioned as IaC, not Terraform-owned.

## The solution — **import-first, never recreate**

The cluster already has live MetalLB CRs. Creating them with Terraform would **destroy and recreate** (Terraform doesn't know them). The correct pattern:

```text
1. Declare the resources in Terraform (module)
2. terraform import   → adopt the LIVE resources into state
3. terraform plan     → must show ZERO destroy (the safety gate)
4. terraform apply    → adoption, not recreation
```

## What was created (implemented files)

| File | Change |
|------|--------|
| `terraform/modules/metallb/main.tf` | Rewritten to `kubectl_manifest` (alekc/kubectl provider) + module's own `required_providers` |
| `terraform/providers.tf` | Added `alekc/kubectl ~> 2.1` provider + block |
| `terraform/metallb.tf` | **New** — root module call with live values |
| `terraform/variables.tf` | Added `kubeconfig_path` variable |

## Provider choice — `kubectl_manifest` (alekc/kubectl)

To manage MetalLB CRDs, Terraform needs a provider. Two options:

| Provider | How it handles CRDs | Verdict |
|----------|--------------------|---------|
| `hashicorp/kubernetes_manifest` | Requires the full CRD **schema** (huge, version-fragile for MetalLB) | Painful for CRDs |
| `alekc/kubectl_manifest` | Treats manifest **opaquely** — just applies YAML | ✅ **Chosen** |

```hcl
terraform {
  required_providers {
    kubectl = { source = "alekc/kubectl", version = "~> 2.1" }
  }
}

resource "kubectl_manifest" "ip_address_pool" {
  yaml_body = <<-EOT
    apiVersion: metallb.io/v1beta1
    kind: IPAddressPool
    metadata:
      name: ${var.pool_name}
      namespace: ${var.namespace}
    spec:
      addresses:
        - ${var.pool_addresses[0]}
  EOT
}
```

> **Bug hit:** without the module's own `required_providers` block, Terraform resolved `kubectl_manifest` to nonexistent `hashicorp/kubectl`. Each module that uses a provider must declare its own `required_providers` to pin the source.

## Root wiring (`terraform/metallb.tf`)

```hcl
module "metallb" {
  source = "./modules/metallb"

  namespace          = "metallb-system"
  pool_name          = "homelab-pool"
  pool_addresses     = ["192.168.178.210-192.168.178.220"]
  advertisement_name = "homelab-advertisement"
}
```

Values must match the live cluster **exactly** so the import shows zero functional diff.

## Troubleshooting log — real issues hit during implementation

### Issue 1: `~` (tilde) does NOT expand in all providers

```text
Error: invalid provider configuration: stat /config/.kube/k3s-config:
       no such file or directory
```

The hashicorp `kubernetes` provider expands `~`, but `alekc/kubectl` treats it as a literal path relative to CWD (`/config/` in the DevContainer).

**Fix:** expose the kubeconfig path as a **variable**:

```hcl
variable "kubeconfig_path" {
  description = "Absolute path to the kubeconfig (tilde does NOT expand in all providers)"
  type        = string
  default     = "~/.kube/k3s-config"
}
```

```hcl
provider "kubectl" {
  config_path = var.kubeconfig_path
}
```

Set at runtime: `export TF_VAR_kubeconfig_path="/home/vscode/.kube/config"`

### Issue 2: Wrong import ID format

```text
Error: expected ID in format apiVersion//kind//name//namespace,
       received: api/v1/namespaces/metallb-system/ipaddresspool/homelab-pool
```

The kubectl provider's import ID is **`<apiVersion>//<kind>//<name>//<namespace>`** — the error message IS the documentation.

**Corrected commands:**

```bash
terraform import 'module.metallb.kubectl_manifest.ip_address_pool' \
  'metallb.io/v1beta1//IPAddressPool//homelab-pool//metallb-system'

terraform import 'module.metallb.kubectl_manifest.l2_advertisement' \
  'metallb.io/v1beta1//L2Advertisement//homelab-advertisement//metallb-system'
```

### Issue 3: The danger of applying a "+ create" plan before import

```text
Plan: 2 to add, 0 to change, 0 to destroy   ← DANGER
```

Before import, Terraform saw the live resources as "unmanaged" and wanted to **create** them — which would conflict/duplicate. **Never apply a plan that shows `to add` for resources that already exist.** Import first; the plan must show `0 to add`.

## The successful adoption — what "in-place update" means

After import, the plan showed:

```text
Plan: 0 to add, 2 to change, 0 to destroy
```

The `~` (in-place change) is **safe** — it strips `generation`/`managedFields`/`last-applied-configuration` metadata and lets Terraform claim ownership. The **functional spec is unchanged** (addresses, autoAssign, avoidBuggyIPs identical). Zero destroy = the safety gate passed.

## Verify

```bash
kubectl get ipaddresspool -n metallb-system    # unchanged
terraform state list                            # shows the 2 resources
kubectl get svc -A | grep 192.168.178           # Argo CD .213, Ring .214 still there
argocd app list                                 # still Synced (nothing Argo-managed touched)
```

**Rollback:** `kubectl apply -f kubernetes/infrastructure/metallb/ip-pool.yaml` restores instantly — the kubectl files stay in the repo as rollback artifacts.

## Learning verification (2.3)

- [x] I can explain why import-first is safer than create.
- [x] I can explain why `plan` is a *read*.
- [x] I adopted the MetalLB CRs with zero destroy in the plan.
- [x] I know the kubectl YAML stays as rollback artifact.
- [x] I know why `~` doesn't expand in all providers and the variable fix.
- [x] I know the kubectl import ID format (`apiVersion//kind//name//namespace`).
- [x] I know never to apply a `+ create` plan for existing resources.

---

# Task 2.4 — Longhorn via Terraform (designed)

## The problem

Longhorn is installed via unpinned `helm install longhorn longhorn/longhorn` — not Terraform-owned, chart version unrecorded.

## The solution — `helm_release` with documented migration

**Critical:** `helm_release` has **no import** for existing releases (provider limitation). Adoption requires a safe, documented migration:

```text
1. helm get values longhorn -n longhorn-system > /tmp/longhorn-values-backup.yaml
2. kubectl get pvc -A && kubectl get volume -n longhorn-system   # record inventory
3. kubectl get volumesnapshot -A                                  # confirm no active snapshots
4. helm uninstall longhorn -n longhorn-system
   ⚠️ DESTRUCTIVE — but PVCs/PVs/volume data are CRs, NOT Helm-managed → survive
5. kubectl get pvc -A          # verify volumes untouched
6. terraform apply             # recreates operator from same chart
7. Verify: pods, storageclass, PVCs, UI at 192.168.178.211
```

**Key learning point:** a Helm release is *metadata* (what chart, what values); the CRs it manages (PVCs, PVs, volumes) are *data* owned by the namespace — they survive uninstall.

**Alternative (if uncomfortable):** keep Longhorn Helm-managed outside Terraform and only document the boundary + pattern. The module exists either way.

## Learning verification (2.4)

- [ ] I understand why `helm_release` can't import.
- [ ] I know the difference between a Helm release (metadata) and its CRs (data).
- [ ] I understand the `create_namespace=false` guard (never recreate the namespace).
- [ ] I backed up values + inventory before any destructive step.

---

# Task 2.5 — Argo CD via Terraform (designed, with safety deviation)

## The problem

Argo CD is the GitOps controller — the live control plane with app state. Adopting its Helm release into Terraform is high-risk.

## The solution — **AppProject bootstrap; helm take-over DEFERRED**

The Plan agent's design deliberately deviates from the master plan here, for safety:

| What | Terraform owns? | Why |
|------|----------------|-----|
| **AppProject** `homelab-platform` | ✅ Yes (via `kubernetes_manifest`, imported) | It's *config*, not *state* — safe, teaches the pattern |
| **Argo CD Helm release** | 🚫 Deferred | Would require `helm uninstall` on the live GitOps controller — violates "migrate platform-critical components last" |
| **App Application CRs** | 🚫 No | Argo CD manages them; Terraform must never touch `kubernetes/gitops/argocd/applications/` |

```hcl
# terraform/argocd.tf
resource "kubernetes_manifest" "app_project" {
  manifest = file(...homelab-platform-project.yaml)   # imported
}
```

**Why this deviation is right for a learning homelab:** the master plan's full helm take-over is a textbook *production* migration; doing it on the one controller with live GitOps state risks the entire platform. The AppProject bootstrap delivers the educational goal (declarative Argo CD config via Terraform, ownership boundary) with near-zero risk. The helm adoption can be added later with a rehearsal cluster.

## Verify

```bash
terraform plan          # shows app_project created; nothing else
terraform apply
kubectl get appproject -n argocd    # homelab-platform exists
argocd app list                     # all three still Synced/Healthy
```

## Learning verification (2.5)

- [ ] I can explain declarative vs imperative adoption.
- [ ] I can explain why the AppProject is the right first Argo CD resource for Terraform.
- [ ] I can explain why the helm take-over is deferred (safety, live control plane).
- [ ] I can state the ownership rule: Terraform owns AppProject, Argo CD owns Applications.

---

# Task 2.6 — `terraform plan` as CI Check (designed)

## The problem

Phase 1 CI runs `fmt`/`validate` only. `plan` (the read that shows what *would* change) needs cluster access — which the GitHub runner doesn't have.

## The solution — extend the Phase 1 workflow

```text
fmt → init(-backend=false) → validate → init(backend) → plan(-lock=false) → PR comment
```

- Plan step runs only on `pull_request` + `workflow_dispatch` (never on push to main)
- `-lock=false` — CI plans are read-only and must not hold the state lock
- **No apply step exists anywhere in CI** — operators are the only entities that apply
- PR comment via `tfcmt` / `github-script` with the plan output

## Read-only cluster access (recommendation)

**Read-only ServiceAccount token** in a GitHub secret:

```bash
# Create SA with get/list/watch only (no create/update/delete)
kubectl create serviceaccount terraform-ci -n kube-system
# + ClusterRoleBinding with resources: ["*"], verbs: ["get","list","watch"]
```

```text
KUBECONFIG_CI = base64 of a minimal kubeconfig with the SA token
ARM_ACCESS_KEY = blob-only access key (Key Vault value)
```

CI decodes → temp file → `export KUBECONFIG=/tmp/kubeconfig-ci` → `terraform plan -lock=false`.

**The operator always runs the authoritative `terraform plan` locally before any apply.** CI plan is a *watchdog*, not a gate. If secrets can't be configured, the plan step degrades gracefully to skipped (documented, not silent).

## Learning verification (2.6)

- [ ] I can explain why CI never applies.
- [ ] I can explain `-lock=false` on CI plans.
- [ ] I can explain the read-only SA token model.
- [ ] I know the operator still plans locally before applying.

---

# Task 2.7 — Documentation

This document. Records the ownership boundary, the risk assessment, the remote-state bootstrap, and the safety deviations.

---

## Risk Assessment

| Risk | Blast radius | Mitigation |
|------|-------------|------------|
| `helm uninstall` on Longhorn gone wrong | Volume data loss | Scripted migration with values+PVC inventory backup; or keep Helm-managed |
| Terraform `apply` recreating live resources | Brief outage | Import-first discipline; plan must show 0 changes on adoption |
| Argo CD `selfHeal` fighting Terraform | Drift loop | Ownership boundary; Terraform never touches Application CRs |
| State file loss | Terraform orphans everything | Blob soft-delete, pre-apply `state pull` backup, KV snapshot |
| CI holding state lock / CI applying | Blocks operators / mutation | `-lock=false` on CI plan; no apply step in CI |
| Kubeconfig in GitHub secret leaked | Cluster compromise | Read-only SA token (get/list/watch), revocable, documented rotation |

## Universal rules (every task)

1. `terraform plan` output must show **zero destroy** before any apply.
2. `terraform state pull > backup.tfstate` before every apply.
3. Apply in a maintenance window with the affected services open in a browser.
4. **Never `terraform destroy` on this cluster.** It is not a disposable lab.
5. The kubectl files stay in the repo as rollback artifacts.

---

## Phase 2 — Master Checklist

- [x] **2.1** Module structure created (5 modules + modules.yaml), fmt/validate green
- [x] **2.2** Storage account + container created, backend.tf, init -migrate-state, key in KV
- [x] **2.3** MetalLB CRs imported (zero-destroy plan), kubectl files annotated
- [ ] **2.4** Longhorn adopted (documented migration) OR documented as deferred
- [ ] **2.5** AppProject bootstrap via Terraform; helm take-over documented as deferred
- [ ] **2.6** CI plan step + read-only SA token + PR comment
- [ ] **2.7** Phase 2 doc complete (this file) + README updates

## Recommended sequence

```text
2.1 (modules) → 2.2 (remote state — everything needs it)
    → 2.3 (MetalLB — safest import) → 2.4 (Longhorn — chart adoption)
    → 2.5 (Argo CD — AppProject only) → 2.6 (CI plan) → 2.7 (docs)
```

---

## Concepts Glossary

| Term | Meaning |
|------|---------|
| **Module** | Reusable Terraform folder with variables in, outputs out |
| **State** | JSON record of what Terraform owns (sensitive — protect it) |
| **Blob lease** | Azure's write lock — one apply at a time |
| **Import-first** | Adopt live resources into state, never recreate them |
| **`helm_release`** | Terraform resource managing a Helm release (no import support) |
| **AppProject** | Argo CD's scoping mechanism (what repos/namespaces an app may touch) |
| **`-lock=false`** | Skip state locking (CI read-only plans) |
| **Ownership boundary** | Which tool manages which resources — the anti-drift contract |

---

## Related Documents

- [Phase 1 — Foundation Hardening](expansion-plan-phase-1.md)
- [Homelab Study Guide](homelab-study-guide.md)
- [Terraform README](../terraform/README.md)
- [Architecture](architecture.md)
- [Runbooks](runbooks/)

---

*Last updated: 2026-08-06*  
*Project: DevOps Homelab Platform*