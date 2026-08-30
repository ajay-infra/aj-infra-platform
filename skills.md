# skills.md — aj-infra-platform

## Purpose
Installs the Kubernetes add-on layer onto an EKS cluster via Helm: Cilium, AWS LBC, Karpenter, cert-manager, External Secrets, metrics-server, OPA Gatekeeper, KEDA, Kong KIC, external-dns, Falcon sensor, ARC controller. Reads EKS cluster details from `aj-tf-module-eks` remote state rather than a module call.

## Type
`tf-module` (remote-state consumer, not a reusable `source =` module in the usual sense — always applied against a specific cluster's state)

## Stable ref
```
source = "github.com/ajay-infra/aj-infra-platform?ref=v1.0.0"
```
Note: `v1.0.0` (2026-03-29) only covers the original 6 add-ons (Cilium, AWS LBC, Karpenter, cert-manager, ESO, metrics-server). KEDA, Kong, Gatekeeper, external-dns, Falcon, and ARC all landed later and are unreleased — pin `main` if you need them until a new tag is cut.

## Key inputs
| Variable | Description |
|---|---|
| `environment` | dev \| staging \| prod |
| `color` | blue \| green |
| `state_bucket` / `eks_state_key` | Where to read EKS remote state from |
| `install_<addon>` | Per-add-on toggle (karpenter, cert_manager, external_secrets, metrics_server, gatekeeper, keda, kong, external_dns, falcon, arc, ack_certificates) |
| `chart_version_<addon>` | Per-add-on Helm chart version — keep in sync with `versions.json` |
| `external_dns_domain_filter` | Root domain external-dns manages |
| `route53_hosted_zone_id` | Zone the ACK Route53 controller may write ACM validation CNAMEs into. Required when `install_ack_certificates` is true |
| `team`, `cost_center`, `tags` | Standard tagging |

## Key outputs
| Output | Description |
|---|---|
| `cluster_name` / `cluster_endpoint` | Passed through from EKS remote state |
| `aws_lbc_role_arn` | AWS LBC Pod Identity role |
| `karpenter_role_arn`, `external_secrets_role_arn`, `keda_role_arn`, `external_dns_role_arn` | Per-add-on Pod Identity roles (null if that add-on is toggled off) |
| `installed_helm_releases` | Map of release name → chart version, built from the active toggles |

## Depends on
`aj-tf-module-eks` — reads its state via `data.terraform_remote_state.eks` (not a module call). Requires a live EKS cluster at apply time (Helm provider uses `aws eks get-token` exec auth).

## AWS tags applied
On this module's own IAM resources: `team`, `cost_center`, plus whatever's in `var.tags`. Not to be confused with per-add-on Pod Identity role tags, which follow the same pattern.

## Branching convention
- `main` — active development, ahead of the last tag
- semver tags (`v1.0.0`, ...) — stable pinned releases, currently behind `main` by 6 add-ons (see Stable ref note above)

## CI checks
fmt, validate (no plan — this module depends on live remote state, so a meaningful dry-run plan isn't possible without a real EKS cluster), security scan

## Agentic capabilities
- Detect chart version drift between `versions.json` and `variables.tf`/`envs/*.tfvars`
- Flag add-ons with `install_* = true` but no corresponding IAM/Pod Identity wiring
- Validate `external_dns_domain_filter` isn't empty before enabling `install_external_dns` in a real environment
- `install_ack_certificates` installs BOTH the ACM and Route53 controllers — the
  ACM controller cannot validate its own certificates, so acm alone leaves every
  public cert in `PENDING_VALIDATION`. Requires `route53_hosted_zone_id`.
- **Never set `spec.exportTo` on an ACK `Certificate`.** It requests an
  exportable certificate at $7/FQDN and $79/wildcard, charged at issuance AND
  every renewal (~$158/yr per wildcard). Blocked cluster-wide by the
  `deny-acm-exportable` Gatekeeper constraint in `aj-cluster-baseline`. cert-manager
  does in-cluster TLS for free.
- Cross-check this repo's "installed add-ons" status against `aj-infra-context/CLAUDE.md`'s roadmap and flag drift
