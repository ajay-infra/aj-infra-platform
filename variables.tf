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
  description = "Active cluster color: blue | green"
  default     = "blue"
  validation {
    condition     = contains(["blue", "green"], var.color)
    error_message = "color must be 'blue' or 'green'."
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

# ── ARC ───────────────────────────────────────────────────────────────────────

variable "chart_version_arc_controller" {
  type        = string
  description = "ARC gha-runner-scale-set-controller Helm chart version."
  default     = "0.9.3"
}

variable "tf_state_bucket" {
  type        = string
  description = "S3 bucket name holding Terraform state — ARC runner IAM policy grants access."
  default     = ""
}

variable "tf_lock_table" {
  type        = string
  description = "DynamoDB table name for Terraform state locking — ARC runner IAM policy grants access."
  default     = "tf-locks-central"
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
