#!/usr/bin/env bash
# Acquire a client-credentials token for an onboarded API as the demo agent
# client, for local testing. The client secret is read from Key Vault by the
# signed-in user (RBAC: Key Vault Secrets User); nothing is stored locally.
#
# Usage: scripts/get-token.sh <api-name> [env]      e.g. scripts/get-token.sh orders-api dev
# Env:   RESOURCE_GROUP (default rg-cloudapiworkflow)
set -euo pipefail
API="${1:?api name, e.g. orders-api}"; ENV="${2:-dev}"
RG="${RESOURCE_GROUP:-rg-cloudapiworkflow}"

TENANT=$(az account show --query tenantId -o tsv)
CLIENT_ID=$(az ad app list --display-name "cloudapiworkflow-agent-client-$ENV" --query "[0].appId" -o tsv)
KV=$(az keyvault list -g "$RG" --query "[0].name" -o tsv)
SECRET=$(az keyvault secret show --vault-name "$KV" -n agent-client-secret --query value -o tsv)
AUDIENCE="api://$TENANT/$API-$ENV"

curl -fsS -X POST "https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  --data-urlencode "client_secret=$SECRET" \
  --data-urlencode "scope=$AUDIENCE/.default" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
