<!-- Title format: "<area>: <change>"  e.g. "apim: onboard orders-api v1" -->

## What

<!-- One paragraph. Link the ticket. -->

## Type of change

- [ ] API onboarding (new folder under `apim/artifacts/apis/`)
- [ ] API change (contract, policy, product link, diagnostics)
- [ ] API deprecation / retirement (label `api-retirement` required for deletion)
- [ ] Agent change (`agents/<name>/`: definition, instructions, tools)
- [ ] AI gateway change (`apim/artifacts/apis/foundry-models-*`, `policy fragments/ai-*`)
- [ ] Backend application (`applications/`)
- [ ] Platform infrastructure (`terraform/`)
- [ ] CI/CD or governance (`.github/`, `governance/`, `scripts/`, `CODEOWNERS`)

## API checklist (delete if not an API change)

- [ ] `specification.yaml` updated; `scripts/validate-openapi.sh` passes locally
- [ ] Version reviewed: `info.version` major == `apiVersion`; breaking change ⇒ new `<api>-v<n>` folder, old version untouched
- [ ] `scripts/detect-breaking-changes.sh` reviewed (or a new version folder was created)
- [ ] Security requirements documented: audience, required roles per operation
- [ ] Required OAuth roles exist in `terraform/environments/*/terraform.tfvars` (`api_app_roles`)
- [ ] `policy.xml` reviewed: `<base />`, `validate-jwt`, role check, no secrets / ids / hostnames
- [ ] Product association present (`products/<product>/apis/<api>/productApiInformation.json`)
- [ ] Rate limit set deliberately (`rate-limit-by-key`)
- [ ] Backend reviewed: `backends/<api>/` exists; URL override added to `configuration.dev.yaml` **and** `configuration.prod.yaml`
- [ ] `apim/extractor.config.yaml` lists the API (drift coverage)
- [ ] `apis/<name>/README.md` added or updated (owner, lifecycle)
- [ ] Automated tests pass (`pytest` for platform-hosted backends)
- [ ] Production impact documented (promotion planned? consumers notified?)

## Agent checklist (delete if not an agent change)

- [ ] `scripts/agent/validate_agent.py agents/<name>` passes; tools reference published contracts only
- [ ] Tools are read-only (`allowedOperations` are GETs) or `allowWrites` was reviewed with the API owner
- [ ] Instructions contain no URLs, hostnames, data or credentials
- [ ] Required roles for the agent identity exist in `agent_app_roles` (platform PR) if new APIs are used
- [ ] End-to-end and security tests updated if the demo prompt or expected answer changed

## Platform checklist (delete if not a Terraform change)

- [ ] Plan reviewed in the CI comment; no destroy/replace of APIM, VNet, Key Vault or state
- [ ] RBAC changes reviewed by security owners
- [ ] Dev and prod roots remain identical except tfvars

## Security

- [ ] No secrets, connection strings, tenant/subscription ids or client secrets in the diff

## Evidence

<!-- Plan excerpt, validation output, screenshots. -->
