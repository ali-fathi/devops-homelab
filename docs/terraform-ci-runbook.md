# Terraform CI Pipeline — Full Guide & Troubleshooting

> **Complete reference for the CI plan-gate: how it works, the pieces, and how to fix it when it breaks.**
> Target: understand deeply + troubleshoot quickly.

## 1. What this pipeline does

GitHub Actions runs **three gates** on every change touching `terraform/`:

```text
GATE 1 (always):  fmt + validate      → style + syntax, no credentials
GATE 2 (PR only): terraform plan      → shows what WOULD change (read-only)
GATE 3 (PR only): PR comment          → posts the plan for review

NEVER: terraform apply. CI is a watchdog, not a deployer.
```

The cloud runner reaches your homelab cluster through **Tailscale** (the runner can't route to `192.168.178.80:6443` directly — it's a private LAN IP).

## 2. The architecture (end to end)

```text
GitHub runner (ubuntu-latest, Microsoft cloud)
   │
   │ ① checkout + setup terraform
   ▼
[GATE 1: fmt, init -backend=false, validate]     ← no secrets needed
   │
   │ ② ONLY on pull_request / workflow_dispatch:
   ▼
Connect to Tailscale (authkey, tag:ci)            ← ③ joins wireguard mesh
   │
   ▼
Terraform init (backend)                          ← ④ reads ARM_ACCESS_KEY, talks to Azure blobs
   │  reads state from Azure Storage (homelabtf/tfstate/homelab.tfstate)
   ▼
Terraform plan -lock=false                         ← ⑤ reads KUBECONFIG_CI, talks to cluster
   │  refreshes state module refs (longhorn, metallb, argocd, app_project)
   ▼
Post plan to PR                                   ← ⑥ github-script posts "## Terraform Plan"
```

## 3. The pieces (what each does)

### 3.1 The workflow — `.github/workflows/terraform-validate.yaml`

| Step | Runs when | Needs | Does |
|------|-----------|-------|------|
| Checkout | always | — | clones the repo |
| Setup Terraform (v4) | always | — | installs terraform 1.9.8 (Node 24, no deprecation warning) |
| fmt check | always | — | fails if formatting differs |
| init (no backend) | always | — | fetches providers, skips state |
| validate | always | — | syntax + internal consistency |
| **Connect Tailscale** | PR + dispatch | `TS_AUTHKEY` | joins tailnet (WireGuard) |
| init (backend) | PR + dispatch | `ARM_ACCESS_KEY` | connects to Azure state |
| **plan (read-only)** | PR + dispatch | `ARM_ACCESS_KEY`, `KUBECONFIG_CI` | builds plan, output to `$GITHUB_OUTPUT` |
| **Post plan to PR** | **PR only** | `pull-requests: write` | comments the plan on the PR |

### 3.2 The RBAC — `kubernetes/ci/terraform-ci/rbac.yaml`

The CI identity is read-only **and scoped to Terraform's current state refreshes**. It intentionally does not use wildcard `apiGroups` or `resources`.

```text
ServiceAccount terraform-ci (kube-system)
   -> Role terraform-ci-metallb-readonly (metallb-system)
      - metallb.io/IPAddressPool
      - metallb.io/L2Advertisement
      verbs: get
   -> Role terraform-ci-argocd-readonly (argocd)
      - argoproj.io/AppProject
      verbs: get
   -> Role terraform-ci-longhorn-release-readonly (longhorn-system)
      - core/Secret
      verbs: get, list
```

All usable permissions are namespace-scoped Roles. The retained `terraform-ci-readonly` ClusterRole and ClusterRoleBinding are deliberately empty compatibility objects: retaining their names lets `kubectl apply` replace the old wildcard rules in place without leaving the previously broad access behind.

This is the least privilege required by the current configuration:

| Terraform resource | Provider | Kubernetes API permission |
|---|---|---|
| MetalLB `IPAddressPool` | `kubectl_manifest` | `get` on `metallb.io/ipaddresspools` in `metallb-system` |
| MetalLB `L2Advertisement` | `kubectl_manifest` | `get` on `metallb.io/l2advertisements` in `metallb-system` |
| Argo CD `AppProject` | `kubectl_manifest` | `get` on `argoproj.io/appprojects` in `argocd` |
| Longhorn Helm release | `helm_release` | `get` and `list` on `secrets` in `longhorn-system` only |

CI has no `create`, `update`, `patch`, `delete`, `deletecollection`, `exec`, `watch`, or wildcard permission. If a future Terraform resource needs additional read access, add only its exact API group, resource, namespace where applicable, and the minimum required read verb after documenting and testing the requirement.

#### Apply and verify the RBAC hardening

Apply the committed RBAC manifest. It preserves the existing `terraform-ci-readonly` ClusterRole and ClusterRoleBinding names, so it replaces the former wildcard rules in place. The existing CI kubeconfig and GitHub secret do not need to change.

```bash
kubectl apply -f kubernetes/ci/terraform-ci/rbac.yaml
```

Verify every required permission is allowed:

```bash
kubectl auth can-i get ipaddresspools.metallb.io -n metallb-system --as=system:serviceaccount:kube-system:terraform-ci
```

```bash
kubectl auth can-i get l2advertisements.metallb.io -n metallb-system --as=system:serviceaccount:kube-system:terraform-ci
```

```bash
kubectl auth can-i get appprojects.argoproj.io -n argocd --as=system:serviceaccount:kube-system:terraform-ci
```

```bash
kubectl auth can-i list secrets -n longhorn-system --as=system:serviceaccount:kube-system:terraform-ci
```

Each command must return `yes`. Then prove that unrelated read access and all write access are denied:

```bash
kubectl auth can-i get pods -n default --as=system:serviceaccount:kube-system:terraform-ci
```

```bash
kubectl auth can-i get secrets -n kube-system --as=system:serviceaccount:kube-system:terraform-ci
```

```bash
kubectl auth can-i create deployments -n default --as=system:serviceaccount:kube-system:terraform-ci
```

Each denial command must return `no`.

Finally, open a Terraform pull request or run the manual Terraform workflow and verify that its read-only `terraform plan` still succeeds. If it fails with a Kubernetes `forbidden` error, record the exact API group/resource requested, confirm that Terraform actively manages it, add only that read permission, and retest.

### 3.3 The GitHub secrets (Settings → Secrets → Actions)

| Secret | Value | Used by |
|--------|-------|---------|
| `ARM_ACCESS_KEY` | Azure storage key (Key Vault `terraform-state-key`) | backend init |
| `KUBECONFIG_CI` | **base64** of a minimal kubeconfig with the SA token | plan → cluster |
| `TS_AUTHKEY` | Tailscale auth key, tagged `tag:ci` | Connect to Tailscale |

### 3.4 The Tailscale side

The `tailscale/github-action@v2` step:
- Uses `authkey: ${{ secrets.TS_AUTHKEY }}` (Free-plan friendly). `authkey` is **deprecated** in favor of OAuth clients — the warning is benign but noted; revisit OAuth later if wanted.
- Pins `version: "1.102.2"` (an explicit version). **Do NOT use `version: stable`** — that keyword broke the action's download+checksum step (`sha256sum: standard input: no properly formatted checksum lines`). Pin an explicit stable version.

Note: `authkey` deprecation warning + the version-pin gotcha are both documented in Task 2.6 of the phase-2 doc.

```text
Policy (admin console):
  tagOwners: tag:ci → autogroup:admin     (your admin can issue tag:ci)
  acls: tag:ci → tag:ci:*                 (CI devices connect to each other)
  (no srcPosture/dstPosture — those are paid-plan only)

Subnet router (Proxmox LXC, like the Cloudflare agent):
  tailscaled up --advertise-routes=192.168.178.0/24 --accept-routes=true
  → cloud runner routes to 192.168.178.80 through this node
  → must APPROVE the route in admin console
```

## 4. The full thread (how a plan is produced)

```text
1. PR touches terraform/** → workflow triggers
2. fmt + validate pass (no creds)
3. runner joins tailnet (TS_AUTHKEY) → can now reach 192.168.178.80
4. init reads ARM_ACCESS_KEY → Azure Storage state
5. plan decodes KUBECONFIG_CI → authenticates as terraform-ci (read-only)
6. plan refreshes live state vs config, produces the diff
7. github-script posts "## Terraform Plan" on the PR
8. On push→main: steps 3–7 SKIP (only fmt+validate) — main is the GitOps source of truth
```

## 5. Troubleshooting — symptom → cause → fix

### 5.1 `dial tcp 192.168.178.80:6443: i/o timeout`
```text
Cause:   runner can't REACH the cluster — Tailscale not connected,
         subnet router down, or route not approved.
Checks:  - "Connect to Tailscale" step green?
         - Subnet router LXC running? `systemctl status tailscaled`
         - Route approved? Admin console → Machines → LXC → Subnets → Approve
Fix:     fix the failing piece, re-run.
```

### 5.2 `x509: certificate signed by unknown authority`
```text
Cause:   runner REACHED the cluster but doesn't TRUST the server cert —
         the `certificate-authority-data` in KUBECONFIG_CI is wrong/missing.
Checks:  - Compare with the master's CA:
           ssh ansible@192.168.178.80 "sudo grep 'certificate-authority-data' /etc/rancher/k3s/k3s.yaml"
Fix:     rebuild kubeconfig with the master CA, re-upload KUBECONFIG_CI:
           gh secret set KUBECONFIG_CI --repo ali-fathi/devops-homelab \
             --body "$(base64 < /tmp/kubeconfig-ci.yaml)"
```

### 5.3 `the server has asked for the client to provide credentials` OR `Please enter Username`
```text
Cause:   TLS OK (CA trusted) but NO valid token — SA token is empty in kubeconfig.
         (K8s 1.24+ doesn't auto-create SA token secrets.)
Checks:  - `kubectl get secret -n kube-system | grep terraform-ci` → empty?
Fix:     create the token secret, rebuild, re-upload:
         kubectl apply -f - <<EOF
         apiVersion: v1
         kind: Secret
         metadata:
           name: terraform-ci-token
           namespace: kube-system
           annotations:
             kubernetes.io/service-account.name: terraform-ci
         type: kubernetes.io/service-account-token
         EOF
         SA_SECRET=terraform-ci-token
         TOKEN=$(kubectl get secret $SA_SECRET -n kube-system -o jsonpath='{.data.token}' | base64 -d)
         # rebuild kubeconfig with token + master CA, re-upload secret
```

### 5.4 `iam error` on init (backend)
```text
Cause:   ARM_ACCESS_KEY secret missing/empty/wrong.
Fix:     az keyvault secret show --vault-name kv-homelab-k3s --name terraform-state-key \
           --query value -o tsv   → then gh secret set ARM_ACCESS_KEY
```

### 5.5 `Connect to Tailscale` fails
```text
Cause:   TS_AUTHKEY missing/expired/tag policy wrong.
Checks:  - `gh secret list --repo ali-fathi/devops-homelab` shows TS_AUTHKEY?
         - auth key still valid (ephemeral vs persisted)?
         - tag:ci allowed by tagOwners?
Fix:     regenerate auth key with tag:ci, re-upload.
```

### 5.6 `issue//comments 404` after plan
```text
Cause:   comment step ran on workflow_dispatch (no PR = no issue number).
Fix:     (already fixed) step now only runs when github.event_name == 'pull_request'.
         On dispatch the step is SKIPPED, not run.
```

### 5.7 `new-line-at-end-of-file` yamllint
```text
Cause:   any YAML file (workflow, rbac, docs/*.yaml) lacks a trailing newline.
         The repo's kubernetes-validate workflow lints docs + ansible + .github.
Fix:     printf '\n' >> <file>  for each flagged file.
```

### 5.8 `No changes. Your infrastructure matches the configuration.`
```text
NOT an error — it's SUCCESS. CI adopted the live infra (no drift).
If you EXPECTED a change (e.g. you edited terraform/), the plan is empty
because your edit didn't reach the runner, or the edit matches live state.
```

## 6. Rebuilding the CI kubeconfig (the full recipe)

```bash
# On the DevContainer:
kubectl apply -f kubernetes/ci/terraform-ci/rbac.yaml

# Ensure the token secret exists (K8s 1.24+):
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: terraform-ci-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: terraform-ci
type: kubernetes.io/service-account-token
EOF

SA_SECRET=terraform-ci-token
TOKEN=$(kubectl get secret $SA_SECRET -n kube-system -o jsonpath='{.data.token}' | base64 -d)
CA=$(ssh ansible@192.168.178.80 "sudo grep 'certificate-authority-data' /etc/rancher/k3s/k3s.yaml | awk '{print \$2}'")

cat > /tmp/kubeconfig-ci.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: k3s
    cluster:
      server: https://192.168.178.80:6443
      certificate-authority-data: $CA
contexts:
  - name: ci
    context:
      cluster: k3s
      user: terraform-ci
      namespace: kube-system
current-context: ci
users:
  - name: terraform-ci
    user:
      token: $TOKEN
EOF

# Verify locally BEFORE uploading (an exact resource Terraform reads):
kubectl --kubeconfig /tmp/kubeconfig-ci.yaml get ipaddresspools.metallb.io -n metallb-system

# Least-privilege proof:
kubectl --kubeconfig /tmp/kubeconfig-ci.yaml auth can-i get ipaddresspools.metallb.io -n metallb-system   # YES
kubectl --kubeconfig /tmp/kubeconfig-ci.yaml auth can-i get nodes                                              # NO
kubectl --kubeconfig /tmp/kubeconfig-ci.yaml auth can-i create deployments                                    # NO

# Upload:
gh secret set KUBECONFIG_CI --repo ali-fathi/devops-homelab --body "$(base64 < /tmp/kubeconfig-ci.yaml)"
```

## 7. Testing the pipeline end-to-end

```text
TEST 1 — manual run (no PR):
  Actions → Terraform Validation → Run workflow → main
  Expect: Tailscale ✅, init ✅, plan ✅, comment SKIPPED (no PR)

TEST 2 — PR (the real gate):
  Open a PR touching terraform/ → workflow runs → "## Terraform Plan" comment posts

TEST 3 — push to main (negative):
  Plan + comment SKIPPED; only fmt+validate run.

TEST 4 — least-privilege proof (in DevContainer):
  kubectl --kubeconfig /tmp/kubeconfig-ci.yaml auth can-i get ipaddresspools.metallb.io -n metallb-system  # YES
  kubectl --kubeconfig /tmp/kubeconfig-ci.yaml auth can-i get nodes                                             # NO
  kubectl --kubeconfig /tmp/kubeconfig-ci.yaml auth can-i create deployments                                   # NO
```

## 8. Key files

| File | Role |
|------|------|
| `.github/workflows/terraform-validate.yaml` | the whole pipeline |
| `kubernetes/ci/terraform-ci/rbac.yaml` | read-only SA + role |
| `terraform/providers.tf` | uses `var.kubeconfig_path` (CI sets it) |
| `docs/expansion-plan-phase-2.md` | Phase 2 doc (Task 2.6) |

## 9. Learning summary

```text
WHAT runs in CI:   fmt, validate (always); plan, comment (PR/dispatch)
WHAT never runs:   terraform apply  — operators apply locally
HOW CI reaches cluster:  Tailscale (authkey tag:ci) → subnet router → 192.168.178.80
HOW CI stays read-only:  SA with exact resource reads only + -lock=false
The 3 secrets:      ARM_ACCESS_KEY, KUBECONFIG_CI, TS_AUTHKEY
The 3 network errors in order:  i/o timeout (no route) → x509 (no trust) → credentials (no token)
```

---

*Last updated: 2026-08-10 · Project: DevOps Homelab Platform*