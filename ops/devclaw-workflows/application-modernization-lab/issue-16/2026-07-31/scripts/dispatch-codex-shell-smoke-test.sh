#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/codex-shell-smoke-dispatch-result.json}"
status_file="${2:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/codex-shell-smoke-status.json}"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
session_suffix="$(date -u +%Y%m%dt%H%M%Sz)"
session_key="agent:main:subagent:codex-shell-smoke-issue-16-${session_suffix}"
model="openai/gpt-5.5"

fail() {
  printf '[dispatch-codex-shell-smoke-test] ERROR: %s\n' "$*" >&2
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
[[ -f "${gateway_env}" ]] || fail "missing gateway env: ${gateway_env}"

set -a
source "${gateway_env}"
set +a

systemctl is-active --quiet openclaw-gateway.service || fail "openclaw-gateway.service is not active"

run_as_devclaw /usr/local/bin/openclaw gateway call sessions.patch \
  --params "$(jq -nc --arg key "${session_key}" --arg model "${model}" --arg label "Codex shell smoke issue 16 ${session_suffix}" '{key:$key, model:$model, label:$label}')" \
  --timeout 30000 \
  --json >/dev/null

task_message='Run only a shell smoke test for the DevClaw/Codex runtime. Do not inspect or modify repositories, issues, labels, branches, PRs, cloud resources, skills, or workflow config. Use the bash tool to execute exactly: pwd && printf smoke-ok && printf "\n" && sed -n "1,5p" /home/devclaw-svc/.openclaw/agents/main/agent/codex-home/config.toml. Then call work_finish with role "operator", result "done" if the shell command succeeds, otherwise result "blocked" with the exact failure.'

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "codex-shell-smoke-issue-16-${session_suffix}" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent"}')"

agent_result="$(
  run_as_devclaw /usr/local/bin/openclaw gateway call agent \
    --params "${agent_params}" \
    --timeout 120000 \
    --json
)"

mkdir -p "$(dirname "${out_file}")"
jq -n \
  --arg dispatchedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sessionKey "${session_key}" \
  --arg agentResult "${agent_result}" \
  '{
    dispatchedAt:$dispatchedAt,
    sessionKey:$sessionKey,
    dispatchAccepted:($agentResult | length > 0),
    agentResult:$agentResult
  }' | tee "${out_file}"

sleep 10
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
session="$(
  if [[ -f "${sessions_file}" ]]; then
    jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
)"
jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sessionKey "${session_key}" \
  --argjson session "${session}" \
  '{
    checkedAt:$checkedAt,
    sessionKey:$sessionKey,
    session:$session
  }' | tee "${status_file}"
