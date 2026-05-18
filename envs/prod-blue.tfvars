environment  = "prod"
color        = "blue"
aws_region   = "us-east-1"
# state_bucket and eks_state_key are injected by provision-eks.yml via -var flags

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

install_karpenter        = true
install_cert_manager     = true
install_external_secrets = true
install_metrics_server   = true
install_gatekeeper       = true
install_keda             = true
install_kong             = true
install_external_dns     = true
install_falcon           = true   # prod: Falcon always on
install_arc              = true   # prod: self-hosted runners for pipeline jobs

# Prod: upsert-only — external-dns never deletes records automatically
external_dns_policy        = "upsert-only"
external_dns_domain_filter = ""   # set once Route53 hosted zone is known

tf_state_bucket = ""  # injected by pipeline

team        = "infra-core"
cost_center = "infra-2026-q1"
tags = {
  Owner       = "ajay"
  Environment = "prod"
}
