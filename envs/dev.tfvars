environment  = "dev"
color        = "blue"
aws_region   = "us-east-1"
# state_bucket and eks_state_key are injected by provision-eks.yml via -var flags

# Chart versions — keep in sync with versions.json
chart_version_cilium           = "1.17.0"
chart_version_aws_lbc          = "1.10.0"
chart_version_karpenter        = "1.2.0"
chart_version_cert_manager     = "v1.16.2"
chart_version_external_secrets = "0.11.0"
chart_version_metrics_server   = "3.12.2"
chart_version_gatekeeper       = "v3.17.1"
chart_version_keda             = "2.16.0"
chart_version_kong             = "0.4.4"
chart_version_external_dns     = "1.15.0"
chart_version_falcon           = "1.25.0"
chart_version_arc_controller   = "0.9.3"

# Dev: disable Karpenter (optional — saves ~$0.10/hr), enable everything else
install_karpenter        = false
install_cert_manager     = true
install_external_secrets = true
install_metrics_server   = true
install_gatekeeper       = true
install_keda             = true
install_kong             = true
install_external_dns     = true
install_falcon           = false  # enable once CID is in Secrets Manager
install_arc              = false  # enable once GitHub App is created in the org

# external-dns: sync mode in dev — create AND delete records freely
external_dns_policy       = "sync"
external_dns_domain_filter = ""   # set to base domain once Route53 hosted zone is created

# ARC
tf_state_bucket = ""  # injected by pipeline

team        = "infra-core"
cost_center = "infra-2026-q1"
tags = {
  Owner = "ajay"
}
