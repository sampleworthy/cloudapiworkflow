# Skills API

Read-only catalogue of technical skills. The first API published to the shared
gateway and the reference example for every API that follows.

| | |
|---|---|
| Lifecycle | **active** |
| Gateway path | `/skills/v1` |
| APIOps folder | `apim/artifacts/apis/skills-api-v1/` |
| Version set | `apim/artifacts/version sets/skills-api/` |
| Product | `internal-apis` |
| Auth | Entra client credentials, audience `api://<tenant-id>/cloudapiworkflow-<env>`, role `Skills.Read` |
| Rate limit | 100 calls / 60 s per caller |
| Backend | `app-skills-api-<suffix>` (App Service), code in `applications/skills-api` |
| Owner | skills-team |

## Calling it

```bash
TOKEN=$(scripts/get-token.sh agent dev)
curl -H "Authorization: Bearer $TOKEN" "$APIM_GATEWAY_URL/skills/v1/skills"
```

`GET /skills/v1/health` needs no token.

## Changing it

Edit the files under the APIOps folder and open a pull request. Breaking
contract changes go in a new folder `skills-api-v2` (see docs/api-onboarding.md).
