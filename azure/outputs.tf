output "tenant_id" {
  description = "The Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "The Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "client_id" {
  description = "The Azure client/app ID"
  value       = data.azurerm_client_config.current.client_id
}

output "subscription_name" {
  description = "The Azure subscription display name"
  value       = data.azurerm_subscription.current.display_name
}

output "test_resource_group_id" {
  description = "ID of the test resource group (verifies write permissions)"
  value       = azurerm_resource_group.test_write_permission.id
}
