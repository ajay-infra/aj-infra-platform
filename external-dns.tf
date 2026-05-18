# ── external-dns — automated Route53 DNS management ──────────────────────────
# Watches Ingress + Service objects and creates/updates Route53 records.
# Critical for blue/green: when ALB comes up with Ingress annotations,
# external-dns creates DNS automatically. When the old ALB is torn down,
# records are cleaned up (dev/staging: policy=sync; prod: policy=upsert-only).
#
# external-dns uses Pod Identity to call Route53 — no static keys.

# ── IAM ───────────────────────────────────────────────────────────────────────

resource "aws_iam_policy" "external_dns" {
  count       = var.install_external_dns ? 1 : 0
  name        = "${local.cluster_name}-external-dns"
  description = "external-dns — manage Route53 records for Ingress + Service objects"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Route53ListHostedZones"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53ChangeRecords"
        Effect = "Allow"
        Action = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
    ]
  })

  tags = local.full_tags
}

resource "aws_iam_role" "external_dns" {
  count = var.install_external_dns ? 1 : 0
  name  = "${local.cluster_name}-external-dns"

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

resource "aws_iam_role_policy_attachment" "external_dns" {
  count      = var.install_external_dns ? 1 : 0
  policy_arn = aws_iam_policy.external_dns[0].arn
  role       = aws_iam_role.external_dns[0].name
}

resource "aws_eks_pod_identity_association" "external_dns" {
  count           = var.install_external_dns ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns[0].arn
  tags            = local.full_tags
}

# ── Helm ──────────────────────────────────────────────────────────────────────

resource "helm_release" "external_dns" {
  count = var.install_external_dns ? 1 : 0

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.chart_version_external_dns
  namespace  = "external-dns"

  create_namespace = true

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "aws.region"
    value = var.aws_region
  }

  # sync: creates AND deletes records (dev/staging — safe to let it manage fully)
  # upsert-only: creates but never deletes (prod — prevent accidental record removal)
  set {
    name  = "policy"
    value = var.external_dns_policy
  }

  # Only manage records for explicitly annotated Ingress/Service objects
  set {
    name  = "domainFilters[0]"
    value = var.external_dns_domain_filter
  }

  set {
    name  = "txtOwnerId"
    value = local.cluster_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns[0].arn
  }

  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.limits.memory"
    value = "256Mi"
  }

  depends_on = [helm_release.cilium, aws_eks_pod_identity_association.external_dns]
  wait       = true
  timeout    = 180
}
