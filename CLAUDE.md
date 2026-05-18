# CLAUDE.md — aj-infra-platform

> Local context file for Claude Code. Not pushed to GitHub.

---

## What This Repo Does

Central orchestrator for the AI Search Engine infrastructure platform layer (L4 in the roadmap).

Reads remote state from `aj-tf-module-eks` and installs all Kubernetes add-ons via Helm:
- **Cilium** — overlay CNI (replaces vpc-cni + kube-proxy from EKS module)
- **AWS Load Balancer Controller** — provisions ALB/NLB for Ingress resources
- **Karpenter** — node autoscaler (replaces cluster-autoscaler)
- **cert-manager** — TLS cert automation (Let's Encrypt + ACM)
- **External Secrets Operator** — syncs AWS Secrets Manager / SSM → K8s Secrets
- **metrics-server** — enables HPA and `kubectl top`

Also creates:
- IAM policies for each add-on
- Pod Identity associations (binds IAM roles to K8s service accounts)

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

- [ ] Karpenter NodePool + EC2NodeClass manifests (go in k8s-manifests, not here)
- [ ] OPA Gatekeeper Helm release + base policy bundle
- [ ] Grafana LGTM stack (move to aj-tf-module-observability when ready)
- [ ] SQS queue for Karpenter spot interruption handler
- [ ] VPC ID wired into AWS LBC (currently using subnet[0] as placeholder — fix when vpc remote state is read)
