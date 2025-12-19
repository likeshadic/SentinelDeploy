locals {
  name_prefix = "${var.project}-${var.environment}"
  tags = {
    project     = var.project
    environment = var.environment
    repo        = var.github_repo
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

# --- Monitoring ---
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_application_insights" "ai" {
  name                = "appi-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
  tags                = local.tags
}

# --- Container Registry ---
resource "azurerm_container_registry" "acr" {
  name                = replace("acr${var.project}${var.environment}", "-", "")
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

# --- Key Vault (RBAC enabled) ---
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                       = "kv-${local.name_prefix}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = local.tags
}

# Give the deploying identity (whoever runs terraform) permissions to manage secrets in this KV.
# In GitHub Actions, this will be the OIDC-authenticated principal.
resource "azurerm_role_assignment" "kv_secrets_officer_for_deployer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "demo" {
  name         = "demo-secret"
  value        = var.demo_secret_value
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.kv_secrets_officer_for_deployer]
}

# --- User-assigned Managed Identity for the running container app ---
resource "azurerm_user_assigned_identity" "app_uai" {
  name                = "uai-${local.name_prefix}-app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

# Allow the app identity to pull images from ACR
resource "azurerm_role_assignment" "acr_pull_for_app" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app_uai.principal_id
}

# Allow the app identity to read secrets from Key Vault
resource "azurerm_role_assignment" "kv_secrets_user_for_app" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app_uai.principal_id
}

# --- Container Apps Environment ---
resource "azurerm_container_app_environment" "cae" {
  name                       = "cae-${local.name_prefix}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  tags                       = local.tags
}

# --- Container App ---
# Note: container_image is typically set by your CD pipeline. For first apply, you can pass a placeholder image.
locals {
  effective_image = length(var.container_image) > 0 ? var.container_image : "${azurerm_container_registry.acr.login_server}/placeholder:latest"
}

resource "azurerm_container_app" "app" {
  name                         = "ca-${local.name_prefix}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app_uai.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app_uai.id
  }

  secret {
    name                = "demo-secret"
    key_vault_secret_id = azurerm_key_vault_secret.demo.id
    identity            = azurerm_user_assigned_identity.app_uai.id
  }

  template {
    container {
      name   = "app"
      image  = local.effective_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name        = "DEMO_SECRET"
        secret_name = "demo-secret"
      }

      env {
        name  = "APPINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.ai.connection_string
      }
    }

    min_replicas = 1
    max_replicas = 3
  }

  ingress {
    external_enabled = true
    target_port      = var.app_port
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = local.tags

  depends_on = [
    azurerm_role_assignment.acr_pull_for_app,
    azurerm_role_assignment.kv_secrets_user_for_app
  ]
}