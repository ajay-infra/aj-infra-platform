# ── Core ──────────────────────────────────────────────────────────────────────

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name: dev | staging | prod"
}

variable "color" {
  type        = string
  description = "Active cluster color: blue | green | standalone"
  default     = "blue"
  validation {
    condition     = contains(["blue", "green", "standalone"], var.color)
    error_message = "color must be 'blue', 'green', or 'standalone'."
  }
}

# ── Remote State ──────────────────────────────────────────────────────────────

variable "state_bucket" {
  type        = string
  description = "S3 bucket holding Terraform state for all modules"
}

variable "eks_state_key" {
  type        = string
  description = "S3 key for the EKS module state file"
  # default follows the pattern: <env>/eks-<color>/terraform.tfstate
  # Override if your key structure differs
  default = ""
}

# ── Helm Chart Versions ───────────────────────────────────────────────────────
# Pin all chart versions here. Keep in sync with versions.json.

variable "chart_version_cilium" {
  type    = string
  default = "1.17.0"
}

variable "chart_version_aws_lbc" {
  type        = string
  description = "AWS Load Balancer Controller Helm chart version"
  default     = "1.10.0"
}

variable "chart_version_karpenter" {
  type    = string
  default = "1.2.0"
}

variable "chart_version_cert_manager" {
  type    = string
  default = "v1.16.2"
}

variable "chart_version_external_secrets" {
  type    = string
  default = "0.11.0"
}

variable "chart_version_metrics_server" {
  type    = string
  default = "3.12.2"
}

# ── Add-on Toggles ────────────────────────────────────────────────────────────
# Disable add-ons not needed in dev to save cost and complexity

variable "install_karpenter" {
  type        = bool
  description = "Install Karpenter node autoscaler. Disable in dev if not needed."
  default     = true
}

variable "install_cert_manager" {
  type    = bool
  default = true
}

variable "install_external_secrets" {
  type    = bool
  default = true
}

variable "install_metrics_server" {
  type    = bool
  default = true
}

variable "install_arc" {
  type        = bool
  description = "Install Actions Runner Controller — self-hosted GitHub Actions runners on EKS."
  default     = false
}

variable "install_gatekeeper" {
  type        = bool
  description = "Install OPA Gatekeeper admission controller. ConstraintTemplates + Constraints live in k8s-manifests."
  default     = true
}

variable "install_keda" {
  type        = bool
  description = "Install KEDA event-driven autoscaler. ScaledObjects live in k8s-manifests."
  default     = true
}

variable "install_kong" {
  type        = bool
  description = "Install Kong Ingress Controller. KongPlugin CRDs live in k8s-manifests."
  default     = true
}

variable "install_external_dns" {
  type        = bool
  description = "Install external-dns for automated Route53 record management."
  default     = true
}

variable "install_falcon" {
  type        = bool
  description = "Install CrowdStrike Falcon sensor DaemonSet. Requires ESO secret 'falcon-credentials' in falcon-system namespace."
  default     = false
}

# ── Chart versions ────────────────────────────────────────────────────────────

variable "chart_version_arc_controller" {
  type    = string
  default = "0.9.3"
}

variable "chart_version_gatekeeper" {
  type    = string
  default = "v3.17.1"
}

variable "chart_version_keda" {
  type    = string
  default = "2.16.0"
}

variable "chart_version_kong" {
  type    = string
  default = "0.4.4"
}

variable "chart_version_external_dns" {
  type    = string
  default = "1.15.0"
}

variable "chart_version_falcon" {
  type    = string
  default = "1.25.0"
}

# ── ARC ───────────────────────────────────────────────────────────────────────

variable "tf_state_bucket" {
  type        = string
  description = "S3 bucket name holding Terraform state — ARC runner IAM policy grants access."
  default     = ""
}

# ── external-dns ──────────────────────────────────────────────────────────────

variable "external_dns_domain_filter" {
  type        = string
  description = "Root domain external-dns is allowed to manage (e.g. platform.example.com). Leave empty to manage all zones."
  default     = ""
}

variable "external_dns_policy" {
  type        = string
  description = "external-dns record policy: 'sync' (create+delete) for dev/staging; 'upsert-only' (create only) for prod."
  default     = "upsert-only"
  validation {
    condition     = contains(["sync", "upsert-only"], var.external_dns_policy)
    error_message = "external_dns_policy must be 'sync' or 'upsert-only'."
  }
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "team" {
  type    = string
  default = "infra-core"
}

variable "cost_center" {
  type    = string
  default = "infra-2026-q1"
}

variable "tags" {
  type    = map(string)
  default = {}
}
