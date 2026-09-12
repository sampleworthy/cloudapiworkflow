# GitHub repository governance

## Branch strategy

```text
feature/onboard-orders-api ──PR──▶ main ──push──▶ apiops-publisher (dev) ──api-promote + approval──▶ prod
```

* `main` is the only deployable branch. Deployment workflows trigger on `push` to `main`, and a push only happens through a merged PR because of the ruleset below.
* Feature branches are short-lived: `feature/<what>`, `fix/<what>`, `platform/<what>`; extractor PRs use `apiops/extract-<env>`.
* Nothing deploys from a feature branch even if a workflow tried: the deployer identities trust only `environment:development` / `environment:production` subjects (and `pull_request` for a plan), so Entra refuses the token exchange.

## Ruleset on `main`

| rule | value | why |
|---|---|---|
| Require a pull request before merging | on | every change is reviewed |
| Required approvals | 1 (enterprise: 2 for `terraform/bootstrap`, `apim/artifacts/policy.xml`) | four-eyes |
| Dismiss stale approvals on new commits | on | re-review after new commits |
| Require review from Code Owners | on | CODEOWNERS routes to the owning team |
| Require conversation resolution | on | |
| Required status checks | `api definitions` (api-validation, runs on every PR); `fmt / validate / scan` and `plan dev` when `terraform-ci` ran | no merge without green validation |
| Require branches to be up to date | on | validation reflects `main` |
| Require linear history | on | clean history; promotion by SHA is unambiguous |
| Block force pushes / deletions | on | |
| Require signed commits | recommended in enterprises (GPG/SSH signing enforced org-wide) | provenance |
| Bypass list | empty (enterprise: a break-glass admin team, audited) | |

Demo caveat: this repository lives under a personal account, and GitHub does
not let an author approve their own PR, so the demo ruleset sets required
approvals to 0 while keeping every other rule. Rulesets and environment
reviewers require a public repository (or GitHub Pro) on a personal account.

## CODEOWNERS

`CODEOWNERS` uses org team handles (`@your-org/platform-team`, ...):

| team | owns |
|---|---|
| `platform-team` | `terraform/`, `.github/`, `scripts/` |
| `security-team` | bootstrap (identities/RBAC), key-vault and identity modules, the global policy |
| `network-team` | networking module |
| `api-platform-team` | `apim/` (products, named values, overrides), `governance/`, `apis/` |
| `skills-team`, `orders-team` | their API folder under `apim/artifacts/apis/`, their README and application |

Because the ruleset requires Code Owner review, a change to
`apim/artifacts/apis/orders-api-v1/` needs the orders team **and** the API
platform team; a change to `apim/configuration.prod.yaml` needs the API
platform team and the platform team; nobody outside `platform-team` can
change `.github/workflows/`, which is where deployment authority lives.

## Environments

| environment | protection | used by |
|---|---|---|
| `development` | none (auto-deploy after merge) | terraform-deploy dev, apiops-publisher, application-deploy, drift plan |
| `production` | required reviewers (platform team), 5-minute wait timer, deployment branches: `main` only | terraform-deploy prod, api-promote; also gated by `PROD_ENABLED` until a prod subscription exists |

Environment names are part of the OIDC subject, so Entra enforces the same
boundary GitHub does.

## Variables (there are no secrets)

| variable | source |
|---|---|
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID_DEV`, `AZURE_SUBSCRIPTION_ID_PROD` | bootstrap |
| `AZURE_PLATFORM_CLIENT_ID_<ENV>`, `AZURE_APIOPS_PUBLISHER_CLIENT_ID_<ENV>`, `AZURE_APIOPS_EXTRACTOR_CLIENT_ID_<ENV>` | bootstrap output `github_variables` |
| `APIM_NAME_<ENV>`, `APIM_GATEWAY_URL_<ENV>`, `APIM_RESOURCE_GROUP_<ENV>`, `API_AUDIENCE_<ENV>`, `AGENT_CLIENT_ID_<ENV>`, `UNPRIVILEGED_CLIENT_ID_<ENV>`, `APPINSIGHTS_ID_<ENV>`, `APPINSIGHTS_SECRET_ID_<ENV>`, `KEY_VAULT_NAME_<ENV>`, `BACKEND_URL_<API>_<ENV>` | written by `terraform-deploy` from the root's `github_variables` output |
| `PROD_ENABLED` | `false` until a prod subscription is bootstrapped |

## Applying the ruleset with gh

```bash
REPO=sampleworthy/cloudapiworkflow
gh api -X POST repos/$REPO/rulesets --input - <<'EOF'
{
  "name": "main", "target": "branch", "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" }, { "type": "non_fast_forward" }, { "type": "required_linear_history" },
    { "type": "pull_request", "parameters": { "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true, "require_last_push_approval": false, "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash", "merge"] } },
    { "type": "required_status_checks", "parameters": { "strict_required_status_checks_policy": true, "do_not_enforce_on_create": true,
        "required_status_checks": [ { "context": "api definitions" } ] } }
  ]
}
EOF
gh api -X PUT repos/$REPO/environments/development
gh api -X PUT repos/$REPO/environments/production --input - <<EOF
{ "wait_timer": 5, "reviewers": [ { "type": "User", "id": $(gh api user --jq .id) } ],
  "deployment_branch_policy": { "protected_branches": true, "custom_branch_policies": false } }
EOF
```
