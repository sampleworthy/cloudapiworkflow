#!/usr/bin/env bash
# Download and run a pinned Microsoft APIOps tool (extractor | publisher).
# Authentication: AZURE_BEARER_TOKEN if set (GitHub OIDC path), otherwise the
# tool's DefaultAzureCredential (Azure CLI locally). No client secrets.
#
# Usage: scripts/apiops.sh <extractor|publisher>
# Env:   APIOPS_VERSION (default v7.0.4), plus the tool's own variables:
#        AZURE_SUBSCRIPTION_ID AZURE_RESOURCE_GROUP_NAME API_MANAGEMENT_SERVICE_NAME
#        API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH [CONFIGURATION_YAML_PATH] [COMMIT_ID]
#        [API_SPECIFICATION_FORMAT=Yaml]
set -euo pipefail
TOOL="${1:?extractor|publisher}"
VERSION="${APIOPS_VERSION:-v7.0.4}"
CACHE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/apiops/$VERSION"
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  ASSET="$TOOL-linux-x64.zip" ;;
  Linux-aarch64) ASSET="$TOOL-linux-arm64.zip" ;;
  Darwin-arm64)  ASSET="$TOOL-osx-arm64.zip" ;;
  Darwin-x86_64) ASSET="$TOOL-osx-x64.zip" ;;
  *) echo "unsupported platform $(uname -s)-$(uname -m)"; exit 2 ;;
esac
mkdir -p "$CACHE"
if [ ! -x "$CACHE/$TOOL/$TOOL" ]; then
  echo "downloading APIOps $TOOL $VERSION ($ASSET)"
  curl -fsSL "https://github.com/Azure/apiops/releases/download/$VERSION/$ASSET" -o "$CACHE/$ASSET"
  mkdir -p "$CACHE/$TOOL" && unzip -oq "$CACHE/$ASSET" -d "$CACHE/$TOOL" && chmod +x "$CACHE/$TOOL/$TOOL"
fi
export API_SPECIFICATION_FORMAT="${API_SPECIFICATION_FORMAT:-Yaml}"
echo "running APIOps $TOOL $VERSION against $API_MANAGEMENT_SERVICE_NAME (${AZURE_RESOURCE_GROUP_NAME})"
exec "$CACHE/$TOOL/$TOOL"
