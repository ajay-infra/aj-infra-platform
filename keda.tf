# ── KEDA — event-driven pod autoscaler ───────────────────────────────────────
# Replaces plain HPA. ScaledObject CRDs live in k8s-manifests (GitOps).
# Do NOT install both KEDA and HPA on the same Deployment.
#
# Scalers in use across the platform:
#   SQS depth     → background jobs (ingest, indexing pipelines)
#   Prometheus    → backend services (custom metrics from Alloy)
#   HTTP req rate → frontend (via KEDA HTTP Add-on or Prometheus scrape)

# ── IAM — KEDA operator SQS + CloudWatch access ───────────────────────────────

resource "aws_iam_policy" "keda" {
  count       = var.install_keda ? 1 : 0
  name        = "${local.cluster_name}-keda"
  description = "KEDA operator — SQS queue metrics and CloudWatch scaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSScaler"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ListQueues",
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:${local.account_id}:${var.environment}-*"
      },
      {
        Sid    = "CloudWatchScaler"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics",
        ]
        Resource = "*"
      },
    ]
  })

  tags = local.full_tags
}

resource "aws_iam_role" "keda" {
  count = var.install_keda ? 1 : 0
  name  = "${local.cluster_name}-keda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = local.full_tags
}

resource "aws_iam_role_policy_attachment" "keda" {
  count      = var.install_keda ? 1 : 0
  policy_arn = aws_iam_policy.keda[0].arn
  role       = aws_iam_role.keda[0].name
}

resource "aws_eks_pod_identity_association" "keda" {
  count           = var.install_keda ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = "keda"
  service_account = "keda-operator"
  role_arn        = aws_iam_role.keda[0].arn
  tags            = local.full_tags
}

# ── Helm ──────────────────────────────────────────────────────────────────────

resource "helm_release" "keda" {
  count = var.install_keda ? 1 : 0

  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.chart_version_keda
  namespace  = "keda"

  create_namespace = true

  set {
    name  = "podIdentity.aws.irsa.enabled"
    value = "false"
  }

  # KEDA operator Pod Identity — SQS + CloudWatch access
  set {
    name  = "operator.replicaCount"
    value = var.environment == "prod" ? "2" : "1"
  }

  set {
    name  = "resources.operator.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.operator.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "resources.operator.limits.memory"
    value = "512Mi"
  }

  depends_on = [
    helm_release.cilium,
    helm_release.metrics_server,
    aws_eks_pod_identity_association.keda,
  ]
  wait    = true
  timeout = 300
}
