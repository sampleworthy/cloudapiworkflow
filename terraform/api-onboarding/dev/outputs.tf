output "apim_name" {
  description = "The shared instance the APIs were added to (read from platform state, not created here)."
  value       = local.apim_name
}

output "apim_gateway_url" {
  value = local.platform.apim_gateway_url
}

output "apis" {
  description = "One entry per onboarded API: how to call it and what token it expects."
  value = {
    for k, a in local.apis : k => {
      api_name     = module.api[k].api_name
      display_name = a.display_name
      url          = "${local.platform.apim_gateway_url}/${module.api[k].path}"
      product      = a.product
      audience     = module.identity[k].identifier_uri
      roles        = keys(a.auth.roles)
      backend_type = a.backend.type
      backend_url  = local.backend_urls[k]
      web_app_name = try(module.backend_app[k].name, null)
    }
  }
}

output "agent_client_id" {
  description = "Client id of the shared demo caller; smoke tests log in as this identity via GitHub OIDC."
  value       = local.platform.agent_client_id
}

output "tenant_id" {
  value = local.platform.tenant_id
}

output "key_vault_name" {
  value = local.platform.key_vault_name
}
