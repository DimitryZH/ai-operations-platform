#!/usr/bin/env bash
set -euo pipefail

gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"

if [[ ! -f "$gateway_env" ]]; then
  echo "missing gateway env: $gateway_env" >&2
  exit 1
fi

set -a
source "$gateway_env"
set +a

openclaw gateway call health \
  --url ws://127.0.0.1:18789 \
  --token "$OPENCLAW_GATEWAY_TOKEN" \
  --json

openclaw gateway call status \
  --url ws://127.0.0.1:18789 \
  --token "$OPENCLAW_GATEWAY_TOKEN" \
  --json
