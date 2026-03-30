environment  = "staging"
color        = "blue"
aws_region   = "us-east-1"
state_bucket = "ai-search-tf-state"

chart_version_cilium           = "1.17.0"
chart_version_aws_lbc          = "1.10.0"
chart_version_karpenter        = "1.2.0"
chart_version_cert_manager     = "v1.16.2"
chart_version_external_secrets = "0.11.0"
chart_version_metrics_server   = "3.12.2"

install_karpenter        = true
install_cert_manager     = true
install_external_secrets = true
install_metrics_server   = true

team        = "infra-core"
cost_center = "infra-2026-q1"
tags = {
  Owner = "ajay"
}
