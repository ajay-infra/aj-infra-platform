locals {
  # Derive EKS state key if not overridden.
  # Pipeline always passes eks_state_key explicitly via -var; this default
  # is a fallback for local apply using the new workload/<mode>/<env> path.
  eks_state_key = var.eks_state_key != "" ? var.eks_state_key : "workload/blue-green/${var.environment}/eks-${var.color}/terraform.tfstate"

  # Shorthand for commonly used remote state outputs
  cluster_name     = data.terraform_remote_state.eks.outputs.cluster_name
  cluster_endpoint = data.terraform_remote_state.eks.outputs.cluster_endpoint
  node_sg_id       = data.terraform_remote_state.eks.outputs.node_security_group_id

  # Applied to every AWS resource through provider default_tags. Per-resource
  # `tags` blocks merge OVER this and are where Application comes from — see
  # platform_components below.
  #
  # Environment carries var.stage, NOT var.environment. var.environment is the
  # cluster/env slug (dev, staging, prod); it is load-bearing for resource names
  # and the remote state key, so it cannot be renamed into the stage vocabulary.
  # Tagging it as Environment produced values in no vocabulary — `dev` and
  # `staging` stopped being stages in the 2026-08-28 migration. prod-blue.tfvars
  # already overrode this by hand, which is the tell that it was wrong.
  full_tags = merge({
    Project     = "aj-infra-platform"
    ManagedBy   = "Terraform"
    Repository  = "aj-infra-platform"
    Environment = var.stage
    Color       = var.color
    Team        = var.team
    CostCenter  = var.cost_center
    # Platform overhead, never a tenant's cost. `internal` rather than absent,
    # so a missing Customer keeps meaning forgotten.
    Class    = "platform"
    Customer = "internal"
  }, var.tags)

  # ── The platform component map ──────────────────────────────────────────────
  # One entry per Terraform-installed component that owns a namespace. Single
  # source for three things that used to disagree:
  #
  #   1. the namespace's labels                    (namespaces.tf)
  #   2. the Application tag on its AWS resources
  #   3. which CiliumNetworkPolicy selects it, via platform.aj/segment
  #
  # `segment` is STATED, never defaulted. apisix is the edge and everything else
  # is platform — no default can know that, and the label is load-bearing:
  # Cilium leaves an endpoint unrestricted until a policy selects it, so a
  # namespace without this label has full connectivity. Every namespace here was
  # previously created by `create_namespace = true` with no labels at all, which
  # left the whole segmentation design inert for the platform's own components —
  # apisix, the internet-facing edge, included.
  #
  # `enabled` mirrors the component's install_* flag, so a namespace is never
  # created for a component that is not installed.
  platform_components = {
    "ack-system"       = { application = "ack", segment = "platform", extra_labels = {}, enabled = var.install_ack_certificates }
    "apisix"           = { application = "apisix", segment = "edge", extra_labels = {}, enabled = var.install_apisix }
    "arc-systems"      = { application = "arc-controller", segment = "platform", extra_labels = {}, enabled = var.install_arc }
    "cert-manager"     = { application = "cert-manager", segment = "platform", extra_labels = {}, enabled = var.install_cert_manager }
    "external-dns"     = { application = "external-dns", segment = "platform", extra_labels = {}, enabled = var.install_external_dns }
    "external-secrets" = { application = "external-secrets", segment = "platform", extra_labels = {}, enabled = var.install_external_secrets }
    # falcon-system carried Pod Security and Gatekeeper-exemption labels in
    # aj-cluster-baseline before ownership moved here. They come with it: an EDR sensor
    # needs host PID, host network and elevated capabilities to see what it
    # exists to see, so `restricted` would defeat its purpose and
    # no-privileged-containers would reject its DaemonSet. Moving the namespace
    # without these would have broken the sensor silently.
    "falcon-system" = {
      application = "falcon"
      segment     = "platform"
      enabled     = var.install_falcon
      extra_labels = {
        "admission.gatekeeper.sh/ignore"     = "true"
        "pod-security.kubernetes.io/enforce" = "privileged"
        "pod-security.kubernetes.io/audit"   = "restricted"
        "pod-security.kubernetes.io/warn"    = "restricted"
      }
    }
    "karpenter" = { application = "karpenter", segment = "platform", extra_labels = {}, enabled = var.install_karpenter }
    "keda"      = { application = "keda", segment = "platform", extra_labels = {}, enabled = var.install_keda }
    "opa"       = { application = "opa", segment = "platform", extra_labels = {}, enabled = var.install_opa }

    # CI runners execute arbitrary repository code. `platform` is the
    # least-wrong of the four segments rather than a good fit — none of
    # edge/platform/app/data was designed for a workload whose legitimate
    # traffic is egress to GitHub. Labelled so the namespace is attributable and
    # admissible; the segmentation question is tracked, not answered here.
    "arc-runners" = { application = "arc-runners", segment = "platform", extra_labels = {}, enabled = var.install_arc }

    # Excluded from every Gatekeeper constraint, so it would be admitted
    # unlabelled. Labelled anyway — the exclusion exists to stop Gatekeeper
    # blocking its own installation, not to declare its cost unattributable.
    "gatekeeper-system" = { application = "gatekeeper", segment = "platform", extra_labels = {}, enabled = var.install_gatekeeper }
  }

  # Only the components actually being installed.
  active_namespaces = {
    for ns, c in local.platform_components : ns => c if c.enabled
  }
}
