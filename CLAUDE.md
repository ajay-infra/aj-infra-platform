# CLAUDE.md — aj-infra-platform

> Local context file for Claude Code, read automatically at session start.

---

## What This Repo Does

Central orchestrator for the platform's Kubernetes add-on layer (L5 — see `aj-infra-context/CLAUDE.md`).

Reads remote state from `aj-tf-module-eks` and installs all Kubernetes add-ons via Helm:

| Add-on | Chart | IAM | Toggle |
|---|---|---|---|
| **Cilium** | cilium/cilium | — | always on |
| **AWS LBC** | aws/aws-load-balancer-controller | Pod Identity | always on |
| **Karpenter** | karpenter/karpenter (OCI) | Pod Identity | `install_karpenter` |
| **cert-manager** | jetstack/cert-manager | — | `install_cert_manager` |
| **External Secrets** | external-secrets/external-secrets | Pod Identity | `install_external_secrets` |
| **metrics-server** | kubernetes-sigs/metrics-server | — | `install_metrics_server` |
| **OPA Gatekeeper** | open-policy-agent/gatekeeper | — | `install_gatekeeper` |
| **KEDA** | kedacore/keda | Pod Identity (SQS + CW) | `install_keda` |
| **APISIX** | apache/apisix | none (no AWS calls) | `install_apisix` |
| **OPA** | open-policy-agent/kube-mgmt | none | `install_opa` |
| **external-dns** | kubernetes-sigs/external-dns | Pod Identity (Route53) | `install_external_dns` |
| **ACK ACM + Route53** | aws-controllers-k8s | Pod Identity (ACM, Route53) | `install_ack_certificates` |
| **Falcon sensor** | crowdstrike/falcon-sensor | — | `install_falcon` |
| **ARC controller** | actions/gha-runner-scale-set-controller | Pod Identity | `install_arc` |

Also creates IAM policies + Pod Identity associations for every add-on that calls AWS APIs.

---

## Where It Fits

**Architecture layer:** L5 — K8s Add-ons
**Provisioned by:** `aj-infra-release` — `provision-eks.yml` (Stage 3, after EKS)
**Depends on:** `aj-tf-module-eks` state (reads via `data.terraform_remote_state.eks`)
**State key pattern:** `workload/<mode>/<env>/aj-infra-platform/terraform.tfstate`

## How to Use

Triggered automatically as Stage 3 of `provision-eks.yml` after the EKS stage completes. Requires a live EKS cluster (Helm provider calls `aws eks get-token`).

tfvars: `aj-infra-release/envs/workload/<mode>/<env>/common.tfvars` (passed via `-var-file`); color injected as `-var="color=..."` by the pipeline.

GitHub secrets required:
- `TF_STATE_BUCKET`, `AWS_DEPLOY_ROLE_ARN`

Current Helm releases installed: Cilium, AWS LBC, Karpenter, cert-manager, ESO, metrics-server, OPA Gatekeeper, KEDA, APISIX, external-dns, Falcon sensor, ARC controller — all 12, each verified to define a real `helm_release` resource (`keda.tf`, `apisix.tf`, `opa.tf`, `external-dns.tf`, `falcon.tf`, `arc.tf`, `gatekeeper.tf`, `helm.tf`).

Added 2026-08-28 and **off by default**: the ACK ACM + Route53 controllers
(`ack.tf`, `install_ack_certificates`). They are 13 and 14, but the toggle
defaults to `false` because enabling them adds a fifth writer to the shared
Route53 zone — a decision, not a default. See the ACK section below.

Still genuinely pending: Cloudability agent, Alloy (k8s-monitoring), ArgoCD agent registration. (This line previously listed KEDA/Kong/external-dns/Falcon as pending too — stale; see the detailed per-add-on TODOs below, which were accurate all along.)

---

## Apply Order (two-stage)

```
Stage 1: aj-tf-module-eks (separate repo)
  → creates EKS cluster, node groups, managed add-ons (without vpc-cni/kube-proxy)
  → writes state to S3: ${env}/eks-${color}/terraform.tfstate

Stage 2: infra-platform (this repo)
  → reads EKS state via data.terraform_remote_state.eks
  → creates IAM policies + pod identity associations
  → installs Helm releases
```

**Nodes stay NotReady until Cilium is installed** — this is expected. Cilium must be the first Helm release (`depends_on` chain enforces the rest).

---

## Files

| File | Purpose |
|---|---|
| `providers.tf` | AWS (5.100.0) + Helm (2.12.1) providers, pinned versions |
| `backend.tf` | S3 backend config (pass -backend-config at init) |
| `data.tf` | Remote state reads from EKS module |
| `variables.tf` | Environment, chart versions, add-on toggles |
| `locals.tf` | Shorthand aliases for remote state outputs |
| `iam.tf` | IAM policies + roles + Pod Identity associations per add-on |
| `helm.tf` | Cilium, AWS LBC, Karpenter, cert-manager, External Secrets, metrics-server Helm releases |
| `keda.tf` | KEDA Helm release + Pod Identity (SQS + CloudWatch scalers) |
| `apisix.tf` | APISIX gateway + ingress controller — north–south API gateway |
| `opa.tf` | Standalone OPA — authorization decision point APISIX calls |
| `external-dns.tf` | external-dns Helm release + Pod Identity (Route53) |
| `ack.tf` | ACK ACM + Route53 controllers — certificates as K8s resources. Off by default |
| `cert-manager-iam.tf` | cert-manager — Pod Identity for Route53 DNS-01 (ACME challenge TXT only) |
| `falcon.tf` | CrowdStrike Falcon sensor Helm release |
| `arc.tf` | Actions Runner Controller Helm release + Pod Identity |
| `gatekeeper.tf` | OPA Gatekeeper Helm release |
| `outputs.tf` | IAM role ARNs, installed chart versions |
| `versions.json` | Single source of truth for all pinned versions |
| `envs/*.tfvars` | Per-environment variable overrides |

---

## Key Design Decisions

- **Remote state not module call** — EKS and VPC are separate repos with their own state; infra-platform reads outputs via `data.terraform_remote_state`. This keeps blast radii separate.
- **Helm provider uses exec auth** — `aws eks get-token` via AWS CLI exec plugin. Requires valid AWS credentials at apply time. GitHub OIDC in CI.
- **Cilium values from EKS output** — `cilium_helm_values` output from the EKS module is consumed directly. No duplication of values.
- **Add-on toggles** — `install_karpenter`, `install_cert_manager`, etc. let dev environments skip expensive or unnecessary add-ons.
- **versions.json** — single source of truth for all chart versions. Keep in sync with `variables.tf` defaults.

---

## Running Locally

```bash
# from aj-infra-context/local-testing/ (formerly My-Infra/ — repo renamed;
# this Podman workflow currently has no Makefile/Dockerfile, see that repo's
# local-testing/README.md for the known gap)
make shell

# Inside container — requires real AWS credentials for Helm to connect
cd /workspaces/infra-platform
terraform init \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=dev/aj-infra-platform/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

---

## Known TODOs

- [ ] Karpenter NodePool + EC2NodeClass manifests live in k8s-manifests (not here)
- [ ] SQS queue for Karpenter spot interruption handler — create in aj-infra-release, pass ARN via var
- [ ] Wire VPC ID into AWS LBC properly (currently using subnet[0] as placeholder)
- [ ] Falcon `install_falcon = true` in dev/staging once CID is stored in Secrets Manager
- [ ] external-dns `domain_filter` — set to actual hosted zone once Route53 zone is created
- [ ] Kong: add Valkey connection details for rate-limiting-advanced plugin via ESO secret

---

## ACK certificate controllers (`ack.tf`)

Two controllers, one toggle, and the reason is not stylistic: **the ACM
controller does not write DNS validation records.** It requests the certificate
and waits for validation it cannot perform; AWS's documentation points at the
separate Route53 controller for the CNAMEs. Deploying acm alone leaves every
public certificate in `PENDING_VALIDATION` indefinitely. So `install_ack_certificates`
governs both, and `route53_hosted_zone_id` is required when it is on — enforced
by a plan-time precondition, since Terraform variable validation cannot see
another variable.

### `spec.exportTo` is forbidden, and IAM cannot enforce that

`exportTo` makes a certificate an **exportable** public certificate: **$7 per
FQDN and $79 per wildcard, charged at issuance AND at every renewal** on a
198-day validity — roughly **$158/year** for a single wildcard. Standard ACM
certificates are free.

There is no IAM condition key for the export option. ACM supports only
`ValidationMethod`, `DomainNames`, `KeyAlgorithm`, `CertificateTransparencyLogging`
(deprecated), `CertificateAuthority` and `CertificateKeyPairOrigin` on
`RequestCertificate` — none sees it. And the charge lands at **issuance**, not
at export, so withholding `acm:ExportCertificate` stops the private key leaving
but does **not** stop the bill.

The enforcement point is therefore admission control:
`k8s-manifests/policies/constraints/deny-acm-exportable.yaml`, cluster-wide and
unconditional, with `gator` tests in both directions. The one case `exportTo`
serves — in-cluster TLS termination — is already covered free by cert-manager.

`acm:ExportCertificate` is still withheld from the controller's role as defence
in depth. That is not the cost control, and the comment in `ack.tf` says so.

### The fifth Route53 writer is bounded by IAM, not by configuration

Session 7's external-dns incident was a DNS writer holding deletion rights over
records it did not create. The ACK Route53 controller's policy is scoped three
ways at once — CNAME records only, names beginning `_`, and `CREATE`/`UPSERT`
with no `DELETE` — plus a single hosted zone. It cannot remove a record even if
compromised. Full ownership table in `aj-platform-gitops/CLAUDE.md`.

---

## APISIX + OPA replaced Kong (2026-08-28)

Full rationale in `aj-infra-context/arch/gateway-selection.md`. What matters when
touching these files:

**Kong OSS could not do what this repo's config claimed.** `kong.tf` advertised
"JWT/OIDC auth"; `openid-connect`, the OPA plugin, the developer portal and Kong
Manager are all Enterprise-gated. The configured OSS `jwt` plugin resolved `kid`
against `KongConsumer` objects, of which there were zero.

**Envoy Gateway was evaluated and rejected on operational evidence**, not on
features: a prior estate OOM-killed it with ~24 JWT issuers in one namespace
against a 16-provider ceiling. APISIX has no xDS config plane, so that class of
failure cannot recur.

### The rule that must never be broken

> **A tenant never appears in gateway configuration.**

Tenants are JWT claims and OPA policy data. Per-tenant state in the proxy config
plane scales O(tenants × proxies) and is exactly what caused that OOM. If a
change would add a per-tenant entry to `apisix.tf` or to a `SecurityPolicy`-like
object, it is the wrong change.

### Why OPA verifies JWTs rather than the gateway

Verification in OPA (`io.jwt.decode_verify` + `allowed_issuers`) makes **issuers
data instead of configuration**. Adding a tenant is a policy-data refresh, not a
proxy rollout, and no provider ceiling exists to hit. The APISIX `opa` plugin
forwards request headers, so OPA sees the `Authorization` header and does
verification and authorization in one decision.

Consequence worth keeping: API keys and JWTs are different *authentication*
mechanisms that both feed the *same* policy. One authorization surface.

### This OPA is not Gatekeeper

Gatekeeper is OPA embedded in an admission controller and does not expose the
Data API (`/v1/data/...`) the APISIX plugin queries. Same language, different
deployment, different job — admission control on Kubernetes objects vs
authorization on API requests. Do not try to point one at the other.
