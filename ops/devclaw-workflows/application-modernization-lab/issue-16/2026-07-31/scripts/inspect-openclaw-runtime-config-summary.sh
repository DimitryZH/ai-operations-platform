#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/openclaw-runtime-config-summary.json}"
config_file="/home/devclaw-svc/.openclaw/openclaw.json"

fail() {
  printf '[inspect-openclaw-runtime-config-summary] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v jq >/dev/null 2>&1 || fail "missing jq"
[[ -f "${config_file}" ]] || fail "missing OpenClaw config: ${config_file}"

mkdir -p "$(dirname "${out_file}")"
jq \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    checkedAt:$checkedAt,
    codex:{
      appServer:.plugins.entries.codex.config.appServer,
      model:.plugins.entries.codex.config.model,
      approvalPolicy:.plugins.entries.codex.config.approvalPolicy,
      policyMode:.plugins.entries.codex.config.policyMode,
      approvalsReviewer:.plugins.entries.codex.config.approvalsReviewer
    },
    devclaw:{
      workHeartbeat:.plugins.entries.devclaw.config.work_heartbeat,
      projectExecution:.plugins.entries.devclaw.config.projectExecution
    },
    tools:{exec:.tools.exec},
    skills:{workshop:.skills.workshop}
  }' "${config_file}" | tee "${out_file}"
