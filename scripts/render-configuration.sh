#!/usr/bin/env bash
# Fill {#TOKEN#} placeholders in an APIOps configuration file from environment
# variables. In CI the variables are GitHub repository variables written by
# terraform-deploy (e.g. APIM_NAME_DEV); pass the environment suffix and the
# script looks up TOKEN_<SUFFIX> first, then TOKEN.
#
# Usage: scripts/render-configuration.sh apim/configuration.dev.yaml DEV > rendered.yaml
set -euo pipefail
FILE="${1:?configuration file}"; SUFFIX="${2:-}"
python3 - "$FILE" "$SUFFIX" <<'PY'
import os, re, sys
path, suffix = sys.argv[1], sys.argv[2]
text = open(path).read()
missing = []
def sub(m):
    name = m.group(1)
    for key in ([f"{name}_{suffix}"] if suffix else []) + [name]:
        if os.environ.get(key):
            return os.environ[key]
    missing.append(name); return m.group(0)
out = re.sub(r"\{#([A-Z0-9_]+)#\}", sub, text)
if missing:
    sys.exit(f"unresolved tokens in {path}: {sorted(set(missing))} (expected variables like {missing[0]}_{suffix or 'ENV'})")
sys.stdout.write(out)
PY
