# ── Apache APISIX — API gateway (north–south) ────────────────────────────────
# Replaces Kong, 2026-08-28. Rationale in
# aj-infra-context/arch/gateway-selection.md — the short version:
#
#   * Kong OSS gates openid-connect, the OPA plugin, the developer portal and
#     Kong Manager behind Enterprise. The configured OSS `jwt` plugin resolves
#     `kid` against KongConsumers, of which there were zero, so it could not
#     carry per-user identity at all.
#   * Envoy Gateway was evaluated and rejected on operational evidence: a prior
#     estate OOM-killed it with ~24 JWT issuers in one namespace against a
#     16-provider ceiling. APISIX has no xDS config plane, so that class of
#     failure cannot recur.
#   * `opa` and `openid-connect` ship in the OSS build. `ApisixConsumer` gives
#     API keys and per-consumer quotas as CRDs, replacing hand-rolled key
#     management.
#
# ── The rule that must never be broken ───────────────────────────────────────
# A TENANT NEVER APPEARS IN GATEWAY CONFIGURATION. Tenants are JWT claims and
# OPA policy data. Putting per-tenant state in the proxy config plane is what
# caused the OOM on the previous estate, and it scales O(tenants × proxies) on
# any gateway. JWT verification happens in OPA (see opa.tf), not here, so
# issuers are data that can be reloaded rather than configuration that must be
# rolled out.
#
# Two components:
#   apisix                    the data plane
#   apisix-ingress-controller translates ApisixRoute/ApisixConsumer/
#                             ApisixPluginConfig CRDs and Gateway API resources
#                             into gateway config
#
# ⚠ VERIFY BEFORE FIRST APPLY: controller 2.x supports driving APISIX in
# standalone mode (no etcd) as well as the traditional etcd-backed deployment.
# The choice affects `apisix.deployment.*` and the controller's provider config,
# and the value keys differ between chart majors. Confirm against the chart's
# own values.yaml at the pinned version rather than trusting this file.

resource "helm_release" "apisix" {
  count = var.install_apisix ? 1 : 0

  name       = "apisix"
  repository = "https://apache.github.io/apisix-helm-chart"
  chart      = "apisix"
  version    = var.chart_version_apisix
  namespace  = kubernetes_namespace.platform["apisix"].metadata[0].name

  # Declared in namespaces.tf so it carries labels. A Helm-created namespace
  # has none, which made it fail-open to Cilium and inadmissible to Gatekeeper.
  create_namespace = false

  # Exposed via an NLB, the same shape Kong used — AWS LBC provisions it from
  # the Service. CloudFront's origin points at this through active.<domain>,
  # and TLS is terminated here using the cert-manager wildcard. See
  # aj-infra-context/arch/tls-and-edge.md.
  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "external"
  }

  set {
    name  = "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-nlb-target-type"
    value = "ip"
  }

  set {
    name  = "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
    value = "internet-facing"
  }

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

resource "helm_release" "apisix_ingress_controller" {
  count = var.install_apisix ? 1 : 0

  name       = "apisix-ingress-controller"
  repository = "https://apache.github.io/apisix-helm-chart"
  chart      = "apisix-ingress-controller"
  version    = var.chart_version_apisix_ingress
  namespace  = kubernetes_namespace.platform["apisix"].metadata[0].name

  # Installs ApisixRoute / ApisixConsumer / ApisixUpstream /
  # ApisixPluginConfig, and supports Gateway API resources. Route and consumer
  # definitions live in k8s-manifests and are synced by ArgoCD — this repo
  # installs the controller, never the routes.
  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.limits.memory"
    value = "256Mi"
  }

  depends_on = [helm_release.apisix]
  wait       = true
  timeout    = 300
}
