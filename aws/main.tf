terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  # No credentials configured - relies on dynamic credentials from HCP Terraform
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "random_id" "policy_suffix" {
  byte_length = 4
}

resource "aws_iam_policy" "test_write_permission" {
  name        = "terraform-dynamic-creds-test-policy-${random_id.policy_suffix.hex}"
  description = "Test policy to verify write permissions - created by terraform-dynamic-creds-test"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}
