# external-secrets module
#
# External Secrets Operator integration (ClusterSecretStore → Azure Key Vault).
#
# STATUS: skeleton only. Ownership deliberately DEFERRED to a later phase.
#
# Why deferred (see docs/expansion-plan-phase-2.md):
#   - The secrets pipeline is the most fragile component: a mis-apply can
#     make every app unable to read credentials.
#   - The existing ClusterSecretStore `azure-keyvault` is applied manually
#     and is already in production.
#   - Adopting it later is the same kubernetes_manifest + import pattern
#     already learned in Phase 2.3 — nothing is lost by deferring.
#
# When adopted, this module will own:
#   - ClusterSecretStore azure-keyvault (imported, kubernetes_manifest)
#   - its auth Secret (from Key Vault, via ExternalSecret or direct)
