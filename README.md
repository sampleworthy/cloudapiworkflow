# cloudapiworkflow — an enterprise API platform on Azure API Management, built with Terraform and Microsoft APIOps

One shared Azure API Management instance per environment. **Terraform** builds
the platform once. **Microsoft APIOps** publishes every API from Git into that
instance, through pull requests, with validation, breaking-change detection,
approval, post-deployment tests, promotion and drift detection. Nobody
configures the gateway by hand, and adding an API never touches Terraform.

```text
PLATFORM (rare)                                     API LIFECYCLE (daily)

terraform/**  ─PR─▶ terraform-ci ─merge─▶            apim/artifacts/apis/orders-api-v1/ ─PR─▶ api-validation
  terraform-deploy ──OIDC──▶ rg-cloudapiworkflow        Spectral · oasdiff · policy · secrets · deletion guard
    ├── APIM service (Consumption dev / StandardV2 prod)      │ review (CODEOWNERS)  │ merge
    ├── VNet · private DNS · Key Vault                        ▼
    ├── Log Analytics · App Insights               apiops-publisher ──OIDC──▶ EXISTING APIM
    ├── App Service Plan + backend web apps            verify · 200 · 401 · 401 · 403 · 200 · 429 · backend 401
    └── Entra resource app · demo clients          api-promote (sha) ──reviewers──▶ prod
```

## What it governs

| workload | lifecycle | how it reaches the gateway | governed by |
|---|---|---|---|
| traditional APIs (Skills, Orders) | APIOps | applications with Entra tokens | `validate-jwt`, roles, rate limits, correlation |
| AI agents (API Platform Assistant) | Foundry CI/CD (`agents/`) | OpenAPI tools with the Foundry project's managed identity | the same API policies; read-only roles; caller attribution |
| AI models (`gpt-4.1-mini`) | APIOps (`foundry-models-v1`) | `/models/v1` with `Models.Use` | `llm-token-limit`, token metrics, deployment allow-list |
| MCP tools | APIOps (optional, preview) | APIM MCP server export | the underlying API's policies + tool allow-list |

The agent demo: "Show me order 1024." → agent → Orders tool → APIM → private
Orders API → answer, with APIM telemetry proving the path and a security test
proving the direct path is blocked. Details in
[docs/agentic-architecture.md](docs/agentic-architecture.md), [docs/ai-gateway.md](docs/ai-gateway.md), [docs/identity.md](docs/identity.md).

## The business problem

Developer → ticket → platform engineer → manual APIM configuration. It does
not scale, it drifts, nothing is reviewed, and every environment ends up
different. This repository replaces it with: API contract + configuration →
pull request → automated governance → approval → APIOps → the existing
gateway. Repeatable, auditable, least-privilege, and fast: an API is one
folder and one PR.

## Repository map

```text
terraform/bootstrap/            state storage, resource groups, OIDC identities (run once by a human)
terraform/modules/              apim · networking · key-vault · monitoring · identity · app-service · foundry
terraform/environments/{dev,prod}/   the platform; identical apart from tfvars
apim/artifacts/                 the APIOps tree: APIs, products, policies, named values, loggers, diagnostics, version sets, backends
apim/configuration.{dev,prod}.yaml   per-environment overrides (tokens filled from GitHub variables)
apim/extractor.config.yaml      what the extractor may pull back into Git
apis/<name>/README.md           owner, lifecycle, how to call
agents/<name>/                  agent definition, instructions, tools (published contracts only), tests
ai-gateway/README.md            map of the AI gateway artifacts inside apim/artifacts
applications/<name>/            FastAPI backends + tests (zip-deployed to App Service)
governance/.spectral.yaml       OpenAPI rules
scripts/                        apiops · render-configuration · validate-* · detect-breaking-changes · smoke-test · test-rate-limit · verify-publish · retirement-guard · apim-drift
.github/workflows/              terraform-ci · terraform-deploy · api-validation · apiops-publisher · api-promote · apiops-extractor · drift-detection · application-deploy · agent-ci · agent-deploy
docs/                           architecture · apiops · api-onboarding · agentic-architecture · ai-gateway · identity · terraform · security · operations · disaster-recovery · branch-protection · cost
```

## Why it is built this way

**Terraform creates APIM; APIOps manages APIs.** Terraform is right for
resources with a lifecycle of their own (SKU, network, identity) and wrong for
things that change daily and belong to many teams. APIOps understands APIM's
object model, publishes only what a commit changed, handles revisions and
deletions, and can pull the live configuration back for review. Terraform
stays small and stable; API teams get a tool built for their change rate.

**APIM is shared infrastructure.** One instance carries every API's policy,
identity, logging and product model. Per-team instances cost a fortune and
fragment governance. The instance has `prevent_destroy`, the CI guard refuses
plans that would replace it, and the onboarding path never runs Terraform.

**Git is the source of truth; developers do not modify APIM.** Nobody but the
publisher identity can write to the gateway, and only from `main`. Changes are
diffs, reviews and commits. Emergency edits go through a documented break-glass
plus an extractor PR so Git catches up.

**Publisher and extractor.** The publisher turns approved commits into APIM
state with `COMMIT_ID` delta semantics. The extractor is the mirror: it reads
APIM and opens a PR when reality differs from Git, and it never merges.

**Pull requests and CODEOWNERS.** Governance happens where the change is
visible. CODEOWNERS routes each API to its owning team plus the API platform
team, the gateway policy to security, workflows to the platform team.

**OpenAPI, Spectral, breaking changes.** The contract is the artifact. Spectral
enforces structure and documentation; oasdiff blocks incompatible changes to a
published version; a breaking change is a new version folder.

**Versions vs revisions.** Versions are new contracts side by side
(`/orders/v1`, `/orders/v2`). Revisions stage non-breaking policy or
configuration changes and can be flipped back.

**Entra ID and JWT validation at the gateway.** One resource app per
environment exposes application permissions as app roles. APIM validates
issuer, audience and roles before any backend is touched, so every API gets
the same authentication and the backend can trust the gateway.

**Managed identity between APIM and backends; private networking.** APIM
calls backends as its own identity; backends accept only that identity, so the
gateway cannot be bypassed even on the Consumption tier. Prod adds VNet
integration and private endpoints with the same code.

**OIDC for GitHub Actions.** Eight federated identities (platform, APIOps
publisher, APIOps extractor, agent deployer × dev/prod) with least-privilege RBAC. No secrets exist in GitHub.
The OIDC subject is the security boundary, and it equals the GitHub
environment, so Entra enforces the same approval gates GitHub does.

**Terraform state in Azure Storage.** Entra-only, versioned, soft-deleted,
one container per layer with RBAC. State is never in Git.

**Protected retirement.** Deleting an API is a labelled, reviewed PR after a
deprecation period; the publisher refuses unlabelled deletions.

**Post-deployment tests.** A green publish proves nothing; the tests prove the
API answers, authentication and authorization behave (401/401/403/200), rate
limiting works (429, on classic/v2 tiers; Consumption has no throttling
policies), and the backend is unreachable without the gateway.

**Both kinds of drift.** Terraform plan on a schedule finds platform drift;
the extractor finds APIM drift. Both report; neither remediates.

**Environment promotion.** The same commit SHA is published to prod with prod
overrides after dev tests pass and production reviewers approve.

**Reuse the API platform for AI.** Agents need exactly what applications
need: authenticated, authorized, rate-limited, observed access to APIs. A
second gateway for AI would duplicate policy, identity and monitoring and
create a place where governance differs. The agent is one more caller.

**APIM as the AI gateway.** It already validates identity and applies limits;
the AI Gateway policies add token limits, quotas and token metrics for model
traffic, and the same instance can front models and MCP tools. One place to
look, one place to change.

**Agents never call backends.** Backends accept only the gateway's identity,
agent definitions cannot contain hosts, and CI plus a live security test keep
it that way. Everything an agent does is a gateway request with its client id
on it.

**Three lifecycles, three tools.** Platform changes are rare and dangerous
(Terraform, reviewed plans, destroy guard). API changes are frequent and
belong to API teams (APIOps). Agent changes are frequent, belong to AI teams,
and are versioned in Foundry (SDK-driven deploy). Coupling them would make
every team wait on every other.

**Agent identity is a workload identity.** Every agent gets its own Entra
Agent ID identity from Foundry; its definition declares read-only roles that
the platform allow-lists and `agent-deploy` grants. Users are authenticated by
the application; user-scoped authorization is propagated by the application
or asserted to the gateway, never by widening the agent's roles.

**Preview features are optional.** MCP export and MCP OAuth in APIM are
preview and the demo runs without them; token limits, token metrics, backend
pools and the Foundry agent service are GA.

Full answers: [docs/architecture.md](docs/architecture.md), [docs/apiops.md](docs/apiops.md), [docs/security.md](docs/security.md), [docs/agentic-architecture.md](docs/agentic-architecture.md), [docs/ai-gateway.md](docs/ai-gateway.md), [docs/identity.md](docs/identity.md).

## Onboarding an API

1. Copy `apim/artifacts/apis/skills-api-v1/` to `orders-api-v1/`, edit the contract, policy and `apiInformation.json`; add the version set, backend and product link; add the backend URL token to both configuration files; add `apis/orders-api/README.md`.
2. Open a PR. `api-validation` runs artifact checks, Spectral, oasdiff, policy validation, gitleaks and the deletion guard. CODEOWNERS requests review.
3. Merge. `apiops-publisher` publishes the commit into the existing instance, verifies path/version/revision, and runs the test matrix.
4. `api-promote` with the SHA takes it to prod behind reviewers.

Walkthrough with every file: [docs/api-onboarding.md](docs/api-onboarding.md).

## Demonstration: Orders API added to the existing instance

<!-- evidence:start -->
Before the Orders API pull request:

```text
$ az apim api list -g rg-cloudapiworkflow -n apim-cloudapiworkflow-<suffix> -o table
Name           Path     ApiVersion  ApiRevision
-------------  -------  ----------  -----------
skills-api-v1  skills   v1          1
```

After the PR merged (`apiops-publisher` run, same APIM resource id):

```text
Name           Path     ApiVersion  ApiRevision
-------------  -------  ----------  -----------
skills-api-v1  skills   v1          1
orders-api-v1  orders   v1          1
```

Post-deployment tests for `orders-api-v1`: health 200, no token 401, invalid
token 401, unprivileged client 403, agent client 200, 70 calls against a
60/min limit produced 429 with `Retry-After`, direct backend call 401.
<!-- evidence:end -->

## Getting started (platform administrator)

```bash
# 0. az login (Owner + Application Administrator), terraform 1.16.2, gh
# 1. bootstrap once: state storage, rg-cloudapiworkflow, six OIDC identities
cd terraform/bootstrap && terraform init && terraform apply && terraform output -raw github_variables | bash
# 2. GitHub environments + ruleset               docs/branch-protection.md
# 3. terraform-deploy (dispatch)                 creates the platform, publishes outputs as variables
# 4. apiops-publisher (dispatch, mode=full)      seeds the instance from apim/artifacts
# 5. every API from now on is a pull request
```

## Demo vs production

The dev environment runs on Consumption APIM and one B1 plan for roughly
$15-20 a month; the security properties are enforced by identity, so they do
not depend on tier. Production tfvars select StandardV2 with VNet integration,
private endpoints, purge protection and longer retention. The enterprise
additions (multi-region, availability zones, Front Door + WAF, enterprise DNS,
subscription per environment, Azure Policy, Defender for Cloud, central
logging, DR rehearsal, PIM-based RBAC, HSM-backed Key Vault) are described in
[docs/cost.md](docs/cost.md) and [docs/disaster-recovery.md](docs/disaster-recovery.md)
rather than deployed for appearance.

## Acceptance criteria

| # | criterion | where |
|---|---|---|
| 1-4 | Terraform creates `rg-cloudapiworkflow`, APIM, remote state, the shared platform | `terraform/`, `docs/terraform.md` |
| 5-6 | APIOps manages the API lifecycle; Git is the source of truth | `apim/`, `docs/apiops.md` |
| 7-8 | Adding an API creates no APIM and changes no Terraform module | `apiops-publisher`; CI guard; `docs/api-onboarding.md` |
| 9-11 | Publisher deploys approved changes; extractor detects and requires review | `apiops-publisher.yml`, `apiops-extractor.yml` |
| 12-13 | OIDC, no long-lived secrets | `terraform/bootstrap`, `docs/security.md` |
| 14-16 | OpenAPI validation, Spectral, breaking-change detection | `api-validation.yml`, `governance/`, `scripts/` |
| 17 | Policies in Git | `apim/artifacts/**/policy.xml` |
| 18-20 | Entra protection, claim validation, managed identity to backends | `apim/artifacts/apis/*/policy.xml`, `modules/app-service` |
| 21 | Backends cannot bypass APIM | Easy Auth allow-list; smoke test asserts 401 |
| 22 | Post-deployment tests | `scripts/smoke-test.sh`, `scripts/test-rate-limit.sh` |
| 23 | DEV → PROD promotion | `api-promote.yml` |
| 24-25 | Infrastructure and APIM drift detection | `drift-detection.yml`, `scripts/apim-drift.py` |
| 26 | Controlled API deletion | `scripts/retirement-guard.sh`, deletion guard in `api-validation` |
| 27 | Versions and revisions | version sets, `;rev=` folders, `docs/api-onboarding.md` |
| 28 | Centralized monitoring | APIOps logger/diagnostics → App Insights → Log Analytics |
| 29-30 | Skills API deployed; Orders API onboarded into the same instance | evidence above |

### Agentic extension

| # | criterion | where |
|---|---|---|
| 1-3 | existing APIM reused; Terraform owns platform; APIOps owns APIs | `terraform/modules/foundry`, `apim/artifacts/apis/foundry-models-v1` |
| 4-6 | separate agent lifecycle, GitHub Actions, OIDC | `agents/`, `agent-ci.yml`, `agent-deploy.yml`, `sp-cloudapiworkflow-agent-deployer-<env>` |
| 7-8 | agent calls Orders through APIM, never the backend | end-to-end test + security test in `agent-deploy` |
| 9-11 | workload identity, APIM policies govern agent traffic, backends protected | Foundry project identity + app roles; unchanged API policies; Easy Auth |
| 12 | AI/agent telemetry observable | Foundry tracing connection, `X-Caller-Id`, token metrics, `docs/agentic-architecture.md` |
| 13 | no credentials in agent instructions | `agent-ci` hygiene checks |
| 14-15 | MCP documented; preview features identified | `docs/ai-gateway.md` capability table |
| 16-18 | cost-conscious demo; production documented; unified governance | `docs/cost.md`, `docs/agentic-architecture.md`, this README |
