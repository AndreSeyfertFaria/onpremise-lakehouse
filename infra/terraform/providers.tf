terraform {
  # 1. Define required providers and their versions
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Ensures a stable and recent version
    }
  }
}

variable "localstack_host" {
  type        = string
  default     = "localhost"
  description = "Hostname for LocalStack (e.g., localhost or localstack)"
}

# 2. Configures the AWS provider to point to LocalStack
provider "aws" {
  region     = "us-east-1"

  # These flags prevent Terraform from trying to validate 
  # real credentials on the internet, speeding up the local process
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  # The secret of the local stack: redirect API calls
  endpoints {
    s3   = "http://${var.localstack_host}:4566"
    glue = "http://${var.localstack_host}:4566"
    iam  = "http://${var.localstack_host}:4566"
    sts  = "http://${var.localstack_host}:4566"
  }
}