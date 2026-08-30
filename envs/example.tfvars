# example.tfvars — NOT read by any pipeline.
#
# Real per-cluster configuration lives in aj-infra-release:
#
#   envs/workload/<mode>/<cluster>/platform.tfvars   stage, chart versions, install_*
#   envs/workload/<mode>/<cluster>/common.tfvars     environment, team, cost_center, tags
#
# bootstrap-workload.yml passes both. This file exists so the module can be
# applied by hand against a scratch cluster, and as the reference for what the
# variables are.
#
# It used to be three files here — dev, staging and prod-blue — and the pipeline
# passed NONE of them. Everything below reached Terraform through nothing at all,
# so the module ran on variable defaults; nine of the twelve install_* flags
# default to true. A cluster installed components its own configuration said to
# skip, and nothing reported it.
#
# Two copies of a chart version list is how they drift, so there is now one.

environment = "scratch"
stage       = "nonprod"
color       = "blue"
aws_region  = "us-east-1"

# Injected by the pipeline via -var; set them here for a manual apply.
state_bucket  = ""
eks_state_key = ""

chart_version_cilium           = "1.17.0"
chart_version_aws_lbc          = "1.10.0"
chart_version_karpenter        = "1.2.0"
chart_version_cert_manager     = "v1.16.2"
chart_version_external_secrets = "0.11.0"
chart_version_metrics_server   = "3.12.2"
chart_version_gatekeeper       = "v3.17.1"
chart_version_keda             = "2.16.0"
chart_version_apisix           = "2.17.0"
chart_version_apisix_ingress   = "1.3.0"
chart_version_opa              = "11.0.12"
chart_version_external_dns     = "1.15.0"
chart_version_falcon           = "1.25.0"
chart_version_arc_controller   = "0.9.3"

install_karpenter        = true
install_cert_manager     = true
install_external_secrets = true
install_metrics_server   = true
install_gatekeeper       = true
install_keda             = true
install_apisix           = true
install_opa              = true
install_external_dns     = true
install_falcon           = false # needs a real CrowdStrike CID
install_arc              = false # needs a real GitHub App

external_dns_policy        = "sync"
external_dns_domain_filter = ""

team        = "infra-core"
cost_center = "infra-2026-q1"
tags        = { Owner = "ajay" }
