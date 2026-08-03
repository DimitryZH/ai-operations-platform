#!/usr/bin/env bash
set -euo pipefail

project="application-modernization-lab"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
projects_file="${state_dir}/workspace/devclaw/projects.json"
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
workflow_root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31"
out_file="${1:-${workflow_root}/results/developer-runtime-tail-readonly-$(date -u +%Y%m%dT%H%M%SZ).json}"

fail() {
  printf '[inspect-issue-16-developer-runtime-tail-readonly] ERROR: %s\n' "$*" >&2
  exit 1
}

run_as_devclaw() {
  runuser -u devclaw-svc -- env \
    HOME=/home/devclaw-svc \
    XDG_CONFIG_HOME=/home/devclaw-svc/.config \
    XDG_CACHE_HOME=/home/devclaw-svc/.cache \
    XDG_DATA_HOME=/home/devclaw-svc/.local/share \
    OPENCLAW_STATE_DIR="${state_dir}" \
    OPENCLAW_CONFIG_PATH="${state_dir}/openclaw.json" \
    OPENCLAW_NO_COLOR=1 \
    OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}" \
    "$@"
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v jq >/dev/null 2>&1 || fail "missing jq"
[[ -f "${gateway_env}" ]] || fail "missing gateway env"
[[ -f "${projects_file}" ]] || fail "missing projects.json"

set -a
# shellcheck disable=SC1090
source "${gateway_env}"
set +a

gateway_status="$(run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000)"
worker="$(
  jq -c --arg project "${project}" \
    '.projects[] | select(.name==$project).workers.developer.levels.senior[0]' \
    "${projects_file}"
)"
session_key="$(jq -r '.sessionKey // empty' <<<"${worker}")"
session="$(
  if [[ -n "${session_key}" && -f "${sessions_file}" ]]; then
    jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
)"
session_id="$(jq -r '.sessionId // .id // empty' <<<"${session}")"
transcript_tail="$(
  if [[ -n "${session_id}" && -f "${state_dir}/agents/main/sessions/${session_id}.jsonl" ]]; then
    tail -n 120 "${state_dir}/agents/main/sessions/${session_id}.jsonl"
  else
    printf ''
  fi
)"

mkdir -p "$(dirname "${out_file}")"
jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson gatewayStatus "${gateway_status}" \
  --argjson worker "${worker}" \
  --argjson session "${session}" \
  --arg sessionId "${session_id}" \
  --arg transcriptTail "${transcript_tail}" \
  '{
    checkedAt:$checkedAt,
    gateway:{tasks:$gatewayStatus.tasks, taskAudit:$gatewayStatus.taskAudit},
    developerWorker:$worker,
    developerSession:$session,
    sessionId:$sessionId,
    transcriptTail:$transcriptTail
  }' | tee "${out_file}"
