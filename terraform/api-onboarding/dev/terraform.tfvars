# DEV API onboarding.
#
# enabled_apis = null  -> every apis/<name>/api.yaml is deployed to dev.
# Adding an API to dev therefore needs no change to this file.
# subscription_id comes from TF_VAR_subscription_id.
environment  = "dev"
enabled_apis = null

# Backend overrides for APIs that declare backend.urlVariable. Empty in dev:
# app_service backends are created here, mock backends need no URL.
backend_urls = {}

tags = {
  project    = "cloudapiworkflow"
  costCenter = "platform-demo"
}
