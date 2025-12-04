terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0.0"
    }
  }
}

provider "aws" {
  # No credentials configured - relies on dynamic credentials from HCP Terraform
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
