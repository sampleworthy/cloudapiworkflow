# Skills API

Read-only catalogue of technical skills. The first API onboarded to the shared
gateway and the reference example for every API that follows.

| | |
|---|---|
| Gateway path | `/skills/v1` |
| Product | `internal-apis` |
| Auth | Entra client credentials, audience `api://<tenant-id>/skills-api-<env>`, role `Skills.Read` |
| Rate limit | 100 calls / 60 s per caller |
| Backend | App Service on the shared plan, code in `applications/skills-api` |
| Owner | skills-team |

## Files

- `api.yaml` – metadata Terraform reads to register the API
- `openapi.yaml` – the contract; linted by Spectral in CI and imported into APIM
- `policies/inbound.xml` – JWT validation, rate limit, backend routing

## Calling it

```bash
TOKEN=$(scripts/get-token.sh skills-api)
curl -H "Authorization: Bearer $TOKEN" "$GATEWAY/skills/v1/skills"
```

`GET /skills/v1/health` needs no token.
