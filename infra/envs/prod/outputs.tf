output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "container_app_fqdn" {
  value = azurerm_container_app.app.ingress[0].fqdn
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}