terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  # No credentials - relies on dynamic credentials from HCP Terraform
  project = var.gcp_project_id
  region  = "us-central1"
}

# Read test: Verify authentication works
data "google_client_config" "current" {}

# Write test: Create a custom IAM role (free, no charges)
resource "random_id" "role_suffix" {
  byte_length = 4
}

resource "google_project_iam_custom_role" "test_write_permission" {
  role_id     = "terraformDynamicCredsTest${random_id.role_suffix.hex}"
  title       = "Terraform Dynamic Creds Test Role"
  description = "Test role to verify write permissions - created by terraform-dynamic-creds-test"
  permissions = ["iam.roles.list"]
}
