# ── cert-manager — Route53 access for the DNS-01 solver ──────────────────────
# cert-manager mints the ORIGIN certificate: the Let's Encrypt wildcard that
# Kong presents to CloudFront. See aj-infra-context/arch/tls-and-edge.md §3.
#
# Why DNS-01 and not HTTP-01, which would need no AWS access at all:
# Let's Encrypt will not issue a WILDCARD certificate over HTTP-01, and
# k8s-manifests/cert-manager/certificate-kong-wildcard.yaml requests
# *.platform.<domain>. The wildcard is what lets a blue/green cutover happen
# without touching TLS — one certificate already covers blue., green. and
# active. So DNS-01 is a requirement, not a preference, and this IAM is the
# price of it.
#
# This closes the gap in tls-and-edge.md §7: clusterissuer-prod.yaml states
# "cert-manager uses EKS Pod Identity ... must have Route53 write access", and
# no such role existed. Without it the chain fails all the way down — no
# _acme-challenge records, no issued certificate, no kong-wildcard-tls Secret,
# no TLS at the origin, and CloudFront's https-only origin connection fails.

resource "aws_iam_policy" "cert_manager" {
  count       = var.install_cert_manager ? 1 : 0
  name        = "${local.cluster_name}-cert-manager"
  description = "cert-manager DNS-01 solver — ACME challenge TXT records only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Zone discovery. cert-manager resolves the correct hosted zone for a
        # domain at solve time, so it must be able to list them.
        Sid    = "DiscoverZones"
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
        # cert-manager is the ONE Route53 writer here that legitimately needs
        # DELETE: an ACME challenge record is created, validated, and then
        # cleaned up. The ACK Route53 controller deliberately has no DELETE at
        # all (see ack.tf) because its records are permanent.
        #
        # So the bound cannot come from the action list, and comes from the
        # record NAME and TYPE instead:
        #
        #   TXT only              CNAMEs are untouchable — that covers
        #                         Terraform's blue./green./active./apex records,
        #                         every external-dns workload record, and every
        #                         ACM validation CNAME from ACK Route53
        #   _acme-challenge*      the only names it can address at all
        #
        # Even holding DELETE, it cannot remove anything that is not an ACME
        # challenge record it created.
        #
        # Note ForAllValues evaluates TRUE when the condition key is absent, so
        # it restricts only on actions that populate these keys. Route53 always
        # does for ChangeResourceRecordSets — do not copy this shape elsewhere
        # without checking that.
        Sid    = "WriteACMEChallengeRecordsOnly"
        Effect = "Allow"
        Action = ["route53:ChangeResourceRecordSets"]

        # Scoped to the estate's zone once one exists. Until then this is
        # hostedzone/*, which is wider than ideal but far less permissive than
        # it looks: the conditions below still restrict it to ACME challenge TXT
        # records and nothing else, in any zone. Narrow it by setting
        # route53_hosted_zone_id.
        Resource = var.route53_hosted_zone_id != "" ? "arn:aws:route53:::hostedzone/${var.route53_hosted_zone_id}" : "arn:aws:route53:::hostedzone/*"

        Condition = {
          "ForAllValues:StringLike" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = ["_acme-challenge*"]
          }
          "ForAllValues:StringEquals" = {
            "route53:ChangeResourceRecordSetsRecordTypes" = ["TXT"]
          }
        }
      },
    ]
  })

  tags = local.full_tags
}

resource "aws_iam_role" "cert_manager" {
  count = var.install_cert_manager ? 1 : 0
  name  = "${local.cluster_name}-cert-manager"

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

resource "aws_iam_role_policy_attachment" "cert_manager" {
  count      = var.install_cert_manager ? 1 : 0
  policy_arn = aws_iam_policy.cert_manager[0].arn
  role       = aws_iam_role.cert_manager[0].name
}

# The ClusterIssuer's route53 solver carries no credentials block — it relies on
# ambient credentials from this association. The service account name is the
# chart default.
resource "aws_eks_pod_identity_association" "cert_manager" {
  count           = var.install_cert_manager ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = "cert-manager"
  service_account = "cert-manager"
  role_arn        = aws_iam_role.cert_manager[0].arn
  tags            = local.full_tags
}
