# ── Actions Runner Controller (ARC) ──────────────────────────────────────────
# Deploys ephemeral self-hosted GitHub Actions runners on EKS.
#
# Architecture:
#   - ARC controller (arc-systems ns) watches GitHub for queued jobs
#   - Runner Scale Sets (arc-runners ns) — one per cluster, defined in aj-platform-gitops
#   - Each job gets a fresh pod; pod is destroyed after the job completes
#   - Pod Identity gives runners IAM access — no static AWS keys in GitHub secrets
#
# Auth: GitHub App (recommended over PAT)
#   1. Create a GitHub App in the ajay-infra org
#   2. Store App ID + private key in Secrets Manager
#   3. ESO syncs it to K8s Secret "arc-github-app-secret" in arc-runners namespace
#   4. ARC uses that secret to authenticate with GitHub
#
# Runner label (runs-on): [self-hosted, <environment>]
#   dev:     runs-on: [self-hosted, dev]
#   staging: runs-on: [self-hosted, staging]
#   prod:    runs-on: [self-hosted, prod]

# ─────────────────────────────────────────────────────────────────────────────
# IAM — Runner Pod Identity
# Runners need access to: Terraform state (S3 + DynamoDB), ECR, EKS describe
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_policy" "arc_runner" {
  count       = var.install_arc ? 1 : 0
  name        = "${local.cluster_name}-arc-runner"
  description = "ARC runner pods — Terraform state, ECR pull, EKS describe"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket}",
          "arn:aws:s3:::${var.tf_state_bucket}/*",
        ]
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = "*"
      },
      {
        Sid      = "EKSDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${var.aws_region}:${local.account_id}:cluster/*"
      },
    ]
  })
}

resource "aws_iam_role" "arc_runner" {
  count = var.install_arc ? 1 : 0
  name  = "${local.cluster_name}-arc-runner"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "arc_runner" {
  count      = var.install_arc ? 1 : 0
  role       = aws_iam_role.arc_runner[0].name
  policy_arn = aws_iam_policy.arc_runner[0].arn
}

resource "aws_eks_pod_identity_association" "arc_runner" {
  count           = var.install_arc ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = "arc-runners"
  service_account = "arc-runner-${var.environment}"
  role_arn        = aws_iam_role.arc_runner[0].arn
}

# ─────────────────────────────────────────────────────────────────────────────
# ARC Controller — the operator that watches GitHub for pending jobs
# Runner Scale Sets are managed via GitOps in aj-platform-gitops
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "arc_controller" {
  count = var.install_arc ? 1 : 0

  name       = "arc"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"
  version    = var.chart_version_arc_controller
  namespace  = "arc-systems"

  create_namespace = true

  set {
    name  = "replicaCount"
    value = "1"
  }

  # Metrics endpoint for Grafana/Prometheus scraping
  set {
    name  = "metrics.controllerManagerAddr"
    value = ":8080"
  }

  depends_on = [helm_release.cilium]
  wait       = true
  timeout    = 300
}
