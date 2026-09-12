#!/usr/bin/env bash
# Breaking-change detection with oasdiff: compares every changed API
# specification against the same file on the base branch. A breaking change
# fails unless the spec is new (a new version folder), which is the only
# sanctioned way to ship an incompatible contract.
#
# Usage: scripts/detect-breaking-changes.sh [base-ref]   (default origin/main)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
BASE="${1:-origin/main}"; OASDIFF_VERSION="${OASDIFF_VERSION:-1.31.0}"
if ! command -v oasdiff >/dev/null 2>&1; then
  os=$(uname -s | tr A-Z a-z); arch=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
  curl -fsSL "https://github.com/oasdiff/oasdiff/releases/download/v${OASDIFF_VERSION}/oasdiff_${OASDIFF_VERSION}_${os}_${arch}.tar.gz" | tar -xz -C "${RUNNER_TEMP:-/tmp}" oasdiff
  export PATH="${RUNNER_TEMP:-/tmp}:$PATH"
fi
git fetch -q origin "${BASE#origin/}" 2>/dev/null || true
changed=$(git diff --name-only "$BASE"...HEAD -- 'apim/artifacts/apis/*/specification.yaml' 2>/dev/null || git diff --name-only "$BASE" -- 'apim/artifacts/apis/*/specification.yaml')
[ -z "$changed" ] && { echo "no specification changes"; exit 0; }
fail=0
for spec in $changed; do
  if ! git cat-file -e "$BASE:$spec" 2>/dev/null; then echo "NEW  $spec (no base to compare; new API or new version)"; continue; fi
  git show "$BASE:$spec" > /tmp/base-spec.yaml
  echo "== $spec"
  if oasdiff breaking /tmp/base-spec.yaml "$spec" --fail-on ERR --format text; then echo "OK   no breaking changes"; else
    echo "::error file=$spec::breaking change detected. Ship it as a new version folder (e.g. apis/<name>-v2) instead of changing the published contract."; fail=1; fi
done
exit $fail
