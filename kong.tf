# ── Kong Ingress Controller — API gateway ────────────────────────────────────
# Kong KIC v3 (chart: kong/ingress) handles all external-facing microservice
# routes: JWT/OIDC auth, per-consumer rate limiting (backed by Valkey),
# request/response transformations, correlation ID injection.
#
# KongPlugin CRDs live in k8s-manifests (GitOps). Kong itself needs no AWS IAM.
#
# Kong proxy is exposed via a LoadBalancer service — AWS LBC provisions an NLB.
# AWS LBC must be installed before Kong (depends_on enforced below).

resource "helm_release" "kong" {
  count = var.install_kong ? 1 : 0

  name       = "kong"
  repository = "https://charts.konghq.com"
  chart      = "ingress"
  version    = var.chart_version_kong
  namespace  = "kong"

  create_namespace = true

  # Expose Kong proxy via NLB (AWS LBC provisions it from the LoadBalancer service)
  set {
    name  = "proxy.type"
    value = "LoadBalancer"
  }

  set {
    name  = "proxy.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "external"
  }

  set {
    name  = "proxy.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-nlb-target-type"
    value = "ip"
  }

  set {
    name  = "proxy.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
    value = "internet-facing"
  }

  # Enable KongPlugin + KongIngress CRD install
  set {
    name  = "ingressController.enabled"
    value = "true"
  }

  set {
    name  = "ingressController.installCRDs"
    value = "true"
  }

  # Replicas — HA in prod
  set {
    name  = "replicaCount"
    value = var.environment == "prod" ? "2" : "1"
  }

  set {
    name  = "resources.requests.cpu"
    value = "200m"
  }

  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "resources.limits.memory"
    value = "1Gi"
  }

  depends_on = [
    helm_release.cilium,
    helm_release.cert_manager,
    helm_release.aws_lbc,
  ]
  wait    = true
  timeout = 300
}
