#!/usr/bin/env bash
set -euo pipefail

workflow_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prompt_file="${workflow_dir}/prompts/apply-proposal-request.md"
out_file="${1:-${workflow_dir}/evidence/apply-result.json}"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"

mkdir -p "$(dirname "${out_file}")"

if [[ ! -f "${prompt_file}" ]]; then
  echo "missing prompt file: ${prompt_file}" >&2
  exit 1
fi

if [[ ! -f "${gateway_env}" ]]; then
  echo "missing gateway env: ${gateway_env}" >&2
  exit 1
fi

set -a
source "${gateway_env}"
set +a

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

result="$(
  runuser -u devclaw-svc -- env \
    HOME=/home/devclaw-svc \
    XDG_CONFIG_HOME=/home/devclaw-svc/.config \
    XDG_CACHE_HOME=/home/devclaw-svc/.cache \
    XDG_DATA_HOME=/home/devclaw-svc/.local/share \
    OPENCLAW_STATE_DIR=/home/devclaw-svc/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/devclaw-svc/.openclaw/openclaw.json \
    OPENCLAW_NO_COLOR=1 \
    OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN}" \
    /usr/local/bin/openclaw agent \
      --agent main \
      --session-key agent:main:knowledge-review-issue-8 \
      --message-file "${prompt_file}" \
      --timeout 900 \
      --json
)"

jq -nc \
  --arg startedAt "${started_at}" \
  --arg finishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sessionKey "agent:main:knowledge-review-issue-8" \
  --arg promptFile "${prompt_file}" \
  --argjson result "${result}" \
  '{
    startedAt:$startedAt,
    finishedAt:$finishedAt,
    sessionKey:$sessionKey,
    promptFile:$promptFile,
    result:$result
  }' | tee "${out_file}"
