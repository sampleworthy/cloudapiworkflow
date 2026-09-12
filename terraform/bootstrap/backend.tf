# Bootstrap state.
#
# The first run of this layer has nowhere to store state, so it starts local.
# After the first apply, migrate it into the storage account it just created:
#
#   terraform init -migrate-state \
#     -backend-config="resource_group_name=rg-cloudapiworkflow-state" \
#     -backend-config="storage_account_name=<output tfstate_storage_account_name>" \
#     -backend-config="container_name=bootstrap" \
#     -backend-config="key=bootstrap.tfstate" \
#     -backend-config="use_azuread_auth=true"
#
# Bootstrap is run by a human platform administrator, never by CI. It is the
# only layer whose identity is a person; everything downstream uses OIDC.
terraform {
  backend "azurerm" {}
}
