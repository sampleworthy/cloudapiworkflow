#!/usr/bin/env bash
# Lints OpenAPI documents with Spectral using the repo ruleset (.spectral.yaml).
# Usage: scripts/validate-openapi.sh [file ...]   (default: apis/*/openapi.yaml)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ $# -eq 0 ]; then set -- apis/*/openapi.yaml; fi
if command -v spectral >/dev/null 2>&1; then
  spectral lint --ruleset .spectral.yaml --fail-severity=error "$@"
else
  npx --yes @stoplight/spectral-cli@6 lint --ruleset .spectral.yaml --fail-severity=error "$@"
fi
