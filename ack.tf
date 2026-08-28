# ── ACK controllers — certificate management ─────────────────────────────────
# AWS Controllers for Kubernetes: ACM + Route53. Deployed as a UNIT, and the
# reason is not stylistic.
#
# The ACM controller does NOT write DNS validation records. It requests the
# certificate and then waits for validation it cannot perform itself; AWS's own
# documentation points at the separate Route53 controller for the validation
# CNAMEs. Deploying acm alone leaves every public certificate stuck in
# PENDING_VALIDATION indefinitely. So both, or neither.
#
# ── This makes ACK Route53 the FIFTH writer on the shared zone ───────────────
# The other four (see aj-platform-gitops/CLAUDE.md):
#   terraform      blue. / green. / active. / apex — permanent traffic records
#   cert-manager   _acme-challenge TXT — ephemeral, in-cluster TLS only
#   external-dns   workload-following records, upsert-only + per-cluster txtOwnerId
#   ACK route53    ACM validation CNAMEs                            ← this file
#
# Session 7 landed a bug where external-dns was granted deletion rights over a
# zone containing Terraform-owned records it had no business touching. The
# lesson was that a DNS writer's blast radius must be bounded by construction,
# not by configuration that can be edited. So this controller's IAM is scoped
# three ways at once — record TYPE, record NAME, and ACTION:
#
#   CNAME only          cert-manager's TXT records are out of reach
#   names beginning _   blue./green./active./apex/workload records are unmatched
#   CREATE + UPSERT     DELETE is not granted at all
#
# It therefore cannot remove a record even if the controller is compromised,
# misconfigured, or reconciling something it should not.
#
# ── exportTo is FORBIDDEN, and IAM cannot enforce that ───────────────────────
# `spec.exportTo` on a Certificate makes it an EXPORTABLE public certificate:
# $7 per FQDN and $79 per wildcard, charged AT ISSUANCE and again at EVERY
# renewal on a 198-day validity — roughly $158/year for one wildcard. Standard
# ACM certificates are free.
#
# There is no IAM condition key for the export option. ACM supports exactly
# ValidationMethod, DomainNames, KeyAlgorithm, CertificateTransparencyLogging
# (deprecated) and CertificateAuthority / CertificateKeyPairOrigin on
# RequestCertificate — none of which sees it. And the charge lands at issuance,
# not at export, so withholding acm:ExportCertificate stops the private key
# leaving but does NOT stop the bill.
#
# The only preventive control is admission control:
#   k8s-manifests/policies/constraints/deny-acm-exportable.yaml
#
# The single case exportTo serves — something in-cluster terminating TLS — is
# already covered, for free, by cert-manager.

# ── ACM controller: IAM ───────────────────────────────────────────────────────

resource "aws_iam_policy" "ack_acm" {
  count       = var.install_ack_certificates ? 1 : 0
  name        = "${local.cluster_name}-ack-acm"
  description = "ACK ACM controller — request and manage ACM certificates. No export."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # RequestCertificate creates a new resource, so it cannot be
        # resource-scoped. Constrained by condition instead: DNS validation
        # only, so a certificate can never fall back to EMAIL validation and
        # sit waiting on a human to click a link in an inbox nobody reads.
        Sid      = "RequestCertificateDNSValidatedOnly"
        Effect   = "Allow"
        Action   = ["acm:RequestCertificate"]
        Resource = "*"
        Condition = {
          StringEquals = { "acm:ValidationMethod" = "DNS" }
        }
      },
      {
        Sid    = "ManageCertificates"
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:ListTagsForCertificate",
          "acm:AddTagsToCertificate",
          "acm:RemoveTagsFromCertificate",
          "acm:DeleteCertificate",
        ]
        Resource = "*"
      },
      # acm:ExportCertificate is deliberately NOT granted. Nothing here needs
      # it, and withholding it keeps a private key from reaching a Secret.
      # Note this is defence in depth, NOT the cost control — see the header.
    ]
  })

  tags = local.full_tags
}

resource "aws_iam_role" "ack_acm" {
  count = var.install_ack_certificates ? 1 : 0
  name  = "${local.cluster_name}-ack-acm"

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

resource "aws_iam_role_policy_attachment" "ack_acm" {
  count      = var.install_ack_certificates ? 1 : 0
  policy_arn = aws_iam_policy.ack_acm[0].arn
  role       = aws_iam_role.ack_acm[0].name
}

resource "aws_eks_pod_identity_association" "ack_acm" {
  count           = var.install_ack_certificates ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = "ack-system"
  service_account = "ack-acm-controller"
  role_arn        = aws_iam_role.ack_acm[0].arn
  tags            = local.full_tags
}

# ── Route53 controller: IAM ───────────────────────────────────────────────────

resource "aws_iam_policy" "ack_route53" {
  count       = var.install_ack_certificates ? 1 : 0
  name        = "${local.cluster_name}-ack-route53"
  description = "ACK Route53 controller — ACM validation CNAMEs only. Cannot delete."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadZones"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:GetChange",
        ]
        Resource = "*"
      },
      {
        # The whole blast-radius argument lives in this one statement.
        #
        # NormalizedRecordNames matches ACM's validation records, which are
        # always `_<hash>.<domain>`. Values must be lowercase, carry no
        # trailing dot, and escape special characters in octal — so the leading
        # underscore is literal and `*` would be \052 if it were needed here.
        #
        # Terraform's blue./green./active./apex records and every
        # workload-following record from external-dns fail the name match.
        # cert-manager's _acme-challenge records match the name pattern but are
        # TXT, so they fail the type match. DELETE is absent from the action
        # list entirely.
        #
        # Caveat on ForAllValues, which is a well-known IAM footgun: it
        # evaluates to TRUE when the condition key is absent from the request,
        # so on an action that does not populate these keys it would grant
        # rather than restrict. Route53 always populates all three for
        # ChangeResourceRecordSets, so it is correct here — but do not copy
        # this shape onto a different action without checking that first.
        Sid      = "WriteACMValidationRecordsOnly"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/${var.route53_hosted_zone_id}"
        Condition = {
          "ForAllValues:StringLike" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = ["_*"]
          }
          "ForAllValues:StringEquals" = {
            "route53:ChangeResourceRecordSetsRecordTypes" = ["CNAME"]
            "route53:ChangeResourceRecordSetsActions"     = ["CREATE", "UPSERT"]
          }
        }
      },
    ]
  })

  tags = local.full_tags

  lifecycle {
    # variable validation cannot see another variable, so the "required when
    # enabled" rule lands here. Without a zone the policy would otherwise be
    # written against hostedzone/ with an empty id, which matches nothing and
    # would fail at reconcile time with a confusing permission error rather
    # than a clear one at plan time.
    precondition {
      condition     = var.route53_hosted_zone_id != ""
      error_message = "route53_hosted_zone_id is required when install_ack_certificates is true — the ACK Route53 controller's IAM policy is scoped to a specific zone."
    }
  }
}

resource "aws_iam_role" "ack_route53" {
  count = var.install_ack_certificates ? 1 : 0
  name  = "${local.cluster_name}-ack-route53"

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

resource "aws_iam_role_policy_attachment" "ack_route53" {
  count      = var.install_ack_certificates ? 1 : 0
  policy_arn = aws_iam_policy.ack_route53[0].arn
  role       = aws_iam_role.ack_route53[0].name
}

resource "aws_eks_pod_identity_association" "ack_route53" {
  count           = var.install_ack_certificates ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = "ack-system"
  service_account = "ack-route53-controller"
  role_arn        = aws_iam_role.ack_route53[0].arn
  tags            = local.full_tags
}

# ── Helm ──────────────────────────────────────────────────────────────────────
# Charts are OCI artifacts on ECR Public — the same pattern as Karpenter.
# serviceAccount.create is left at its default (true) so the chart owns the
# ServiceAccount; the Pod Identity association above binds the role to it by
# name, so no eks.amazonaws.com/role-arn annotation is needed.

resource "helm_release" "ack_acm" {
  count = var.install_ack_certificates ? 1 : 0

  name       = "ack-acm-controller"
  repository = "oci://public.ecr.aws/aws-controllers-k8s"
  chart      = "acm-chart"
  version    = var.chart_version_ack_acm
  namespace  = "ack-system"

  create_namespace = true

  set {
    name  = "aws.region"
    value = var.aws_region
  }

  set {
    name  = "serviceAccount.name"
    value = "ack-acm-controller"
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

  depends_on = [helm_release.cilium, aws_eks_pod_identity_association.ack_acm]
  wait       = true
  timeout    = 180
}

resource "helm_release" "ack_route53" {
  count = var.install_ack_certificates ? 1 : 0

  name       = "ack-route53-controller"
  repository = "oci://public.ecr.aws/aws-controllers-k8s"
  chart      = "route53-chart"
  version    = var.chart_version_ack_route53
  namespace  = "ack-system"

  create_namespace = true

  set {
    name  = "aws.region"
    value = var.aws_region
  }

  set {
    name  = "serviceAccount.name"
    value = "ack-route53-controller"
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

  # Ordered after the ACM controller only so that a fresh install brings the
  # validation writer up alongside the requester rather than long before it.
  depends_on = [helm_release.ack_acm, aws_eks_pod_identity_association.ack_route53]
  wait       = true
  timeout    = 180
}
