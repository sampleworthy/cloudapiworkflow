# SKU and cost considerations

## APIM tiers, and why the demo runs on Consumption

| tier | approx. monthly (East US 2) | VNet | static egress IP | provisioning | notes |
|---|---|---|---|---|---|
| Consumption | $0 for the first 1M calls, then ~$3.50 / 1M | no | no | ~2 min | serverless; **no throttling policies at all** (`rate-limit*`, `quota*`, `llm-token-limit` rejected); no resource logs |
| Developer | ~$50 | injection | yes | 30-45 min | full features, no SLA |
| BasicV2 | ~$150 | no | no | minutes | SLA, no networking |
| StandardV2 | ~$700 | outbound integration + inbound private endpoint | no | minutes | the production choice here |
| Premium | ~$2,800 | injection, multi-region, zones | yes | 45+ min | enterprise scale |

"Consumers cannot bypass APIM" is satisfied on every tier by identity (Easy
Auth allow-listing APIM's managed identity), so the demo does not pay for
networking to prove it. Consumption provisions in minutes. Production tfvars
select StandardV2 with VNet integration and private endpoints; that
configuration is validated and planned by CI but not applied here.

Tier-specific behaviour lives in `terraform/modules/apim` (VNet mode derived
from the SKU; resource logs only where supported) and in policies
(`rate-limit-by-key`, available everywhere).

## Dev environment (applied)

| resource | SKU | monthly estimate |
|---|---|---|
| API Management | Consumption | $0-4 |
| App Service Plan | B1 Linux (skills + orders web apps) | ~$13 |
| Log Analytics + Application Insights | PerGB, 1 GB/day cap, 30-day retention | $0-3 |
| Key Vault | standard | < $1 |
| Private DNS zones (2), VNet, NSG | | ~$1 |
| State storage | Standard LRS | < $1 |
| Microsoft Foundry resource + project | S0, basic agent setup (Microsoft-managed storage) | $0 idle |
| Model deployment `gpt-4.1-mini` (GlobalStandard, 10K TPM) | pay per token; CI tests only | < $1 |
| GitHub Actions | public repo | $0 |
| **total** | | **~$16-22** |

APIOps itself costs nothing: two binaries downloaded at run time.

## Production (configured, documented, not applied)

| resource | SKU | monthly estimate |
|---|---|---|
| API Management | StandardV2_1 | ~$700 |
| App Service Plan | P1v3 | ~$140 |
| Private endpoints | 1 per backend + Key Vault | ~$7 each |
| Log Analytics | no cap, 90-day retention | usage-based |
| Front Door + WAF (enterprise) | Standard/Premium | ~$35 + usage / ~$330 + usage |
| Foundry private endpoint + standard agent setup (Cosmos DB, Storage, AI Search) | | ~$7 + ~$100+ |
| Model capacity (PTU) if latency SLAs require it | per PTU-hour | usage-based |
| **total** | | **~$900+** |

## Cost controls built in

* One App Service Plan for all backends; an API adds a web app, never a plan
* Log Analytics daily cap in dev; per-API diagnostic sampling; prod global sampling 20 %
* Consumption APIM idles at $0; Foundry and the model deployment idle at $0
* `llm-token-limit` daily quotas bound model spend per caller
* Tear-down order: `terraform destroy` in `environments/dev` (remove `prevent_destroy` first), then bootstrap
