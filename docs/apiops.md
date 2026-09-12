# Microsoft APIOps in this repository

[APIOps](https://azure.github.io/apiops/) is Microsoft's toolkit for treating
API Management configuration as code. Two binaries, released on GitHub:

| tool | reads | writes | identity here |
|---|---|---|---|
| **extractor** | the live APIM instance | a folder tree in the APIOps layout | `sp-cloudapiworkflow-apiops-extractor-<env>` (API Management Service Reader Role) |
| **publisher** | a folder tree in the APIOps layout (+ per-environment overrides) | the live APIM instance | `sp-cloudapiworkflow-apiops-publisher-<env>` (API Management Service Contributor) |

Version pinned: **v7.0.4** (`scripts/apiops.sh`). Both tools authenticate with
`AZURE_BEARER_TOKEN`, which the workflows obtain from `az account get-access-token`
after an OIDC `azure/login`. No client secret exists.

## Why Terraform creates APIM but APIOps manages APIs

Terraform is excellent at long-lived resources with a lifecycle of their own
(SKU, network, identity) and terrible as a day-to-day API deployment tool:
every API becomes state, every policy change is a plan/apply cycle owned by
the platform team, and a mistake in one API's HCL can fail the plan for all
of them. APIOps understands APIM's own object model, publishes only what
changed in a commit, handles revisions and deletions, and can pull the live
configuration back into Git for review. Splitting the two keeps Terraform
small and stable and gives API teams a tool designed for their change rate.

## The artifact tree (`apim/artifacts`)

The layout is dictated by the tools, not by this repository:

```text
apim/artifacts/
├── policy.xml                                   global policy
├── named values/<name>/namedValueInformation.json
├── loggers/appinsights/loggerInformation.json
├── diagnostics/applicationinsights/diagnosticInformation.json
├── products/<product>/productInformation.json
├── products/<product>/policy.xml
├── products/<product>/apis/<api>/productApiInformation.json   product ↔ API link
├── version sets/<name>/versionSetInformation.json
├── backends/<name>/backendInformation.json
└── apis/<api>-v<n>/
    ├── apiInformation.json                      path, version, version set, revision
    ├── specification.yaml                       OpenAPI 3.x
    ├── policy.xml                               API policy
    ├── operations/<operationId>/policy.xml      optional operation policies
    └── diagnostics/applicationinsights/diagnosticInformation.json
```

Revisions: a sibling folder `apis/<api>-v<n>;rev=<r>/` with its own
`apiInformation.json` (`apiRevision`, `isCurrent`). Versions: a new folder
`apis/<api>-v<n+1>/` pointing at the same version set.

## Environment overrides

`apim/configuration.<env>.yaml` follows the publisher's override schema. The
artifact tree holds placeholders for anything environment-bound (backend
URLs, App Insights ids, Key Vault secret ids, tenant id) and the override
file sets the real value. Real values are not committed: `{#NAME#}` tokens are
filled at publish time by `scripts/render-configuration.sh` from GitHub
repository variables that `terraform-deploy` writes after each apply
(`APIM_NAME_DEV`, `API_AUDIENCE_DEV`, `BACKEND_URL_SKILLS_API_DEV`, ...).

Named values referenced by policies (`{{tenant-id}}`, `{{api-audience}}`)
make the policy XML identical in every environment. The App Insights
connection string is a Key Vault-backed named value read by the gateway's
managed identity, so it never leaves Key Vault.

## Publisher modes

| mode | when | behaviour |
|---|---|---|
| `COMMIT_ID=<sha>` (default) | merge to main, promotion | publishes only artifacts changed in that commit; deleted folders are deleted in APIM |
| full (no `COMMIT_ID`) | resync, disaster recovery | PUTs every artifact; never deletes |

Delta mode is what makes retirement real, which is why deletions are guarded
(`scripts/retirement-guard.sh`).

## Extractor scope and drift

`apim/extractor.config.yaml` lists what the extractor may pull. The drift
comparison (`scripts/apim-drift.py`) computes *expected* = artifacts with the
environment's overrides applied, and compares it with the extracted tree:

* JSON semantically (order, whitespace, server-managed fields ignored)
* policies after whitespace normalisation
* OpenAPI by operation set (path, method, operationId), because APIM
  re-serialises the document on export

Drift produces a pull request on branch `apiops/extract-<env>` with label
`apim-drift`. It is never merged automatically; the reviewer decides whether
Git or Azure is right. Files that exist only in APIM are copied into the PR;
files missing from APIM are reported, not deleted from Git.

## Seeding the tree

The first tree was authored by hand from the tool's source (`src/common/*.cs`
defines the folder and file names), published, then confirmed by running the
extractor against the freshly published instance so Git matches what the
tool writes. From then on the extractor is only used for drift.

## Break-glass

If an operator must change APIM directly during an incident:

1. Make the change in the portal; record it in the incident ticket.
2. Within one business day run `apiops-extractor` (manual dispatch). Review and merge the drift PR so Git is authoritative again.
3. The next `apiops-publisher` run will not revert the change because Git now contains it.

Skipping step 2 means the next delta publish that touches the same artifact
overwrites the manual change, and the daily drift job will keep opening PRs.
