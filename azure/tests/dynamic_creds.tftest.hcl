run "verify_azure_identity" {
  command = plan

  assert {
    condition     = data.azurerm_client_config.current.tenant_id != ""
    error_message = "Azure client config should return a tenant ID"
  }

  assert {
    condition     = data.azurerm_client_config.current.subscription_id != ""
    error_message = "Azure client config should return a subscription ID"
  }

  assert {
    condition     = data.azurerm_client_config.current.client_id != ""
    error_message = "Azure client config should return a client ID"
  }
}

run "verify_azure_write_permission" {
  command = apply

  assert {
    condition     = azurerm_resource_group.test_write_permission.id != ""
    error_message = "Resource group should be created with a valid ID"
  }

  assert {
    condition     = can(regex("^/subscriptions/.+/resourceGroups/", azurerm_resource_group.test_write_permission.id))
    error_message = "Resource group ID should be a valid Azure resource ID"
  }
}
