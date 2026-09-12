# GitHub repository governance

## Branch strategy

```
feature/onboard-orders-api ──PR──▶ main ──push──▶ api-deploy (dev) ──approval──▶ (prod)
```

* `main` is the only deployable branch. Deployment workflows trigger on `push`
  to `main`; a push only happens through a merged PR because of the ruleset
  below.
* Feature branches are short-lived: `feature/<what>`, `fix/<what>`,
  `platform/<what>`.
* No environment is ever deployed from a feature branch. Even if a workflow on
  a branch tried, Entra would refuse the OIDC exchange: the deployer
  identities trust only `environment:development` / `environment:production`
  subjects, and the `pull_request` subject can only plan.

## Ruleset on `main`

Applied with `gh api` (see below) and kept in `docs/` as the source of truth:

| rule | value | why |
|---|---|---|
| Require a pull request before merging | on | every change is reviewed |
| Required approvals | 1 (enterprise: 2 for `terraform/platform/**`) | four-eyes |
| Dismiss stale approvals on new commits | on | re-review after force-pushed changes |
| Require review from Code Owners | on | CODEOWNERS routes to the owning team |
| Require conversation resolution | on | |
| Required status checks | `api definitions`, `plan (terraform/api-onboarding/dev)`, `fmt / validate / scan`, `plan (terraform/platform/dev)` (each only when its workflow ran) | no merge without a green plan |
| Require branches to be up to date | on | plan reflects `main` |
| Require linear history | on | clean, bisectable history |
| Block force pushes / deletions | on | |
| Bypass list | empty (enterprise: a break-glass admin team, audited) | |

Demo caveat: this repository lives under a personal account. GitHub does not
let the author approve their own PR, so the demo ruleset sets required
approvals to **0** while keeping every other rule; the PR history still shows
CI, plan comments and CODEOWNERS review requests. In an organisation set it to
1 or more.

## CODEOWNERS

`CODEOWNERS` uses org team handles (`@your-org/platform-team`, ...). In an
enterprise:

| team | owns | typical members |
|---|---|---|
| `platform-team` | `terraform/bootstrap`, `terraform/platform`, platform modules, `.github/workflows` | cloud/platform engineers |
| `security-team` | bootstrap (identities/RBAC), key-vault and identity modules | security engineering; second approver |
| `network-team` | networking module | network engineering |
| `api-platform-team` | `terraform/api-onboarding`, `apim-api` module, `apis/**`, Spectral rules and schema | API governance |
| `skills-team`, `orders-team`, `customer-team` | their `apis/<name>/` and `applications/<name>/` | product engineers |

Because the ruleset requires Code Owner review, a change to `apis/orders-api/`
needs the orders team **and** the API platform team, while a change to the
gateway module needs the platform team only. Nobody outside `platform-team`
can merge a change to `.github/workflows/`, which is where deployment
authority lives.

## Environments

| environment | protection | used by |
|---|---|---|
| `development` | none (auto-deploy after merge) | `platform-deploy`, `api-deploy`, `application-deploy` dev jobs, smoke tests |
| `production` | required reviewers (platform team), wait timer 5 min, deployment branches: `main` only | prod jobs; gated additionally by the `PROD_ENABLED` variable while no prod subscription exists |

Environment names are part of the OIDC subject, so Entra enforces the same
boundary GitHub does.

## Variables (no secrets)

Repository variables:

| name | value |
|---|---|
| `AZURE_TENANT_ID` | tenant id |
| `AZURE_SUBSCRIPTION_ID_DEV` / `_PROD` | subscription ids |
| `AZURE_PLATFORM_CLIENT_ID_DEV` / `_PROD` | bootstrap output `deployer_client_ids["platform-dev"]` / `["platform-prod"]` |
| `AZURE_API_CLIENT_ID_DEV` / `_PROD` | bootstrap output `deployer_client_ids["api-dev"]` / `["api-prod"]` |
| `PROD_ENABLED` | `false` until a prod subscription is bootstrapped |

There are **no repository secrets**.

## Applying the ruleset with gh

```bash
REPO=sampleworthy/cloudapiworkflow
gh api -X POST repos/$REPO/rulesets --input - <<'EOF'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash", "merge"] } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": true,
        "required_status_checks": [
          { "context": "api definitions" },
          { "context": "plan dev / plan (terraform/api-onboarding/dev)" } ] } }
  ]
}
EOF

gh api -X PUT repos/$REPO/environments/development
gh api -X PUT repos/$REPO/environments/production --input - <<'EOF'
{ "wait_timer": 5,
  "reviewers": [ { "type": "User", "id": <your user id> } ],
  "deployment_branch_policy": { "protected_branches": true, "custom_branch_policies": false } }
EOF
```
