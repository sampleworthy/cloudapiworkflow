# apim/ — the API Management configuration, as code

`artifacts/` is the exact folder layout Microsoft APIOps uses: the publisher
reads it, the extractor writes it. Do not add other formats here.

| path | what |
|---|---|
| `artifacts/policy.xml` | global policy (correlation id, security headers, error shape) |
| `artifacts/products/<product>/` | product definition, product policy, and `apis/<api>/` links |
| `artifacts/named values/<name>/` | configuration values referenced by policies as `{{name}}` |
| `artifacts/loggers/appinsights/` | Application Insights logger (connection string from Key Vault) |
| `artifacts/diagnostics/applicationinsights/` | gateway-wide diagnostics |
| `artifacts/version sets/<api>/` | one per logical API; versions hang off it |
| `artifacts/backends/<api>/` | named backend entities (URL overridden per environment) |
| `artifacts/apis/<api>-<version>/` | `apiInformation.json`, `specification.yaml`, `policy.xml`, `diagnostics/` |
| `configuration.<env>.yaml` | per-environment overrides (tokens filled from GitHub variables) |
| `extractor.config.yaml` | what the extractor is allowed to pull back into Git |

Revisions live in sibling folders named `<api>;rev=<n>`. See
[docs/apiops.md](../docs/apiops.md) and [docs/api-onboarding.md](../docs/api-onboarding.md).
