# ── OPA Gatekeeper — admission controller + policy enforcement ────────────────
# Installs the Gatekeeper controller only. ConstraintTemplates + Constraints
# (the actual policies) live in aj-cluster-baseline and are synced by ArgoCD.
#
# No IAM role needed — Gatekeeper only talks to the K8s API server, not AWS.

resource "helm_release" "gatekeeper" {
  count = var.install_gatekeeper ? 1 : 0

  name       = "gatekeeper"
  repository = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart      = "gatekeeper"
  version    = var.chart_version_gatekeeper
  namespace  = kubernetes_namespace.platform["gatekeeper-system"].metadata[0].name

  # Declared in namespaces.tf so it carries labels. A Helm-created namespace
  # has none, which made it fail-open to Cilium and inadmissible to Gatekeeper.
  create_namespace = false

  set {
    name  = "auditInterval"
    value = "60"
  }

  # Surface violations as K8s Events so ArgoCD and kubectl can surface them
  set {
    name  = "emitAuditEvents"
    value = "true"
  }

  set {
    name  = "emitAdmissionEvents"
    value = "true"
  }

  # Cap audit results per constraint — prevents unbounded memory growth
  set {
    name  = "violationLimit"
    value = "100"
  }

  set {
    name  = "controllerManager.priorityClassName"
    value = "system-cluster-critical"
  }

  set {
    name  = "audit.priorityClassName"
    value = "system-cluster-critical"
  }

  # Exempt the gatekeeper-system namespace from its own policies
  set {
    name  = "postInstall.labelNamespace.enabled"
    value = "true"
  }

  depends_on = [helm_release.cilium]
  wait       = true
  timeout    = 300
}
