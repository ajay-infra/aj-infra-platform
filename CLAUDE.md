# CLAUDE.md — aj-infra-platform

> Local context file for Claude Code. Not pushed to GitHub.

---

## What This Repo Does

Central orchestrator for the AI Search Engine infrastructure platform layer (L4 in the roadmap).

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
| **Kong KIC** | kong/ingress | — | `install_kong` |
| **external-dns** | kubernetes-sigs/external-dns | Pod Identity (Route53) | `install_external_dns` |
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

Current Helm releases installed: Cilium, AWS LBC, Karpenter, cert-manager, ESO, metrics-server, OPA Gatekeeper.

Pending additions (Group 3 roadmap item): KEDA, Kong (KIC), external-dns, Falcon sensor, Cloudability agent, Alloy (k8s-monitoring), ArgoCD agent registration.

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
| `helm.tf` | All Helm releases in install order |
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
# From My-Infra/
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
