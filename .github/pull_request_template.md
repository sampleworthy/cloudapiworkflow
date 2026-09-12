<!-- Title format: "<area>: <change>"  e.g. "apis: onboard orders-api v1" -->

## What

<!-- One paragraph. Link the ticket. -->

## Type of change

- [ ] API onboarding (new `apis/<name>/` folder)
- [ ] API change (existing contract, policy or metadata)
- [ ] Backend application change (`applications/`)
- [ ] Platform infrastructure (`terraform/platform`, platform modules)
- [ ] CI/CD or governance (`.github/`, `CODEOWNERS`, `.spectral.yaml`, `schemas/`)

## API checklist (delete if not an API change)

- [ ] `openapi.yaml` added/updated and Spectral passes locally (`scripts/validate-openapi.sh`)
- [ ] `api.yaml` valid (`scripts/onboarding-check.sh`); folder name == `name`
- [ ] Gateway `path` reviewed for collisions and naming (`/<path>/<version>`)
- [ ] Authentication documented: audience, roles, which clients are allowed
- [ ] Backend configured: `backend.type` and, for external backends, `urlVariable` + prod `backend_urls`
- [ ] `policies/inbound.xml` reviewed: starts with `<base />`, JWT validation present, no secrets or tenant ids
- [ ] Rate limit (`rateLimit.calls` / `renewalPeriod`) set deliberately, not copied
- [ ] Breaking change? If yes: new `version` + new folder with `versionSet`; the existing version is untouched
- [ ] Product association correct (`internal-apis` / `partner-apis` / `agent-apis`)
- [ ] Backend tests pass (`pytest`) and the app exposes `GET /health`
- [ ] Prod promotion: added to `terraform/api-onboarding/prod/terraform.tfvars` `enabled_apis` (or explicitly deferred)

## Terraform plan review

- [ ] I read the plan posted by CI on this PR
- [ ] The plan contains **no** change to `azurerm_api_management` (the shared gateway)
- [ ] Resource counts match expectations (new API ≈ version set + api + policy + backend + product link + diagnostic + identity + web app)
- [ ] No unexpected destroys

## Security

- [ ] No secrets, connection strings, tenant/subscription ids or client secrets in the diff
- [ ] Least privilege preserved (no RBAC widened without a platform-team reviewer)

## Evidence

<!-- Plan excerpt, test output, screenshots. -->
