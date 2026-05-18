output "cluster_name" {
  description = "EKS cluster name (from remote state)"
  value       = local.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint (from remote state)"
  value       = local.cluster_endpoint
}

output "aws_lbc_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.aws_lbc.arn
}

output "karpenter_role_arn" {
  description = "IAM role ARN for Karpenter"
  value       = var.install_karpenter ? aws_iam_role.karpenter[0].arn : null
}

output "external_secrets_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  value       = var.install_external_secrets ? aws_iam_role.external_secrets[0].arn : null
}

output "keda_role_arn" {
  description = "IAM role ARN for KEDA operator (SQS + CloudWatch scaler)"
  value       = var.install_keda ? aws_iam_role.keda[0].arn : null
}

output "external_dns_role_arn" {
  description = "IAM role ARN for external-dns (Route53 record management)"
  value       = var.install_external_dns ? aws_iam_role.external_dns[0].arn : null
}

output "installed_helm_releases" {
  description = "Map of installed Helm release names and chart versions"
  value = merge(
    { cilium                        = var.chart_version_cilium },
    { aws-load-balancer-controller  = var.chart_version_aws_lbc },
    var.install_karpenter     ? { karpenter        = var.chart_version_karpenter }     : {},
    var.install_cert_manager  ? { cert-manager      = var.chart_version_cert_manager }  : {},
    var.install_external_secrets ? { external-secrets = var.chart_version_external_secrets } : {},
    var.install_metrics_server   ? { metrics-server   = var.chart_version_metrics_server }   : {},
    var.install_gatekeeper    ? { gatekeeper        = var.chart_version_gatekeeper }    : {},
    var.install_keda          ? { keda              = var.chart_version_keda }          : {},
    var.install_kong          ? { kong              = var.chart_version_kong }          : {},
    var.install_external_dns  ? { external-dns      = var.chart_version_external_dns }  : {},
    var.install_falcon        ? { falcon-sensor      = var.chart_version_falcon }        : {},
    var.install_arc           ? { arc               = var.chart_version_arc_controller } : {},
  )
}
