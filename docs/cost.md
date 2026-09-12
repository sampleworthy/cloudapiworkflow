# SKU and cost considerations

## APIM tiers, and why the demo runs on Consumption

| tier | approx. monthly (East US 2) | VNet | static egress IP | provisioning | notes |
|---|---|---|---|---|---|
| Consumption | $0 for the first 1M calls, then ~$3.50 / 1M | no | no | ~2 min | serverless; no `rate-limit`/`quota` (use `*-by-key`), no resource logs, no developer portal |
| Developer | ~$50 | injection (internal/external) | yes | 30-45 min | full features, no SLA; good for a networking demo |
| BasicV2 | ~$150 | no | no | minutes | SLA, no networking |
| StandardV2 | ~$700 | outbound integration + inbound private endpoint | no (use integration) | minutes | the production choice here |
| Premium | ~$2,800 | injection, multi-region | yes | 45+ min | availability zones, self-hosted gateways |

The requirement "consumers cannot bypass APIM" is satisfied on **every** tier
by identity (Easy Auth allow-listing APIM's managed identity), so the demo
does not need to pay for networking to prove it. Consumption also provisions
in minutes, which keeps the platform bootstrap under a coffee break. The
production tfvars select StandardV2 with VNet integration and private
endpoints so the network path is closed as well; that configuration is
validated and planned by CI but not applied in this demo.

Tier-specific behaviour is handled in `terraform/modules/apim`:

* `virtual_network_type` is derived from the SKU (`None` on Consumption, `External` on V2, injection on classic)
* the Log Analytics diagnostic setting is created only when the tier supports resource logs
* policies use `rate-limit-by-key` / `quota-by-key`, which exist on all tiers

## Dev environment (applied)

| resource | SKU | monthly estimate |
|---|---|---|
| API Management | Consumption | $0-4 |
| App Service Plan | B1 Linux (hosts skills + orders) | ~$13 |
| Log Analytics + Application Insights | PerGB, 1 GB/day cap, 30-day retention | $0-3 |
| Key Vault | standard | < $1 |
| Private DNS zones (2) | | ~$1 |
| VNet, NSG, subnets | | $0 |
| State storage | Standard LRS | < $1 |
| **total** | | **~$15-20** |

Tear-down: `terraform destroy` in `api-onboarding/dev`, then `platform/dev`
(the resource group has `prevent_destroy`; remove it for a full clean-up),
then bootstrap.

## Production environment (configured, not applied)

| resource | SKU | monthly estimate |
|---|---|---|
| API Management | StandardV2_1 | ~$700 |
| App Service Plan | P1v3 | ~$140 |
| Private endpoints | 1 per backend + Key Vault | ~$7 each |
| Log Analytics | no cap, 90-day retention | usage-based |
| Key Vault | standard, purge protection | < $1 |
| **total** | | **~$900+** |

## Cost controls built in

* One App Service Plan for all backends; an API adds a web app, not a plan
* Log Analytics daily cap in dev
* Per-API sampling percentage for APIM diagnostics (`api.yaml` → `diagnostics.samplingPercentage`)
* `mock` backend type lets an API be onboarded (contract, identity, policy) with zero compute
* Consumption APIM idles at $0
