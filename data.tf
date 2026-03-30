# ── EKS Remote State ──────────────────────────────────────────────────────────
# Reads outputs from aj-tf-module-eks: cluster endpoint, CA, name,
# node SG, cilium_helm_values, node role ARNs, etc.
# EKS must be applied before infra-platform can plan/apply.

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = local.eks_state_key
    region = var.aws_region
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
