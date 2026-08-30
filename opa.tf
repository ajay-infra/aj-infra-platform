# ── OPA — the authorization decision point ───────────────────────────────────
# Standalone OPA that APISIX's `opa` plugin calls over HTTP. This is the single
# source of truth for "who may reach what" across the estate.
#
# ── Why standalone, and not the OPA we already run ───────────────────────────
# Gatekeeper is OPA embedded in an admission controller. It does not expose the
# OPA Data API (`/v1/data/...`) that the APISIX plugin queries, so it cannot be
# reused. Same policy language, different deployment, different job:
#
#   Gatekeeper (aj-cluster-baseline/policies)  admission control on K8s objects
#   this OPA                             authorization on API requests
#
# ── Why OPA verifies the JWT, not the gateway ────────────────────────────────
# This is the lever that prevents the failure that killed the previous estate.
# Verifying tokens here with io.jwt.decode_verify + allowed_issuers makes
# ISSUERS DATA rather than gateway configuration. Adding a tenant becomes a
# policy-data refresh, not a proxy config rollout, and no provider ceiling
# exists to hit. The APISIX opa plugin forwards request headers, so OPA
# receives the Authorization header and can do both verification and
# authorization in one decision.
#
# Corollary: API keys and JWTs are different AUTHENTICATION mechanisms that both
# land as input to the SAME policy. One authorization surface, not two.
#
# ── Policy delivery ──────────────────────────────────────────────────────────
# The chart bundles kube-mgmt, which loads Rego from labelled ConfigMaps. That
# is deliberate — it is the pattern that worked on the previous estate, and it
# keeps policy in git under ArgoCD rather than in a bundle server nobody owns.
# Policies live in aj-cluster-baseline; this repo installs the engine only.
#
# ⚠ JWKS: do NOT fetch keys per request. Either ship the JWKS in policy data or
# use http.send with explicit caching. Key rotation should be a data refresh.

resource "helm_release" "opa" {
  count = var.install_opa ? 1 : 0

  name       = "opa"
  repository = "https://open-policy-agent.github.io/kube-mgmt/charts"
  chart      = "opa-kube-mgmt"
  version    = var.chart_version_opa
  namespace  = kubernetes_namespace.platform["opa"].metadata[0].name

  # Declared in namespaces.tf so it carries labels. A Helm-created namespace
  # has none, which made it fail-open to Cilium and inadmissible to Gatekeeper.
  create_namespace = false

  # This OPA answers API authorization queries. It is NOT an admission
  # controller — Gatekeeper owns that, and enabling admission here would put two
  # webhooks on the same objects.
  set {
    name  = "admissionController.enabled"
    value = "false"
  }

  # Rego is loaded from ConfigMaps carrying openpolicyagent.org/policy=rego.
  set {
    name  = "mgmt.enabled"
    value = "true"
  }

  # An authorization decision sits in the request path of every API call, so
  # prod runs more than one replica. A single-replica OPA is a single point of
  # failure for the entire API surface.
  set {
    name  = "replicas"
    value = var.environment == "prod" ? "3" : "1"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "resources.limits.memory"
    value = "512Mi"
  }

  depends_on = [helm_release.cilium]
  wait       = true
  timeout    = 300
}
