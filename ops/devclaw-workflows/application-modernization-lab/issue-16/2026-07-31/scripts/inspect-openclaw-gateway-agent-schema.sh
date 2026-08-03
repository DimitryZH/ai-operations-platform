#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/openclaw-gateway-agent-schema-inspection.json}"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"

run_as_devclaw() {
  runuser -u devclaw-svc -- env \
    HOME=/home/devclaw-svc \
    OPENCLAW_STATE_DIR="${state_dir}" \
    OPENCLAW_CONFIG_PATH="${state_dir}/openclaw.json" \
    OPENCLAW_NO_COLOR=1 \
    OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}" \
    "$@"
}

source "${gateway_env}"
mkdir -p "$(dirname "${out_file}")"

status_json="$(run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000)"
health_json="$(run_as_devclaw /usr/local/bin/openclaw gateway call health --json --timeout 10000)"

jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson status "${status_json}" \
  --argjson health "${health_json}" \
  '{
    checkedAt:$checkedAt,
    status:$status,
    health:$health
  }' | tee "${out_file}"
