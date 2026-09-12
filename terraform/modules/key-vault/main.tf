# Key Vault for secrets that cannot be eliminated (for example the client
# secret of a non-Azure caller). RBAC authorisation only; no access policies.
# Everything Azure-to-Azure uses managed identity and never touches this vault.

resource "azurerm_key_vault" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled    = true
  purge_protection_enabled      = var.purge_protection_enabled
  soft_delete_retention_days    = 7
  public_network_access_enabled = var.public_network_access_enabled

  network_acls {
    default_action = var.public_network_access_enabled ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

# Identities that are allowed to write secrets (the platform deployer writes
# the agent client secret at apply time). Readers are granted per consumer.
resource "azurerm_role_assignment" "secrets_officers" {
  for_each = toset(var.secrets_officer_principal_ids)

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "secrets_users" {
  for_each = toset(var.secrets_user_principal_ids)

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

# Optional private endpoint (prod). Dev keeps the vault reachable by the
# deployer over the public endpoint with RBAC as the control.
resource "azurerm_private_endpoint" "this" {
  count = var.private_endpoint_subnet_id == null ? 0 : 1

  name                = "pe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id == null ? [] : [1]
    content {
      name                 = "default"
      private_dns_zone_ids = [var.private_dns_zone_id]
    }
  }
}
