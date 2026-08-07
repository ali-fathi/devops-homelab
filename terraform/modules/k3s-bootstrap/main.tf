# k3s-bootstrap module
#
# Bootstrap resources for the K3s cluster: namespaces used by platform
# services, plus cluster-scoped bootstrap configuration.
#
# Implemented incrementally in Phase 2. The interfaces (variables/outputs)
# are defined here so the module can be called from root main.tf.

# Namespaces for platform services
resource "kubernetes_namespace_v1" "platform_namespaces" {
  for_each = var.namespaces

  metadata {
    name = each.value
  }
}
