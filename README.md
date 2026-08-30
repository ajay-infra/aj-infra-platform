# aj-infra-platform

Central orchestrator for the platform's Kubernetes add-on layer. Reads remote state from `aj-tf-module-eks` and installs every cluster add-on via Helm, plus the IAM policies and Pod Identity associations each one needs to call AWS APIs.

L5 in the platform's infrastructure layer stack — see `aj-infra-context/CLAUDE.md` for the full picture.

---

## Add-ons installed

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

All 12 install via real `helm_release` resources — see `helm.tf` (Cilium/AWS LBC/Karpenter/cert-manager/External Secrets/metrics-server) and the per-add-on files (`keda.tf`, `apisix.tf`, `opa.tf`, `external-dns.tf`, `falcon.tf`, `arc.tf`, `gatekeeper.tf`).

`versions.json` is the single source of truth for chart versions — keep it in sync with `variables.tf` defaults and `envs/*.tfvars`.

---

## Apply order (two-stage)

```
Stage 1: aj-tf-module-eks (separate repo)
  → creates EKS cluster, node groups, managed add-ons (without vpc-cni/kube-proxy)
  → writes state to S3: ${env}/eks-${color}/terraform.tfstate

Stage 2: aj-infra-platform (this repo)
  → reads EKS state via data.terraform_remote_state.eks
  → creates IAM policies + Pod Identity associations
  → installs Helm releases
```

Triggered automatically as Stage 3 of `aj-infra-release`'s `provision-eks.yml`, after the EKS stage completes. Requires a live EKS cluster — the Helm provider authenticates via `aws eks get-token` exec auth.

**Nodes stay `NotReady` until Cilium is installed** — this is expected. Cilium is the first Helm release; the `depends_on` chain enforces the rest install after it.

---

## Usage

tfvars come from `aj-infra-release/envs/workload/<mode>/<env>/common.tfvars`, passed via `-var-file`; `color` is injected as `-var="color=..."` by the pipeline. Per-environment overrides also live in this repo's own `envs/*.tfvars` (`dev.tfvars`, `staging.tfvars`, `prod-blue.tfvars`).

```bash
terraform init \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=dev/aj-infra-platform/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

GitHub secrets required in CI: `TF_STATE_BUCKET`, `AWS_DEPLOY_ROLE_ARN`.

---

## Files

| File | Purpose |
|---|---|
| `providers.tf` | AWS (5.100.0) + Helm (2.12.1) providers, pinned versions |
| `backend.tf` | S3 backend config (pass `-backend-config` at init) |
| `data.tf` | Remote state read from the EKS module |
| `variables.tf` | Environment, chart versions, add-on toggles |
| `locals.tf` | Shorthand aliases for remote state outputs |
| `iam.tf` | IAM policies + roles + Pod Identity associations per add-on |
| `helm.tf` | Cilium, AWS LBC, Karpenter, cert-manager, External Secrets, metrics-server |
| `keda.tf` | KEDA — Pod Identity for SQS + CloudWatch scalers |
| `apisix.tf` | APISIX gateway + ingress controller — north–south API gateway |
| `opa.tf` | Standalone OPA — authorization decision point APISIX calls |
| `external-dns.tf` | external-dns — Pod Identity for Route53 |
| `ack.tf` | ACK ACM + Route53 controllers — certificates as K8s resources. Off by default |
| `cert-manager-iam.tf` | cert-manager — Pod Identity for Route53 DNS-01 (ACME challenge TXT only) |
| `falcon.tf` | CrowdStrike Falcon sensor |
| `arc.tf` | Actions Runner Controller — Pod Identity |
| `gatekeeper.tf` | OPA Gatekeeper |
| `outputs.tf` | IAM role ARNs, installed chart versions map |
| `versions.json` | Single source of truth for all pinned versions |
| `envs/*.tfvars` | Per-environment variable overrides |

---

## Key design decisions

- **Remote state, not a module call** — EKS and VPC are separate repos with their own state; this module reads outputs via `data.terraform_remote_state`, keeping blast radii separate.
- **Helm provider uses exec auth** — `aws eks get-token` via the AWS CLI exec plugin. Requires valid AWS credentials at apply time (GitHub OIDC in CI).
- **Cilium values from EKS output** — `cilium_helm_values` from the EKS module is consumed directly, no duplication.
- **Add-on toggles** — `install_karpenter`, `install_cert_manager`, etc. let dev environments skip expensive or unnecessary add-ons (see `envs/dev.tfvars` for what's on/off by default).

---

## Provider pins

| Tool | Version |
|---|---|
| Terraform | `= 1.10.5` |
| AWS provider | `= 5.100.0` |
| Helm provider | `2.12.1` |

---

## Known TODOs

- [ ] Karpenter NodePool + EC2NodeClass manifests live in `aj-cluster-baseline`, not here
- [ ] SQS queue for Karpenter spot interruption handler — create in `aj-infra-release`, pass ARN via var
- [ ] Wire VPC ID into AWS LBC properly — currently uses `data.terraform_remote_state.eks.outputs.active_private_subnets[0]` (a subnet ID) as a placeholder for `vpcId`
- [ ] `install_falcon = true` in dev/staging once the Falcon CID is stored in Secrets Manager
- [ ] `external_dns_domain_filter` — set to the real hosted zone once Route53 is created
- [ ] Kong: wire Valkey connection details for the `rate-limiting-advanced` plugin via an ESO secret
- [ ] Still genuinely missing (not yet started): Cloudability agent, Alloy (k8s-monitoring), ArgoCD agent registration
