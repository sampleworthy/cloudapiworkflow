# Orders API

Create and query customer orders. Onboarded in its own pull request after the
Skills API to demonstrate that a second API lands in the **existing** APIM
instance through APIOps, with no Terraform change.

| | |
|---|---|
| Lifecycle | **active** |
| Gateway path | `/orders/v1` |
| APIOps folder | `apim/artifacts/apis/orders-api-v1/` |
| Version set | `apim/artifacts/version sets/orders-api/` |
| Product | `internal-apis` |
| Auth | Entra client credentials, audience `api://<tenant-id>/cloudapiworkflow-<env>` |
| Roles | `Orders.Read` for GET, `Orders.Write` for anything else |
| Rate limit | 60 calls / 60 s per caller |
| Backend | `app-orders-api-<suffix>` (App Service), code in `applications/orders-api` |
| Owner | orders-team |

## Calling it

```bash
TOKEN=$(scripts/get-token.sh agent dev)
curl -H "Authorization: Bearer $TOKEN" "$APIM_GATEWAY_URL/orders/v1/orders"
```
