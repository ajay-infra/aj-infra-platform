# ─────────────────────────────────────────────────────────────────────────────
# Platform namespaces
#
# Every one of these was previously created by `create_namespace = true` on a
# helm_release, which produces a namespace with NO labels. Three things broke
# quietly as a result:
#
#   1. `require-cost-labels` and `require-segment-label` are both at `deny` and
#      exclude only kube-system, kube-public, kube-node-lease, default and
#      gatekeeper-system. So nine of these namespaces would be REJECTED at
#      admission — the platform could not install itself onto a cluster running
#      its own policies.
#   2. The CiliumNetworkPolicies select on
#      io.cilium.k8s.namespace.labels.platform.aj/segment. No label, no policy,
#      and Cilium leaves an unselected endpoint unrestricted — so every platform
#      component was fail-open, apisix (the internet-facing edge) included.
#   3. Container cost was attributable no further than "this cluster".
#
# The rule now: THE MECHANISM THAT INSTALLS A COMPONENT DECLARES ITS NAMESPACE.
# Terraform installs these, so Terraform declares them. ArgoCD-installed
# components use managedNamespaceMetadata in their ApplicationSet, and
# k8s-manifests keeps only the workload namespaces no installer owns.
#
# Ownership follows installation because the alternative has a race: falcon-system
# was declared in k8s-manifests AND created by helm, so whichever landed first
# decided whether it had labels.
# ─────────────────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "platform" {
  for_each = local.active_namespaces

  metadata {
    name = each.key

    labels = merge({
      # Cost attribution. AWS tags attach to nodes and many pods share a node,
      # so container spend is allocated from these, not from the tags above.
      "team"                 = var.team
      "platform.aj/class"    = "platform"
      "platform.aj/customer" = "internal"

      # Load-bearing: selects the CiliumNetworkPolicy. See locals.tf.
      "platform.aj/segment" = each.value.segment

      # The same concept as the Application tag, under the name every chart,
      # ArgoCD and Prometheus already read.
      "app.kubernetes.io/name"       = each.value.application
      "app.kubernetes.io/managed-by" = "terraform"

      # Pod Security. `audit` and `warn` only — `enforce` is deliberately unset
      # except where a component states its own level, because a wrong enforce
      # level BLOCKS the component and the charts cannot be fetched offline to
      # confirm what each one needs. Audit and warn surface the same information
      # in the log without that risk, and enforce can be raised per component
      # once its real requirements are observed.
      "pod-security.kubernetes.io/audit" = "restricted"
      "pod-security.kubernetes.io/warn"  = "restricted"
      },
      each.value.extra_labels
    )
  }
}
