#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/agent-param-cwd-codex-smoke-dispatch-result.json}"
status_file="${2:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/agent-param-cwd-codex-smoke-status.json}"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
repo="/workspace/repos/application-modernization-lab"
session_suffix="$(date -u +%Y%m%dt%H%M%Sz)"
session_key="agent:main:subagent:codex-agent-param-cwd-smoke-issue-16-${session_suffix}"
model="openai/gpt-5.5"

fail() {
  printf '[dispatch-agent-param-cwd-codex-smoke-test] ERROR: %s\n' "$*" >&2
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
[[ -d "${repo}/.git" ]] || fail "missing repository checkout: ${repo}"
[[ -f "${gateway_env}" ]] || fail "missing gateway env: ${gateway_env}"

set -a
source "${gateway_env}"
set +a

systemctl is-active --quiet openclaw-gateway.service || fail "openclaw-gateway.service is not active"

run_as_devclaw /usr/local/bin/openclaw gateway call sessions.patch \
  --params "$(jq -nc --arg key "${session_key}" --arg model "${model}" --arg label "Codex agent-param cwd smoke issue 16 ${session_suffix}" '{key:$key, model:$model, label:$label}')" \
  --timeout 30000 \
  --json >/dev/null

task_message='Operator smoke test only. Do not modify files, repositories, issues, labels, branches, PRs, skills, workflow config, or cloud resources. Use the bash tool once with cwd /workspace/repos/application-modernization-lab to execute exactly: pwd && git status --short --branch. Then answer with the observed output and stop.'

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "codex-agent-param-cwd-smoke-issue-16-${session_suffix}" \
  --arg cwd "${repo}" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent", cwd:$cwd}')"

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
  --arg repo "${repo}" \
  --arg agentResult "${agent_result}" \
  '{
    dispatchedAt:$dispatchedAt,
    sessionKey:$sessionKey,
    repo:$repo,
    dispatchAccepted:($agentResult | length > 0),
    agentResult:$agentResult
  }' | tee "${out_file}"

sleep 15
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
session="$(
  if [[ -f "${sessions_file}" ]]; then
    jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
)"
session_id="$(jq -r '.id // empty' <<<"${session}")"
tail_text="$(
  if [[ -n "${session_id}" && -f "${state_dir}/agents/main/sessions/${session_id}.jsonl" ]]; then
    tail -n 80 "${state_dir}/agents/main/sessions/${session_id}.jsonl"
  else
    printf ''
  fi
)"
jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sessionKey "${session_key}" \
  --argjson session "${session}" \
  --arg tail "${tail_text}" \
  '{
    checkedAt:$checkedAt,
    sessionKey:$sessionKey,
    session:$session,
    tail:$tail
  }' | tee "${status_file}"
