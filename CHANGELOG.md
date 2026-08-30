# Changelog

All notable changes to this module are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Fixed — every platform namespace was created unlabelled, and three things broke quietly
Eleven namespaces were created by `create_namespace = true` on a `helm_release`, which produces a namespace with **no labels at all**.

- **The platform could not install itself onto a cluster running its own policies.** `require-cost-labels` and `require-segment-label` are both at `deny` and exclude only `kube-system`, `kube-public`, `kube-node-lease`, `default` and `gatekeeper-system` — so nine of these namespaces would have been rejected at admission.
- **Every platform component was fail-open to Cilium.** The `CiliumNetworkPolicy` set selects on `io.cilium.k8s.namespace.labels.platform.aj/segment`, and Cilium leaves an endpoint unrestricted until a policy selects it. No label, no policy, full connectivity — **including `apisix`, the internet-facing edge**. The segmentation work was inert for the components it was designed around.
- **Container cost was attributable no further than "this cluster".**

Namespaces are now declared in `namespaces.tf` from a single `platform_components` map, and each `helm_release` references the namespace resource rather than naming it as a string — so the dependency is implicit and cannot be forgotten.

### Added — `platform_components`, one map behind three things that used to disagree
Namespace labels, the `Application` tag on AWS resources, and which `CiliumNetworkPolicy` selects a component all derive from the same entry. `segment` is **stated, never defaulted** — `apisix` is `edge` and everything else is `platform`, and no default can know that.

### Changed — `falcon-system` ownership moved here, with all of its labels
It was declared in `aj-cluster-baseline` **and** created by Helm, so whichever landed first decided whether it had labels. Terraform installs Falcon, so Terraform now declares it — and it carries the Pod Security and Gatekeeper-exemption labels the aj-cluster-baseline version had. An EDR sensor needs host PID, host network and elevated capabilities, so `restricted` would defeat its purpose and `no-privileged-containers` would reject its DaemonSet. Moving the namespace without them would have broken the sensor silently. Its `team` label changes from `platform` to `infra-core`, which is what this repo's `var.team` says.

### Added — Pod Security `audit` and `warn` on every platform namespace
`enforce` is deliberately left unset. A wrong enforce level **blocks** the component, and the charts cannot be fetched offline to confirm what each one needs; audit and warn surface the same information in the log without that risk. `falcon-system` is the exception and states its own.

### Added — `Application` tag on all 27 taggable AWS resources
Nine components own IAM (`ack_acm`, `ack_route53`, `arc_runner`, `aws_lbc`, `cert_manager`, `external_dns`, `external_secrets`, `karpenter`, `keda`), and every one of their roles, policies and Pod Identity associations carried an **identical tag set**. The only thing distinguishing cert-manager's role from karpenter's was the resource *name*, which is not a queryable tag.

### Fixed — the `Environment` tag carried values in no vocabulary
`full_tags` set `Environment = var.environment`, which is the cluster slug (`dev`, `staging`, `prod`). Two of those three stopped being stages in the 2026-08-28 migration. `var.environment` is load-bearing for resource names and the remote state key so it cannot be renamed; a new `stage` variable carries the tag value instead, validated against the five-value vocabulary. `prod-blue.tfvars` had been overriding `Environment` by hand — the tell that this was already known to be wrong.

### Fixed — stale identifiers
`Project` was `ai-search` and `Repository` was `infra-platform`. Both now `aj-infra-platform`. `Class = platform` and `Customer = internal` added, which begins the emit side the SaaS tag guardrail is waiting on.

### Known gap — scheduling is not wired
Every Karpenter NodePool taints `platform.aj/segment: NoSchedule`, and exactly one Helm release (falcon) sets a toleration. The `platform` NodePool therefore cannot receive the add-ons it was built for; they land on the managed general node group. **Not fixed here on purpose:** the toleration value path differs per chart, a wrong `helm_release` `set` path silently does nothing, and the charts cannot be fetched offline to confirm. Guessing would ship exactly the kind of rule-that-no-ops this change exists to remove.

### Added
- **Keycloak (`keycloak.tf`, `keycloakx` 7.3.0 / app 26.7.2), off by default.** The identity provider that issues the tokens OPA verifies. Chosen over Zitadel and Cognito because it is already proven in operation here, and because **Organizations** (GA in Keycloak 26) solves the exact failure that shaped the API layer.
  - **Why Organizations is the point:** a prior estate ran realm-per-tenant and reached ~24 issuers in one namespace, OOM-killing an Envoy-based gateway against a 16-provider ceiling. Organizations puts tenants *inside a single realm*, each with its own members and its own federated IdP — so a customer bringing their own IdP is brokered and the token reaching the gateway is still Keycloak-issued. One issuer, tenant as a claim, issuer count flat as tenants grow.
  - **⚠ Prototype before committing.** "3 realms per tenant" on the previous estate implies those realms encoded something — environments, brands. Whether that distinction survives a mapping onto organizations is a modelling question and the open risk. See `aj-infra-context/arch/gateway-selection.md` §5.
  - **Off by default because there is no database.** `aj-tf-module-aurora` has no consumer (`aj-infra-context#15`) and the engine choice is deferred (`#17`). The release is configured for production mode (`start --optimized`), so it refuses to run without a real database rather than silently starting on H2 and losing every user on restart.
  - **Deliberately incomplete.** Database connection, hostname, TLS and admin bootstrap are *not* configured — the keycloakx chart takes these through `command`, `extraEnv` and `database.*`, and keys differ across chart majors. Left out rather than guessed: a plausible-but-wrong Helm value passes `terraform validate` and fails at apply. Admin credentials must arrive via External Secrets, never Terraform variables, or they land in state.

### Changed — BREAKING
- **Kong replaced by Apache APISIX + standalone OPA** (`apisix.tf`, `opa.tf`; `kong.tf` removed). Full rationale in `aj-infra-context/arch/gateway-selection.md`; the decision is LOCKED there.
  - **Kong OSS could not do what this repo's own config claimed.** `kong.tf` advertised "JWT/OIDC auth" — `openid-connect`, the OPA plugin, the developer portal and Kong Manager are all Enterprise-gated. The configured OSS `jwt` plugin resolves `kid` against `KongConsumer` objects, of which there were zero, so it could not carry per-user identity at all.
  - **Envoy Gateway was evaluated and rejected on operational evidence rather than features.** A prior estate OOM-killed it with ~24 JWT issuers in one namespace against a 16-provider ceiling. APISIX has no xDS config plane, so that class of failure cannot recur.
  - `opa` and `openid-connect` ship in the APISIX OSS build, so no licence gates the authorization design. `ApisixConsumer` provides API keys and per-consumer quotas as CRDs, replacing key management that had been hand-rolled in Python on the previous estate.
  - The APISIX Ingress Controller supports **Gateway API** alongside its own CRDs, so config stays as GitOps-native as any Envoy-based option.
- **`install_kong` / `chart_version_kong` → `install_apisix`, `install_opa`, `chart_version_apisix`, `chart_version_apisix_ingress`, `chart_version_opa`.** All three env tfvars updated; `outputs.tf` chart-version map updated.

### Added — the invariant this design rests on
- **A tenant never appears in gateway configuration.** Tenants are JWT claims and OPA policy data. Per-tenant state in the proxy config plane scales O(tenants × proxies) and is precisely what caused the OOM above. Documented at the top of `apisix.tf` and in `CLAUDE.md`.
- **JWT verification happens in OPA, not at the gateway.** `io.jwt.decode_verify` with `allowed_issuers` makes issuers *data* rather than configuration — adding a tenant becomes a policy-data refresh, not a proxy rollout, and no provider ceiling exists to hit. The APISIX `opa` plugin forwards request headers, so OPA receives the `Authorization` header and performs verification and authorization in a single decision. Consequence: API keys and JWTs are different *authentication* mechanisms feeding the *same* policy — one authorization surface, not two.
- **This OPA is not Gatekeeper.** Gatekeeper is OPA embedded in an admission controller and does not expose the Data API (`/v1/data/...`) the APISIX plugin queries. Same language, different deployment, different job. `admissionController.enabled=false` is set explicitly so the two never contend for the same webhooks.
- OPA runs 3 replicas in prod: an authorization decision sits in the request path of every API call, so a single-replica deployment would be a single point of failure for the entire API surface.

### Fixed
- **cert-manager had no IAM role and no Pod Identity association, so its DNS-01 solver had no AWS credentials.** `aj-cluster-baseline/cert-manager/clusterissuer-prod.yaml` states it uses EKS Pod Identity and notes "cert-manager Pod Identity role must have Route53 write access" — eight associations existed here and cert-manager was not one of them; its Helm release set only `installCRDs` and leader election.
  - Consequence, end to end: no `_acme-challenge` TXT records → Let's Encrypt never validates → Secret `kong-wildcard-tls` never created → Kong has no certificate → CloudFront's `origin_protocol_policy = "https-only"` connection to the origin fails → **nothing serves TLS**. DNS-01 is not optional here: Let's Encrypt will not issue a wildcard over HTTP-01, and `certificate-kong-wildcard.yaml` requests one.
  - **cert-manager is the one Route53 writer that legitimately needs `DELETE`** — it creates a challenge record, validates, and cleans up. So the bound cannot come from the action list. It comes from record **type and name** instead: `TXT` only, names matching `_acme-challenge*`. Even holding DELETE it cannot touch a CNAME, which covers Terraform's `blue.`/`green.`/`active.`/apex records, every external-dns workload record, and every ACM validation CNAME from the ACK Route53 controller.
  - `Resource` narrows to `route53_hosted_zone_id` when set and is `hostedzone/*` until then. Wider than ideal, but far less permissive than it looks — the type and name conditions still restrict it to ACME challenge records in any zone. It is written this way because `install_cert_manager` defaults true and is set in all three env tfvars, none of which has a zone id yet; requiring one would break every existing environment at plan time.
  - `helm_release.cert_manager` now `depends_on` the association, so the first reconcile cannot run without credentials.
  - Closes the §7 gap 1 recorded in `aj-infra-context/arch/tls-and-edge.md`.

### Added
- **ACK ACM + Route53 controllers (`ack.tf`), off by default** behind `install_ack_certificates`. Certificates become Kubernetes resources rather than Terraform ones, which breaks the dependency cycle where the ACM cert was trapped inside the CloudFront stage — CloudFront needs the ALB's DNS, and an ALB with HTTPS needs a cert that only existed after CloudFront ran.
  - **Both controllers, one toggle, by necessity.** The ACM controller does **not** write DNS validation records; it requests the certificate and then waits for validation it cannot perform. AWS's documentation points at the separate Route53 controller for the CNAMEs, so installing acm alone leaves every public certificate in `PENDING_VALIDATION` indefinitely. An earlier note in `aj-platform-gitops/CLAUDE.md` credited the ACM controller with writing its own validation records — that was wrong and is corrected there.
  - **Off by default** because enabling it adds a **fifth writer** to the shared Route53 zone. That is a decision, not a default.
  - `route53_hosted_zone_id` is required when enabled, enforced by a plan-time `precondition` — Terraform variable validation cannot reference another variable.
- **The fifth Route53 writer is bounded by IAM rather than by chart configuration.** Session 7's external-dns incident was a DNS writer holding deletion rights over records it did not create, one edited value away from removing production records. The ACK Route53 policy is scoped three ways simultaneously — `ChangeResourceRecordSetsRecordTypes` = CNAME only, `ChangeResourceRecordSetsNormalizedRecordNames` = names beginning `_`, `ChangeResourceRecordSetsActions` = CREATE/UPSERT with **no DELETE** — plus a single hosted zone in `Resource`. It cannot remove a record even if compromised. (Noted in-file: `ForAllValues` evaluates true when the key is absent, so this shape must not be copied onto an action that does not populate these keys.)
- `acm:RequestCertificate` is conditioned on `acm:ValidationMethod = DNS`, so a certificate can never fall back to EMAIL validation and wait on a human clicking a link.

### Note — `spec.exportTo` is forbidden, and IAM cannot enforce it
`exportTo` requests an **exportable** public certificate: **$7 per FQDN and $79 per wildcard, charged at issuance AND at every renewal** on a 198-day validity — roughly **$158/year** per wildcard. Standard ACM certificates are free.

There is no IAM condition key for the export option — `RequestCertificate` supports only `ValidationMethod`, `DomainNames`, `KeyAlgorithm`, `CertificateTransparencyLogging` (deprecated), `CertificateAuthority` and `CertificateKeyPairOrigin`. And the charge lands at **issuance**, not at export, so withholding `acm:ExportCertificate` prevents the private key leaving but does **not** prevent the spend.

Enforcement is therefore admission control: `deny-acm-exportable` in `aj-cluster-baseline`, cluster-wide and unconditional, with `gator` tests in both directions. `acm:ExportCertificate` is still withheld from the role as defence in depth, which `ack.tf` is explicit is *not* the cost control.

### Fixed
- `terraform fmt` failures in `envs/dev.tfvars`, `envs/prod-blue.tfvars`, `envs/staging.tfvars`, `external-dns.tf`, `falcon.tf`, `outputs.tf` — pre-existing (predates this PR entirely; none of these files were touched by anything else in this changeset), and CI's `Format` job was failing on `main` as a result. This PR is apparently the first to actually trigger `pull_request` CI in a while, surfacing it. Whitespace/alignment only, no semantic changes — ran `terraform fmt -recursive`.
- `CLAUDE.md`'s "Pending additions" summary claimed KEDA, Kong, external-dns, and Falcon sensor were still pending. All four are fully implemented — verified each defines a real `helm_release` resource (`keda.tf`, `kong.tf`, `external-dns.tf`, `falcon.tf`), and `versions.json` pins all their chart versions. ARC controller (`arc.tf`) is also fully implemented but wasn't even mentioned in the pending list. This also means the central `aj-infra-context/CLAUDE.md` roadmap's priority-#1 item ("Update aj-infra-platform... blocks full workload cluster operation") is largely already done — flagged separately for a fix there too.
  - Root cause, from git history: `cfe37d8` ("docs: update CLAUDE.md across all repos") landed, then `bec5a8d` ("feat: add KEDA, Kong, Gatekeeper, external-dns, Falcon") merged right after — the docs commit's snapshot was obsoleted almost immediately and never revisited.
  - The detailed per-add-on TODO list below the summary line was **not** stale — verified all 5 items still accurately open (AWS LBC still uses `active_private_subnets[0]` as a VPC ID placeholder, `install_falcon` defaults `false`, `external_dns_domain_filter` defaults empty, no Valkey/ESO wiring in `kong.tf`). Only Cloudability agent, Alloy, and ArgoCD agent registration are genuinely still missing.
- `CLAUDE.md`'s "Files" table was missing 6 files that already existed: `keda.tf`, `kong.tf`, `external-dns.tf`, `falcon.tf`, `arc.tf`, `gatekeeper.tf`. Added.
- `CLAUDE.md` opened with "Central orchestrator for the AI Search Engine infrastructure platform layer" — generalized to describe the module itself, not one specific product (same reasoning as the equivalent fixes in `aj-tf-module-vpc`/`aj-tf-module-eks`).
- `CLAUDE.md`'s "Running Locally" pointed at `My-Infra/ make shell` — repo since renamed to `aj-infra-context`; that Podman workflow currently has no `Makefile`/`Dockerfile` (documented gap, not fixed here).
- `CLAUDE.md` claimed "Not pushed to GitHub" — inaccurate (it obviously is, this is a git-tracked file); corrected.

### Added
- `README.md` — none existed. Covers the add-on table, apply order, usage, files, design decisions, provider pins, and TODOs.
- `skills.md` — none existed, meaning this repo had no context source for `aj-agent-farm`'s two-source context model. Notes the module's real dependency on live EKS remote state (no meaningful dry-run plan is possible, unlike other tf-module repos), and that `v1.0.0` is well behind `main` (6 add-ons landed after the last tag).

## [v1.0.0] - 2026-03-29

Initial release — Cilium, AWS LBC, Karpenter, cert-manager, External Secrets, metrics-server. IAM policies + Pod Identity associations for each. Everything else (Gatekeeper, KEDA, Kong, external-dns, Falcon, ARC) landed after this tag and is unreleased.
