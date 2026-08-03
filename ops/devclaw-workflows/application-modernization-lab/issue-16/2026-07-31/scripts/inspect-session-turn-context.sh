#!/usr/bin/env bash
set -euo pipefail

session_id="${1:?session id is required}"
out_file="${2:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/session-turn-context.json}"
session_file="/home/devclaw-svc/.openclaw/agents/main/sessions/${session_id}.jsonl"

fail() {
  printf '[inspect-session-turn-context] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v jq >/dev/null 2>&1 || fail "missing jq"
[[ -f "${session_file}" ]] || fail "missing session file: ${session_file}"

mkdir -p "$(dirname "${out_file}")"
jq -c '
  select(.type == "turn_context" or .type == "event_msg") |
  if .type == "event_msg" and .payload.type == "thread_settings_applied" then
    {
      timestamp,
      type:.payload.type,
      cwd:.payload.thread_settings.cwd,
      approval_policy:.payload.thread_settings.approval_policy,
      sandbox_policy:.payload.thread_settings.sandbox_policy,
      permission_profile:.payload.thread_settings.permission_profile,
      model:.payload.thread_settings.model
    }
  elif .type == "turn_context" then
    {
      timestamp,
      type,
      cwd:.payload.cwd,
      workspace_roots:.payload.workspace_roots,
      approval_policy:.payload.approval_policy,
      sandbox_policy:.payload.sandbox_policy,
      permission_profile:.payload.permission_profile,
      model:.payload.model
    }
  else empty end
' "${session_file}" | jq -s \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sessionId "${session_id}" \
  '{checkedAt:$checkedAt, sessionId:$sessionId, contexts:.}' | tee "${out_file}"
