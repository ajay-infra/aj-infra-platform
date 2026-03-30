terraform {
  backend "s3" {
    # Configured via -backend-config or backend.hcl at init time
    # key    = "${environment}/aj-infra-platform/terraform.tfstate"
    # bucket = "<your-tf-state-bucket>"
    # region = "us-east-1"
    # dynamodb_table = "<your-lock-table>"
    # encrypt = true
  }
}
