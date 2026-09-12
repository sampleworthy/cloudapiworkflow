#!/usr/bin/env bash
# Deleting an API folder from apim/artifacts is a retirement, which the
# publisher would execute (COMMIT_ID mode deletes removed artifacts). This
# guard refuses to publish a commit that deletes API folders unless the pull
# request that introduced it carried the "api-retirement" label.
# Usage: scripts/retirement-guard.sh <commit-sha>     (needs gh, GH_TOKEN)
set -euo pipefail
SHA="${1:?commit sha}"
deleted=$(git diff --name-only --diff-filter=D "$SHA~1" "$SHA" -- 'apim/artifacts/apis/*/apiInformation.json' | sed 's|apim/artifacts/apis/||; s|/apiInformation.json||' | sort -u)
[ -z "$deleted" ] && { echo "no API deletions in $SHA"; exit 0; }
echo "commit $SHA deletes API(s): $deleted"
labels=$(gh pr list --state merged --search "$SHA" --json labels --jq '.[0].labels[].name' 2>/dev/null || true)
if echo "$labels" | grep -qx "api-retirement"; then echo "retirement approved via label api-retirement"; exit 0; fi
echo "::error::API deletion without the api-retirement label. Follow docs/api-onboarding.md#retirement (deprecate first, then a labelled retirement PR)."; exit 1
