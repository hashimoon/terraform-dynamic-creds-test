terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  # No credentials - relies on dynamic credentials from HCP Terraform
}

# Read test: Verify authentication works
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Write test: Create a resource group (free, no charges)
resource "random_id" "rg_suffix" {
  byte_length = 4
}

resource "azurerm_resource_group" "test_write_permission" {
  name     = "terraform-dynamic-creds-test-${random_id.rg_suffix.hex}"
  location = var.azure_location

  tags = {
    purpose = "terraform-dynamic-creds-test"
  }
}
