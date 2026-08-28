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
# Keycloak needs a database and this estate has none. Running it on the chart's
# dev-mode H2 would produce an identity provider that loses every user on
# restart, which is worse than not running it.
#
# The engine is DECIDED: Aurora PostgreSQL. This is platform infrastructure, so
# it does NOT wait on aj-infra-context#17, which defers the *application*
# data-tiering choice. What it does wait on (aj-infra-context#24):
#
#   * a pipeline stage that applies aj-tf-module-aurora — none exists (#15),
#     and this is its first real consumer
#   * a DEDICATED cluster, not the application one. If the app database is down
#     and Keycloak shares it, you cannot authenticate in order to fix anything.
#     An IdP must not inherit the availability of what it protects.
#   * RIGHT-SIZED: db.t4g.medium + 1 replica is about $117/mo. Copying the
#     application shape (db.r8g.xlarge + 2) would be roughly $1,280/mo for
#     realms, users and sessions. The dedicated-vs-shared argument is worth
#     ~$117/mo; it is not worth $1,280.
#
# UNRESOLVED, AND BLOCKING: aj-tf-module-aurora sets enable_iam_auth = true per
# a 2026-03-31 standing decision — pods use 15-minute rotating rds-db:connect
# tokens, never static passwords. KEYCLOAK CANNOT DO THIS out of the box: its
# JDBC connection is configured at startup with no token-refresh mechanism.
# Either the AWS Advanced JDBC Driver goes into the image (a build), or a static
# password comes from Secrets Manager via External Secrets (an explicit,
# recorded exception to that decision). Decide before enabling — see #24.
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
