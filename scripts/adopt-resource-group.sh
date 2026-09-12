#!/usr/bin/env bash
# One-time hand-over of rg-cloudapiworkflow from bootstrap to the platform
# layer. Bootstrap creates the group (so RBAC can be scoped to it before the
# platform identity exists); the platform layer manages it from then on.
# Idempotent: does nothing once the group is in platform state.
#
# Usage: scripts/adopt-resource-group.sh <platform-root-dir> <subscription-id> [resource-group-name]
set -euo pipefail
ROOT_DIR="$1"; SUB="$2"; RG="${3:-rg-cloudapiworkflow}"
cd "$ROOT_DIR"
if terraform state list 2>/dev/null | grep -qx 'azurerm_resource_group.main'; then
  echo "resource group already managed by platform state"
  exit 0
fi
echo "importing $RG into platform state"
terraform import -input=false -no-color azurerm_resource_group.main "/subscriptions/$SUB/resourceGroups/$RG"
