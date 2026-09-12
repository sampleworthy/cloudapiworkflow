# Entra ID resource application for one API.
#
# Produces the thing a JWT is issued *for*: an app registration exposing the
# API's application permissions (app roles). Callers acquire a client
# credentials token for the identifier URI; APIM validates audience + roles;
# the backend's Easy Auth validates the same registration.
#
# Identifier URI format is api://<tenant-id>/<name>. Entra tenants created
# after 2024 reject free-form api://<string> URIs (the "default URI formats"
# restriction), and the tenant-scoped form is accepted everywhere.

resource "random_uuid" "role" {
  for_each = var.app_roles
}

resource "azuread_application" "this" {
  display_name    = var.display_name
  description     = var.description
  identifier_uris = ["api://${var.tenant_id}/${var.name}"]
  owners          = var.owners

  sign_in_audience = "AzureADMyOrg"

  api {
    # v1 access tokens: aud = identifier URI, iss = https://sts.windows.net/<tenant>/
    requested_access_token_version = 1
  }

  dynamic "app_role" {
    for_each = var.app_roles
    content {
      id                   = random_uuid.role[app_role.key].result
      value                = app_role.key
      display_name         = app_role.key
      description          = app_role.value
      allowed_member_types = ["Application"]
      enabled              = true
    }
  }

  tags = var.tags
}

resource "azuread_service_principal" "this" {
  client_id                    = azuread_application.this.client_id
  app_role_assignment_required = false # APIM validates roles; the MI needs a role-less token for Easy Auth
  owners                       = var.owners
  tags                         = var.tags
}

# Grant application permissions to client identities (e.g. the shared agent
# client). Keyed "<client-key>|<role>" so each grant is individually tracked.
resource "azuread_app_role_assignment" "clients" {
  for_each = {
    for pair in flatten([
      for client_key, client in var.client_grants : [
        for role in client.roles : {
          key                 = "${client_key}|${role}"
          principal_object_id = client.principal_object_id
          role                = role
        }
      ]
    ]) : pair.key => pair
  }

  app_role_id         = random_uuid.role[each.value.role].result
  principal_object_id = each.value.principal_object_id
  resource_object_id  = azuread_service_principal.this.object_id
}
