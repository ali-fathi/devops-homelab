# Terraform Infrastructure as Code

Terraform is the Infrastructure as Code layer of this repository.

Its purpose is to describe infrastructure declaratively rather than creating it manually through a web console or a series of undocumented commands.

For the full platform study guide:

```text
docs/homelab-study-guide.md
```

---

## Current repository status

Terraform is currently a scaffold:

```text
terraform/providers.tf
terraform/variables.tf
terraform/outputs.tf
terraform/modules/modules.yaml
```

At present:

```text
A Kubernetes provider is configured.
An environment variable is defined.
An output is defined.
No substantial resources are managed by Terraform yet.
```

Do not assume that `terraform apply` installs the whole homelab. The active application deployment path is Kubernetes plus Argo CD.

---

## Terraform concepts

### Provider

A provider translates Terraform resources into API calls to a platform such as:

```text
Kubernetes
Azure
AWS
DNS providers
```

The current provider configuration points to:

```text
~/.kube/k3s-config
```

### Resource

A resource is an object Terraform creates or manages.

Examples could include:

```text
kubernetes_namespace
kubernetes_service
Azure resource group
DNS record
```

### Variable

A variable makes configuration reusable between environments:

```text
environment = homelab
```

### Output

An output exposes useful values after a plan/apply operation.

### State

Terraform state records what Terraform believes it owns. State is sensitive and must be protected.

Do not commit a local state file containing credentials or infrastructure details.

---

## Terraform versus Ansible

Use Ansible for host configuration:

```text
SSH users
OS packages
K3s installation
node patching
sudo and SSH hardening
```

Use Terraform for declarative infrastructure APIs:

```text
cloud resources
DNS
Kubernetes resources when Terraform owns them
```

Do not make Terraform and Argo CD manage the same Kubernetes fields without an ownership plan.

A recommended boundary is:

```text
Terraform → cluster/bootstrap infrastructure
Argo CD   → application and platform manifests
Ansible   → operating-system hosts
```

---

## Standard workflow

From this directory:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

### `terraform init`

Downloads providers and initializes the working directory.

### `terraform fmt`

Formats `.tf` files consistently.

### `terraform validate`

Checks syntax and internal configuration correctness.

### `terraform plan`

Shows the proposed change without applying it.

Always review the plan before applying.

### `terraform apply`

Executes the approved plan.

---

## Safe future development

When adding a resource:

```text
1. Add a focused resource file.
2. Define variables instead of hardcoded values.
3. Run terraform fmt.
4. Run terraform validate.
5. Run terraform plan.
6. Review for destructive changes.
7. Protect state.
8. Apply in a maintenance window.
9. Document ownership and rollback.
```

For stateful resources:

```text
Back up first.
Avoid renaming resources.
Understand replacement behavior.
Test restore.
```

---

## Troubleshooting

### Provider cannot connect

```bash
terraform providers
kubectl --kubeconfig ~/.kube/k3s-config get nodes
```

Check `config_path` in `providers.tf` and kubeconfig permissions.

### Resource wants to be replaced

Read the plan carefully:

```text
-/+ means destroy and recreate
~ means update in place
+ means create
- means destroy
```

Never apply a destructive stateful plan without backup and a rollback strategy.

### State lock or stale state

Do not delete state blindly. Determine whether another operation is running and inspect the backend/state ownership first.

---

## Planned improvements

```text
Add remote state with locking.
Add Kubernetes bootstrap resources only after ownership is defined.
Add Azure resources for Key Vault if appropriate.
Add CI terraform fmt/validate/plan checks.
Define separate dev and homelab variables.
Document state backup and recovery.
```
