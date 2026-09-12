#!/usr/bin/env bash
# Lint every API specification in the APIOps tree with Spectral.
# Usage: scripts/validate-openapi.sh [file ...]   (default: apim/artifacts/apis/*/specification.yaml)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
if [ $# -eq 0 ]; then set -- apim/artifacts/apis/*/specification.yaml; fi
RULESET=governance/.spectral.yaml
if command -v spectral >/dev/null 2>&1; then
  spectral lint --ruleset "$RULESET" --fail-severity=error "$@"
else
  npx --yes @stoplight/spectral-cli@6 lint --ruleset "$RULESET" --fail-severity=error "$@"
fi
