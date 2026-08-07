# Terraform remote state backend — Azure Storage with blob-lease locking
#
# State lives in Azure Storage (blob: homelab.tfstate) so operator and CI
# share the SAME source of truth, and the blob lease provides locking
# (only one apply at a time).
#
# Backend configuration is fixed at `terraform init` time — changing it
# requires `terraform init -reconfigure` (or -migrate-state).
#
# The access key is NOT stored here. It is injected at init/apply time via:
#   export ARM_ACCESS_KEY="$(az keyvault secret show --vault-name kv-homelab-k3s \
#     --name terraform-state-key --query value -o tsv)"
#
# Bootstrap (one-time, documented in docs/expansion-plan-phase-2.md):
#   az storage account create ... homelabtf ...
#   az storage container create --name tfstate --account-name homelabtf
#   az storage blob service-properties delete-policy update ... (soft-delete 7d)
#   az keyvault secret set --vault-name kv-homelab-k3s --name terraform-state-key ...

terraform {
  backend "azurerm" {
    resource_group_name  = "homelab"
    storage_account_name = "homelabtf"
    container_name       = "tfstate"
    key                  = "homelab.tfstate"
  }
}
