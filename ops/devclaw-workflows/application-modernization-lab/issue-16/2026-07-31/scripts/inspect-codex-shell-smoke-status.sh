#!/usr/bin/env bash
set -euo pipefail

session_key="${1:?session key is required}"
session_id="${2:?session id is required}"
out_file="${3:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/codex-shell-smoke-final-status.json}"
sessions_file="/home/devclaw-svc/.openclaw/agents/main/sessions/sessions.json"
session_file="/home/devclaw-svc/.openclaw/agents/main/sessions/${session_id}.jsonl"

mkdir -p "$(dirname "${out_file}")"
session="$(
  if [[ -f "${sessions_file}" ]]; then
    jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
)"
tail_text="$(
  if [[ -f "${session_file}" ]]; then
    tail -n 120 "${session_file}"
  else
    printf 'missing session file: %s' "${session_file}"
  fi
)"

jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sessionKey "${session_key}" \
  --arg sessionId "${session_id}" \
  --argjson session "${session}" \
  --arg tail "${tail_text}" \
  '{
    checkedAt:$checkedAt,
    sessionKey:$sessionKey,
    sessionId:$sessionId,
    session:$session,
    tail:$tail
  }' | tee "${out_file}"
