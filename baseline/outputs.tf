
output "resource_group_id" {
  description = "List of the Resource Group IDs"
  value       = azurerm_resource_group.rg.id
}

output "acr_admin_username" {
  description = "The Username associated with the Container Registry Admin account - if the admin account is enabled."
  value       = azurerm_container_registry.acr.admin_username
}

output "acr_admin_password" {
  description = "The Password associated with the Container Registry Admin account - if the admin account is enabled."
  value       = azurerm_container_registry.acr.admin_password
  sensitive   = true
}

output "acr_id" {
  description = "The ID of the Container Registry."
  value       = azurerm_container_registry.acr.id
}
