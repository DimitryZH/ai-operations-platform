#!/usr/bin/env bash
set -euo pipefail

state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
out_file="${1:-$(dirname "$0")/../results/devclaw-exec-guardrails-inspection.json}"

fail() {
  printf '[inspect-devclaw-exec-guardrails] ERROR: %s\n' "$*" >&2
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

config_get_or_null() {
  local key="$1"
  run_as_devclaw /usr/local/bin/openclaw config get "${key}" 2>/dev/null |
    sed -E 's/^\s+|\s+$//g; s/^"//; s/"$//' |
    tail -n1 || true
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v jq >/dev/null 2>&1 || fail "missing jq"
[[ -f "${gateway_env}" ]] || fail "missing gateway env: ${gateway_env}"

set -a
source "${gateway_env}"
set +a

openclaw_json="$(
  if [[ -f "${state_dir}/openclaw.json" ]]; then
    jq '{
      tools: .tools,
      gateway: .gateway,
      plugins: {
        codex: .plugins.entries.codex,
        devclaw: .plugins.entries.devclaw
      },
      skills: .skills
    }' "${state_dir}/openclaw.json"
  else
    printf 'null'
  fi
)"

approval_files="$(
  find "${state_dir}" /var/lib/devclaw /opt/devclaw -maxdepth 5 -type f \
    \( -iname '*approval*' -o -iname '*policy*' -o -iname '*codex*' \) \
    -printf '%p\n' 2>/dev/null | sort
)"

mkdir -p "$(dirname "${out_file}")"
jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg toolsExecMode "$(config_get_or_null tools.exec.mode)" \
  --arg strictInlineEval "$(config_get_or_null tools.exec.strictInlineEval)" \
  --arg codexEnabled "$(config_get_or_null plugins.entries.codex.enabled)" \
  --arg heartbeat "$(config_get_or_null plugins.entries.devclaw.config.work_heartbeat.enabled)" \
  --arg projectExecution "$(config_get_or_null plugins.entries.devclaw.config.projectExecution)" \
  --arg skillAutonomous "$(config_get_or_null skills.workshop.autonomous.enabled)" \
  --arg skillApprovalPolicy "$(config_get_or_null skills.workshop.approvalPolicy)" \
  --argjson openclawConfig "${openclaw_json}" \
  --arg approvalFiles "${approval_files}" \
  '{
    checkedAt:$checkedAt,
    configGet:{
      toolsExecMode:$toolsExecMode,
      strictInlineEval:$strictInlineEval,
      codexEnabled:$codexEnabled,
      heartbeat:$heartbeat,
      projectExecution:$projectExecution,
      skillAutonomous:$skillAutonomous,
      skillApprovalPolicy:$skillApprovalPolicy
    },
    openclawConfig:$openclawConfig,
    approvalFiles:($approvalFiles | split("\n") | map(select(length > 0)))
  }' | tee "${out_file}"
