terraform {
  required_version = "= 1.7.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.100.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.12.1"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.full_tags
  }
}

# Helm provider authenticates to EKS via aws eks get-token (AWS CLI exec plugin).
# Requires: AWS CLI installed + valid credentials + cluster already provisioned.
# On first apply of a new environment, run:
#   terraform apply -target=data.terraform_remote_state.eks
#   (verify state is readable) then: terraform apply
provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_ca_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name,
        "--region", var.aws_region
      ]
    }
  }
}
