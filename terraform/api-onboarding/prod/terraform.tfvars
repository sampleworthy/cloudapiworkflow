# PROD API onboarding.
#
# Promotion is explicit: an API reaches prod only when its folder name is
# added to enabled_apis in a reviewed PR. Everything else about the API
# (contract, policy, roles) is identical to dev because it comes from the same
# apis/<name>/ folder at the same commit.
environment = "prod"

enabled_apis = [
  "skills-api",
]

# Backend overrides for APIs that declare backend.urlVariable (none yet).
backend_urls = {}

tags = {
  project    = "cloudapiworkflow"
  costCenter = "api-platform"
}
