# Rollback and disaster recovery

Two things can go wrong independently: the **platform** (Terraform) and the
**API configuration** (APIOps). Each has its own rollback path, and both
depend on knowing two states: what Git says should exist, and what Azure
actually has. That is why drift detection and rollback share tooling.

## Rolling back API configuration

| situation | action |
|---|---|
| a merged change broke an API | `git revert <sha>` → PR → merge. `apiops-publisher` publishes the revert commit in delta mode, which restores the previous artifacts (and re-creates anything the bad commit deleted). |
| a policy change needs to be undone quickly in prod | revert in Git and run `api-promote` with the revert SHA; the `production` reviewers gate it like any other promotion |
| a staged revision misbehaves | flip `isCurrent` back to the previous revision folder in a PR; the previous revision was never deleted |
| a new version is wrong | consumers on v1 were never touched; fix or retire v2 through a PR |
| APIM was edited by hand and Git must win | run `apiops-publisher` with `mode=full` (PUTs every artifact); then `apiops-extractor` to confirm zero drift |
| Git must be brought in line with APIM | run `apiops-extractor`, review and merge the drift PR |

APIM revisions give an in-service rollback for policy/configuration changes;
Git gives a full-fidelity rollback for everything else. The publisher is
idempotent, so re-running it is always safe.

## Rolling back the platform

| situation | action |
|---|---|
| a merged Terraform change is wrong | revert the commit; `terraform-ci` shows the reverse plan; merge; `terraform-deploy` applies it. The critical-resource guard still applies. |
| state file corrupted or wrong | Azure Storage blob versioning on `stcawstate4k7m`: restore the previous version of `platform/<env>.tfstate` (Blob Data Contributor), then `terraform plan` to confirm |
| state lost entirely | 30-day soft delete on the container; failing that, `terraform import` the resources (all names are deterministic from `name_prefix` + the suffix recorded in Key Vault tags / outputs) |
| a resource was deleted in Azure | `terraform plan` shows it as a create; apply recreates it. APIM specifically has soft delete (`recover_soft_deleted = true` in the provider features), so a deleted instance is recoverable for 48 hours |

## Disaster recovery for the whole environment

Everything needed to rebuild an environment is in Git plus three external inputs:

1. the bootstrap outputs (identity client ids → GitHub variables)
2. the Terraform state account (versioned; back it up with `az storage blob copy` to another region for prod)
3. Key Vault contents (soft delete + purge protection in prod; the only secrets are demo-client secrets and the App Insights connection string, both regenerable)

Rebuild order:

```text
terraform/bootstrap  →  terraform-deploy (new APIM instance)  →  apiops-publisher mode=full  →  application-deploy  →  post-deployment tests
```

Because APIOps publishes from Git, a new APIM instance receives every API,
product, policy and named value in one run. Consumers are unaffected if the
gateway hostname is fronted by a custom domain (prod: Front Door), which is
re-pointed at the new instance.

## Production-grade DR (documented, not deployed)

* APIM Premium multi-region or StandardV2 in two regions behind Front Door with health probes
* Availability zones for the primary region
* APIM backup/restore to a storage account (`az apim backup`) on a schedule as belt-and-braces alongside Git
* Geo-redundant state storage (GRS) and Key Vault backup
* Backends in paired regions with private endpoints in each
* Runbook rehearsed quarterly: restore into a scratch subscription from Git + backups and run the post-deployment tests

## RTO / RPO for this demo

| asset | RPO | RTO |
|---|---|---|
| API configuration | 0 (Git) | minutes (full publish) |
| platform | last applied commit | ~15 min on Consumption (StandardV2 similar; classic tiers 30-45 min) |
| Terraform state | last write (versioned) | minutes |
| backend code | Git | minutes (`application-deploy`) |
