locals {
  # Derive EKS state key if not overridden
  eks_state_key = var.eks_state_key != "" ? var.eks_state_key : "${var.environment}/eks-${var.color}/terraform.tfstate"

  # Shorthand for commonly used remote state outputs
  cluster_name     = data.terraform_remote_state.eks.outputs.cluster_name
  cluster_endpoint = data.terraform_remote_state.eks.outputs.cluster_endpoint
  node_sg_id       = data.terraform_remote_state.eks.outputs.node_security_group_id

  full_tags = merge({
    Project     = "ai-search"
    ManagedBy   = "Terraform"
    Repository  = "infra-platform"
    Environment = var.environment
    Color       = var.color
    Team        = var.team
    CostCenter  = var.cost_center
  }, var.tags)
}
