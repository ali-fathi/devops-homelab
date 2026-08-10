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

> Implementation status: 2.1 ✅ · 2.2 ✅ · 2.3 ✅ · 2.4 ✅ (with incident — see runbook) · 2.5 ✅ · 2.6 ✅ (implemented, pending the 4-test verification) · 2.7 ✅ (this doc).

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

# Task 2.4 — Longhorn via Terraform ✅ (implemented — with a full incident)

## The problem

Longhorn is installed via unpinned `helm install longhorn longhorn/longhorn` — not Terraform-owned, chart version unrecorded.

## The solution — `helm_release` with documented migration

**Critical:** `helm_release` has **no import** for existing releases (provider limitation). Adoption requires a migration (record → uninstall → apply).

**What was implemented:**

| File | Change |
|------|--------|
| `terraform/modules/longhorn/main.tf` | `helm_release` (name/repo/chart/version/namespace, `create_namespace=false`, `wait=true`, `timeout=600`) |
| `terraform/longhorn.tf` | Root module call, chart pinned to live `1.12.0` |
| `scripts/recover-longhorn-volumes.sh` | Recovery script (re-creates Volume CRs matching orphaned data) |

**Verified:** `terraform apply` → `helm_release.longhorn: Creation complete (21s)`, `Apply complete! Resources: 1 added`. Longhorn is now Terraform-owned.

---

## 🚨 THE FULL INCIDENT — uninstall cascade → data recovery (Option C)

This is the most important learning experience in the project. Read it carefully.

### What happened (chronological)

1. **The migration started as planned** — recorded values (`null`, no custom values), recorded PVC/volume inventory (7 PVCs, 6 volumes, all healthy).

2. **First `helm uninstall` FAILED** with `job longhorn-uninstall failed: BackoffLimitExceeded`.

3. **Root cause (learned from logs):** Longhorn has a `deleting-confirmation-flag` setting (default `false`) that REFUSES uninstall. The log:
   ```
   level=fatal msg="cannot uninstall Longhorn because deleting-confirmation-flag is set to `false`. Please set it to `true`..."
   ```
   This is Longhorn's **data-safety interlock** — it refuses to uninstall unless explicitly confirmed.

4. **The mistake:** we set `deleting-confirmation-flag=true` and re-ran uninstall. The uninstall **succeeded** — but the Longhorn uninstall job **cascaded and deleted the Volume CRDs AND the PVCs** (they entered `Terminating`).

5. **The discovery:** the replica DATA was still on disk (`/var/lib/longhorn/replicas/pvc-*`), but Longhorn **v1.12 has NO "Adopt" button** in the UI — orphaned replicas can only be *deleted*.

6. **Attempted manual recovery:** created new Volume CRs with EXACT matching names → they attached but created **FRESH EMPTY replicas** (different hashes), NOT re-claiming the on-disk data. The `du -sh` proved the old data (400–500MB/replica) sat untouched in the old dirs.

7. **User decision: Option C** — accept the data loss and re-initialize cleanly (data was re-fetchable from Garmin/Ring/etc.).

### The recovery that followed (what was done to restore the cluster)

1. Detached + deleted the empty fresh volumes we created.
2. Deleted the orphaned replica data via the Longhorn UI (reclaimed disk).
3. Removed PVC/PV finalizers to clear the stuck `Terminating` objects.
4. Scaled the PVC-owning Deployments to 0, deleted PVCs, scaled back up (fresh volumes created automatically).
5. Re-created the `GarminStats` database in InfluxDB:
   ```bash
   kubectl exec -n garmin deployment/garmin-influxdb -- influx -execute 'CREATE DATABASE GarminStats'
   ```
6. Re-ran `helm upgrade` (NOT install — releases still existed) for the observability stack:
   ```bash
   helm upgrade monitoring prometheus-community/kube-prometheus-stack -n monitoring -f kubernetes/observability/monitoring/values.yaml
   helm upgrade loki grafana/loki -n logging -f kubernetes/observability/logging/loki-values.yaml
   helm upgrade alloy grafana/alloy -n logging -f kubernetes/observability/logging/alloy-values.yaml
   ```
7. Restarted `garmin-fetch-data` — it recovered and resumed polling.

### Final state — fully recovered

```text
All 7 Longhorn volumes: attached + healthy ✅
All 3 nodes: ready ✅
All apps Running (garmin, ring, observability, health-dashboard) ✅
All PVCs Bound (garmin 10+1Gi, loki 20Gi, prometheus 20Gi, grafana+alertmanager+vm 5Gi each) ✅
All MetalLB IPs back (.210-.216) ✅
Garmin fetcher healthy (re-fetching) ✅
```

### ⚠️ The Longhorn "error" explained (cosmetic, not a bug)

```text
"Failed to get filesystem device type of /var/lib/longhorn/"
error="lstat /sys/class/block/ubuntu--vg-ubuntu--lv: no such file or directory"

Longhorn is on an LVM logical volume (ubuntu--vg-ubuntu--lv). It can't
resolve the block-device TYPE for UI disk accounting only. Does not
affect volumes, replicas, or data. No fix needed.
```

### The hard-won learning points (this is the gold)

1. **`deleting-confirmation-flag` is Longhorn's data-safety interlock.** Setting it `true` is the explicit "yes, I accept the consequences" — and those consequences include cascade-deleting volume CRDs/PVCs on uninstall.

2. **A Helm release is metadata; its CRs are the entry point for cascade deletion.** The uninstall job doesn't just remove the operator — it deletes the Volume CRs, which is what triggered the PVC `Terminating` cascade.

3. **Longhorn v1.12 has NO "Adopt" UI.** Orphaned on-disk replicas can only be deleted, not re-adopted by matching-named volumes (the new volume creates fresh replicas). Manual block-level restore or backup-restore is the only real recovery.

4. **The data WAS recoverable on disk** — the replica dirs survived. But without the volume CRs + no Adopt feature, Longhorn wouldn't re-claim them.

5. **A StatefulSet/Deployment with a PVC template is a self-healing loop** — it re-creates a deleted PVC instantly. To clean-slate: **scale to 0 FIRST, delete PVCs, then scale back up.** Order matters.

6. **`helm upgrade` vs `helm install`:** after workloads are deleted, the Helm *release* record may still exist → `install` fails ("cannot re-use a name"), `upgrade` re-applies. Check `helm list -A` first.

7. **Fresh InfluxDB needs its database re-created** (`GarminStats`) after a storage wipe — it's not auto-created.

8. **Never `terraform destroy` / rethink `helm uninstall` on a storage platform.** The safest path is the "defer" option: keep the storage platform Helm-managed until tested on a scratch cluster.

## Learning verification (2.4)

- [x] I understand why `helm_release` can't import.
- [x] I know the difference between a Helm release (metadata) and its CRs (data).
- [x] I understand the `create_namespace=false` guard (never recreate the namespace).
- [x] I backed up values + inventory before any destructive step.
- [x] I now understand Longhorn's `deleting-confirmation-flag` safety interlock.
- [x] I learned why uninstall cascades to Volume CRDs/PVCs.
- [x] I learned the scale-to-0-first clean-slate order.
- [x] I learned the `helm upgrade` vs `install` distinction.

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

# Task 2.6 — `terraform plan` as CI Check ✅ (implemented)

> **Dedicated troubleshooting reference:** see [Terraform CI Runbook](terraform-ci-runbook.md) for the complete architecture, the 5-step thread, and symptom→cause→fix for every error (i/o timeout, x509, credentials, yamllint, PR comment 404).

## The problem

Phase 1 CI runs `fmt`/`validate` only. `plan` (the read that shows what *would* change) needs cluster access — which the GitHub runner doesn't have.

## The solution — extend the Phase 1 workflow

```text
fmt → init(-backend=false) → validate     ← ALWAYS (no creds needed)
→ init(backend) → plan(-lock=false) → PR comment   ← PR + manual only
```

## What was implemented

| File | Change |
|------|--------|
| `.github/workflows/terraform-validate.yaml` | Added gated plan path + PR comment step |
| `kubernetes/ci/terraform-ci/rbac.yaml` | **New** — read-only ServiceAccount/ClusterRole/Binding |

### The workflow (key steps)

1. **Validation gate (always):** `fmt` + `init -backend=false` + `validate` — no secrets needed, catches style/syntax.
2. **Plan gate (PR + workflow_dispatch only):** reconstructs a read-only kubeconfig from `KUBECONFIG_CI`, runs `terraform plan -no-color -lock=false`, captures output to `$GITHUB_OUTPUT`.
3. **PR comment:** `github-script` posts the plan as a `## Terraform Plan` comment.
4. **No `terraform apply` anywhere** — CI only plans, operators apply.

**Key gates:**
- `if: github.event_name == 'pull_request' || github.event_name == 'workflow_dispatch'` on the plan steps → **never runs on push to main**
- `-lock=false` → CI plans are read-only and must NOT hold the state blob lease
- `permissions: pull-requests: write` → needed for the comment

### The RBAC (read-only identity)

```yaml
ServiceAccount terraform-ci (kube-system)
  → ClusterRole terraform-ci-readonly
      verbs: ["get", "list", "watch"]   ← READ-ONLY, no create/update/delete
  → ClusterRoleBinding terraform-ci-readonly
```

### The two GitHub secrets

| Secret | Value | Used by |
|--------|-------|---------|
| `ARM_ACCESS_KEY` | Azure storage key (from Key Vault `terraform-state-key`) | Backend init |
| `KUBECONFIG_CI` | base64 of a minimal kubeconfig with the SA token | Cluster access |

## ⚠️ The network problem discovered (and the Tailscale solution)

**The problem:** the first CI run failed with:
```text
dial tcp 192.168.178.80:6443: i/o timeout
```
The GitHub cloud runner cannot reach the cluster API — `192.168.178.80:6443` is a **private homelab LAN IP** with no route from Microsoft's cloud. The RBAC, secrets, and kubeconfig were all valid; only **network reachability** was broken.

**Options considered:**
| Option | Verdict |
|--------|---------|
| Self-hosted runner in homelab | ❌ Risky on a public repo — a fork's PR can run arbitrary code on your LAN runner |
| Cloudflare Tunnel for the K8s API | ❌ Exposes the crown-jewel admin API to the internet — too dangerous |
| **Tailscale** | ✅ **Chosen** — WireGuard E2E, zero open ports, free, first-party GH Action |

**The Tailscale architecture (industry standard):**
```text
GitHub cloud runner (ubuntu-latest — SAFE sandbox)
   ├── tailscale/github-action@v2  →  joins the tailnet over WireGuard
   └── reaches 192.168.178.80:6443 THROUGH the tailnet (no public exposure)

Homelab (Proxmox LXC, like the Cloudflare agent pattern)
   └── tailscaled →  subnet router advertising 192.168.178.0/24
```

**Why Tailscale is the answer:** the runner stays on GitHub's sandbox (no self-hosted PR risk), the cluster API is never exposed (unlike CF Tunnel), and the connection is encrypted + free.

**The workflow change:** revert `runs-on` to `ubuntu-latest` + add before the plan:
```yaml
- name: Connect to Tailscale
  uses: tailscale/github-action@v2
  with:
    authkey: ${{ secrets.TS_AUTHKEY }}   # auth key (Free-plan friendly, simpler than OAuth)
    tags: tag:ci
```
The `KUBECONFIG_CI` secret still points at `192.168.178.80:6443` — the runner reaches it *through* the subnet-router-advertised route.

### The Tailscale setup (one-time)

1. **Create a free Tailscale account** → https://tailscale.com (free: 3 users, 100 devices).
2. **Policy:** in the admin console, set `tagOwners` for `tag:ci` + an `acls` rule (`tag:ci → tag:ci`). (On the Free plan, omit `srcPosture`/`dstPosture` — those are paid features.)
3. **Generate an auth key** (Keys → Generate auth key) with tag `tag:ci`, and add it as a GitHub secret:
   ```bash
   gh secret set TS_AUTHKEY --repo ali-fathi/devops-homelab --body "tskey-auth-..."
   ```
4. **Install `tailscaled` on a Proxmox LXC** (same pattern as the Cloudflare agent), as a **subnet router** advertising `192.168.178.0/24`:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up --advertise-routes=192.168.178.0/24 --accept-routes=true
   ```
   In the Tailscale admin console: **approve the subnet route** on the LXC machine.

## Bug fixed during implementation

The first version had the PR-comment step read `steps.plan.outputs.stdout` — but GitHub doesn't auto-expose stdout as an output. Fixed by having the plan step write its output to `$GITHUB_OUTPUT` (`plan<<EOF ... EOF`) and the comment reads `steps.plan.outputs.plan`.

## Testing — how to confirm 2.6 works (4 tests)

### Test 0 — Prereq: secrets configured

```bash
gh secret list --repo ali-fathi/devops-homelab
# Must show: ARM_ACCESS_KEY, KUBECONFIG_CI,
#            TS_OAUTH_CLIENT_ID, TS_OAUTH_CLIENT_SECRET
```

**And the tailnet must be up:** the homelab subnet router (LXC) is running `tailscaled`, and the `tag:ci` OAuth client exists.

### Test 1 — `workflow_dispatch` (quickest proof)

GitHub → Actions → "Terraform Validation" → **Run workflow** → main → Run.
**Expected steps:**
- `Connect to Tailscale` → green (runner joins the tailnet)
- `plan (read-only)` → green (reaches the cluster through the tailnet)
All steps green (the comment step may skip — no PR to comment on).

**If `Connect to Tailscale` fails** → check the OAuth secrets / `tag:ci` tag.
**If `plan` fails with `i/o timeout`** → the subnet router route `192.168.178.0/24` isn't approved or isn't running.

### Test 2 — Real PR (the actual gate)

Make a trivial change under `terraform/` on a branch, open a PR. The workflow runs plan and **posts a `## Terraform Plan` comment** on the PR.

### Test 3 — Push to main (negative test)

Push/merge to `main`. The plan + comment steps must show **skipped** (only fmt+validate run).

### Test 4 — Read-only proof

```bash
kubectl --kubeconfig /tmp/kubeconfig-ci.yaml auth can-i create deployments   # → NO
kubectl --kubeconfig /tmp/kubeconfig-ci.yaml auth can-i get nodes            # → YES
```
Confirms the CI token can only read.

## Learning verification (2.6)

- [x] I can explain why CI never applies.
- [x] I can explain `-lock=false` on CI plans.
- [x] I can explain the read-only SA token model.
- [x] I know the operator still plans locally before applying.
- [x] I can run the 4 tests to confirm the workflow works.
- [x] I understand why a cloud runner can't reach a private homelab LAN.
- [x] I understand why Tailscale (WireGuard, E2E, zero open ports) is the secure bridge.
- [x] I know the subnet-router + OAuth `tag:ci` model for CI connections.

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
- [x] **2.4** Longhorn adopted (documented migration + full incident runbook)
- [x] **2.5** AppProject bootstrap via Terraform; helm take-over documented as deferred
- [x] **2.6** CI plan step + read-only SA token + PR comment
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