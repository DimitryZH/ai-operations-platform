#!/usr/bin/env bash
set -euo pipefail

root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics"
out_file="${1:-${root}/results/post-reboot-minimal-smoke-dispatch.json}"
status_file="${2:-${root}/results/post-reboot-minimal-smoke-status.json}"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
session_suffix="$(date -u +%Y%m%dt%H%M%Sz)"
session_key="agent:main:subagent:issue-16-post-reboot-runtime-smoke-${session_suffix}"
model="openai/gpt-5.5"

fail() {
  printf '[dispatch-post-reboot-minimal-subagent-smoke-readonly] ERROR: %s\n' "$*" >&2
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

[[ "${EUID}" -eq 0 ]] || fail "must run as root on DevClaw VM"
command -v jq >/dev/null 2>&1 || fail "missing jq"
[[ -f "${gateway_env}" ]] || fail "missing gateway env"

set -a
# shellcheck disable=SC1090
source "${gateway_env}"
set +a

mkdir -p "$(dirname "${out_file}")" "$(dirname "${status_file}")"
systemctl is-active --quiet openclaw-gateway.service || fail "openclaw-gateway.service is not active"

patch_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg model "${model}" \
  --arg label "Issue 16 post reboot runtime smoke ${session_suffix}" \
  '{key:$key, model:$model, label:$label}')"

patch_result=""
patch_rc=0
patch_result="$(run_as_devclaw /usr/local/bin/openclaw gateway call sessions.patch --params "${patch_params}" --timeout 30000 --json 2>&1)" || patch_rc="$?"

task_message='Runtime diagnostic smoke only. Do not inspect or modify repositories, issues, labels, branches, PRs, skills, workflow config, services, VM settings, or cloud resources. Use the bash tool exactly once to execute this read-only command: true && pwd && id. Then answer with SMOKE_OK and the observed pwd/id output if the command executed successfully, or SMOKE_FAILED plus the exact error if it failed.'

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "issue-16-post-reboot-runtime-smoke-${session_suffix}" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent"}')"

agent_result=""
agent_rc=0
if [[ "${patch_rc}" -eq 0 ]]; then
  agent_result="$(run_as_devclaw /usr/local/bin/openclaw gateway call agent --params "${agent_params}" --timeout 120000 --json 2>&1)" || agent_rc="$?"
else
  agent_rc=99
  agent_result='{"skipped":"sessions.patch failed"}'
fi

jq -n \
  --arg dispatchedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sessionKey "${session_key}" \
  --arg patchResult "${patch_result}" \
  --argjson patchRc "${patch_rc}" \
  --arg agentResult "${agent_result}" \
  --argjson agentRc "${agent_rc}" \
  '{
    dispatchedAt:$dispatchedAt,
    sessionKey:$sessionKey,
    patch:{rc:$patchRc, result:$patchResult},
    agent:{rc:$agentRc, result:$agentResult},
    dispatchAccepted:($agentRc == 0 and ($agentResult | length > 0))
  }' | tee "${out_file}"

sleep 25
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
session="$(
  if [[ -f "${sessions_file}" ]]; then
    jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
)"
session_id="$(jq -r '.sessionId // .id // empty' <<<"${session}")"
tail_text="$(
  if [[ -n "${session_id}" && -f "${state_dir}/agents/main/sessions/${session_id}.jsonl" ]]; then
    tail -n 220 "${state_dir}/agents/main/sessions/${session_id}.jsonl"
  else
    printf ''
  fi
)"

jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sessionKey "${session_key}" \
  --arg sessionId "${session_id}" \
  --argjson session "${session}" \
  --arg transcriptTail "${tail_text}" \
  '{
    checkedAt:$checkedAt,
    sessionKey:$sessionKey,
    sessionId:$sessionId,
    session:$session,
    transcriptTail:$transcriptTail
  }' | tee "${status_file}"
