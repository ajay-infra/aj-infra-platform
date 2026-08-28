# ── Keycloak — the identity provider ─────────────────────────────────────────
# Issues the tokens OPA verifies. Chosen over Zitadel and Cognito because it is
# already proven in operation here, and because **Organizations** (GA in
# Keycloak 26) solves the exact failure that shaped this whole design.
#
# ── Why Organizations matters more than the chart ────────────────────────────
# A prior estate ran realm-per-tenant: root + tenant issuer × 3 realms × 4
# tenants ≈ 24 issuers in one namespace, which OOM-killed an Envoy-based gateway
# against a 16-provider ceiling.
#
# Organizations puts tenants INSIDE a single realm. Each organization has its
# own members and its own federated identity provider — so a customer bringing
# their own IdP is brokered, and the token reaching the gateway is still issued
# by Keycloak. One issuer, tenant as a claim, issuer count flat as tenants grow.
#
# THE INVARIANT THIS EXISTS TO PRESERVE:
#   A tenant never appears in gateway configuration.
# If k8s-manifests/opa/policy-issuers.yaml starts gaining one entry per tenant,
# the topology has regressed and this is the thing to fix.
#
# ⚠ PROTOTYPE BEFORE COMMITTING. "3 realms per tenant" on the previous estate
# implies those realms encoded something — environments, brands, something.
# Whether that distinction survives a mapping onto organizations is the open
# risk, and it is a modelling question, not a deployment one. See
# aj-infra-context/arch/gateway-selection.md §5.
#
# ── Why this is off by default ───────────────────────────────────────────────
# Keycloak needs a database, and this estate has none: aj-tf-module-aurora has
# no consumer and no pipeline stage applies it (aj-infra-context#15), with the
# engine choice deliberately deferred (#17). Running it on the chart's
# dev-mode H2 would produce an identity provider that loses every user on
# restart, which is worse than not running it.
#
# ⚠ INCOMPLETE BY DESIGN. Database connection, hostname, TLS and admin
# bootstrap are NOT configured below. The keycloakx chart takes these through
# `command`, `extraEnv` and `database.*`, and the exact keys differ across chart
# majors. They are deliberately left out rather than guessed — a plausible-but-
# wrong Helm value passes terraform validate and fails at apply. Complete them
# against the pinned chart's own values.yaml when a database exists.
#
# Admin credentials must come from a Secret via External Secrets, never from
# Terraform variables — they would otherwise land in state.

resource "helm_release" "keycloak" {
  count = var.install_keycloak ? 1 : 0

  name       = "keycloak"
  repository = "https://codecentric.github.io/helm-charts"
  chart      = "keycloakx"
  version    = var.chart_version_keycloak
  namespace  = "keycloak"

  create_namespace = true

  # Production mode. The chart defaults to a dev-friendly start command; this
  # forces the optimized production build, which refuses to run without a real
  # database and a hostname — failing loudly rather than silently starting on
  # H2 and losing every user on the next restart.
  set {
    name  = "command[0]"
    value = "/opt/keycloak/bin/kc.sh"
  }

  set {
    name  = "command[1]"
    value = "start"
  }

  set {
    name  = "command[2]"
    value = "--optimized"
  }

  set {
    name  = "replicas"
    value = var.environment == "prod" ? "2" : "1"
  }

  set {
    name  = "resources.requests.cpu"
    value = "500m"
  }

  set {
    name  = "resources.requests.memory"
    value = "1Gi"
  }

  set {
    name  = "resources.limits.memory"
    value = "2Gi"
  }

  depends_on = [helm_release.cilium]
  wait       = true
  timeout    = 600
}
