#!/usr/bin/env bash
set -euo pipefail

session_key="${1:?session key is required}"
out_file="${2:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics/results/minimal-smoke-session-inspection.json}"
state_dir="/home/devclaw-svc/.openclaw"
sessions_file="${state_dir}/agents/main/sessions/sessions.json"

fail() {
  printf '[inspect-minimal-smoke-session-readonly] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on DevClaw VM"
command -v jq >/dev/null 2>&1 || fail "missing jq"
[[ -f "${sessions_file}" ]] || fail "missing sessions file: ${sessions_file}"

session="$(jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}")"
session_id="$(jq -r '.sessionId // .id // empty' <<<"${session}")"
session_file=""
tail_text=""
if [[ -n "${session_id}" && -f "${state_dir}/agents/main/sessions/${session_id}.jsonl" ]]; then
  session_file="${state_dir}/agents/main/sessions/${session_id}.jsonl"
  tail_text="$(tail -n 200 "${session_file}")"
fi

mkdir -p "$(dirname "${out_file}")"
jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sessionKey "${session_key}" \
  --arg sessionFile "${session_file}" \
  --argjson session "${session}" \
  --arg transcriptTail "${tail_text}" \
  '{
    checkedAt:$checkedAt,
    sessionKey:$sessionKey,
    session:$session,
    sessionFile:$sessionFile,
    transcriptTail:$transcriptTail
  }' | tee "${out_file}"
