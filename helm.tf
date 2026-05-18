# ── L5 Helm Releases ─────────────────────────────────────────────────────────
# Install order matters — depends_on chains enforce this:
#   1. Cilium          — CNI must be first; nodes stay NotReady until this runs
#   2. cert-manager    — needed by AWS LBC for webhook TLS
#   3. AWS LBC         — needs cert-manager CRDs
#   4. Karpenter       — needs cluster + node role ARNs
#   5. External Secrets — needed by Falcon to read CID from Secrets Manager
#   6. metrics-server  — needed by KEDA for HPA compatibility
#   7. OPA Gatekeeper  — admission control (gatekeeper.tf)
#   8. KEDA            — event-driven autoscaler (keda.tf)
#   9. Kong KIC        — API gateway (kong.tf)
#  10. external-dns    — Route53 automation (external-dns.tf)
#  11. Falcon sensor   — runtime security DaemonSet (falcon.tf)
#  12. ARC controller  — self-hosted CI runners (arc.tf, optional)

# ─────────────────────────────────────────────────────────────────────────────
# 1. Cilium — overlay CNI (replaces vpc-cni + kube-proxy)
# ─────────────────────────────────────────────────────────────────────────────
# Values are sourced directly from the EKS module output (cilium_helm_values).
# Only installed when the EKS cluster was provisioned with cni = "cilium".

resource "helm_release" "cilium" {
  count = data.terraform_remote_state.eks.outputs.cni == "cilium" ? 1 : 0

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.chart_version_cilium
  namespace  = "kube-system"

  # Pass all values from the EKS module output directly
  dynamic "set" {
    for_each = data.terraform_remote_state.eks.outputs.cilium_helm_values
    content {
      name  = set.key
      value = set.value
    }
  }

  # Cilium must be ready before any other add-on can schedule pods
  wait    = true
  timeout = 600
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. cert-manager — TLS certificate management
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "cert_manager" {
  count = var.install_cert_manager ? 1 : 0

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version_cert_manager
  namespace  = "cert-manager"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }

  depends_on = [helm_release.cilium]
  wait       = true
  timeout    = 300
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. AWS Load Balancer Controller
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version_aws_lbc
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = local.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.aws_lbc.arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = data.terraform_remote_state.eks.outputs.active_private_subnets[0]
  }

  depends_on = [helm_release.cert_manager, aws_eks_pod_identity_association.aws_lbc]
  wait       = true
  timeout    = 300
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Karpenter — node autoscaler
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "karpenter" {
  count = var.install_karpenter ? 1 : 0

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.chart_version_karpenter
  namespace  = "karpenter"

  create_namespace = true

  set {
    name  = "settings.clusterName"
    value = local.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = local.cluster_endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter[0].arn
  }

  depends_on = [helm_release.cilium, aws_eks_pod_identity_association.karpenter]
  wait       = true
  timeout    = 300
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. External Secrets Operator
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "external_secrets" {
  count = var.install_external_secrets ? 1 : 0

  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version_external_secrets
  namespace  = "external-secrets"

  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets[0].arn
  }

  depends_on = [helm_release.cilium, aws_eks_pod_identity_association.external_secrets]
  wait       = true
  timeout    = 300
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. metrics-server — required for HPA and kubectl top
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.chart_version_metrics_server
  namespace  = "kube-system"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [helm_release.cilium]
  wait       = true
  timeout    = 180
}
