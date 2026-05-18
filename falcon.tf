# ── CrowdStrike Falcon — runtime security sensor ──────────────────────────────
# Deploys the Falcon sensor as a privileged DaemonSet on every node.
# Requires CrowdStrike CID (Customer ID) stored in Secrets Manager.
# ESO ExternalSecret syncs the CID into K8s Secret "falcon-credentials"
# in the falcon-system namespace before this Helm release is applied.
#
# OPA Gatekeeper: the no-privileged-containers constraint in k8s-manifests
# has an exemption for falcon-system namespace.
#
# No IAM role needed — Falcon agent calls CrowdStrike cloud endpoints directly
# (egress over 443), not AWS APIs.

resource "helm_release" "falcon" {
  count = var.install_falcon ? 1 : 0

  name       = "falcon-sensor"
  repository = "https://crowdstrike.github.io/falcon-helm"
  chart      = "falcon-sensor"
  version    = var.chart_version_falcon
  namespace  = "falcon-system"

  create_namespace = true

  # Use kernel backend (default; requires no init container)
  set {
    name  = "node.backend"
    value = "kernel"
  }

  # CID is read from the ESO-synced secret — never hardcoded here
  set {
    name  = "falcon.existingSecret"
    value = "falcon-credentials"
  }

  # Resource limits — DaemonSet runs on every node; keep footprint small
  set {
    name  = "node.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "node.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "node.resources.limits.memory"
    value = "512Mi"
  }

  # Tolerate all taints so the sensor runs on every node including system nodes
  set {
    name  = "node.tolerations[0].operator"
    value = "Exists"
  }

  depends_on = [
    helm_release.cilium,
    helm_release.external_secrets,   # ESO must be up to sync falcon-credentials
  ]
  wait    = true
  timeout = 300
}
