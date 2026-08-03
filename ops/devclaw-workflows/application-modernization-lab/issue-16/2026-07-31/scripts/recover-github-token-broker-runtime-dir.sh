#!/usr/bin/env bash
set -euo pipefail

workflow_root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31"
out_file="${1:-${workflow_root}/results/github-token-broker-runtime-dir-recovery.json}"

fail() {
  printf '[recover-github-token-broker-runtime-dir] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
id devclaw-token >/dev/null 2>&1 || fail "missing devclaw-token user"
getent group devclaw-broker >/dev/null 2>&1 || fail "missing devclaw-broker group"

mkdir -p /run/devclaw
chown devclaw-token:devclaw-broker /run/devclaw
chmod 0770 /run/devclaw
systemctl restart devclaw-github-token-broker.service
sleep 2

service_state="$(systemctl is-active devclaw-github-token-broker.service || true)"
socket_state="$(
  if [[ -S /run/devclaw/github-token-broker.sock ]]; then
    stat -c '%U:%G %a %n' /run/devclaw/github-token-broker.sock
  else
    printf 'missing'
  fi
)"

mkdir -p "$(dirname "${out_file}")"
jq -n \
  --arg recoveredAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg serviceState "${service_state}" \
  --arg socketState "${socket_state}" \
  '{
    recoveredAt:$recoveredAt,
    action:"created ephemeral /run/devclaw runtime directory and restarted devclaw-github-token-broker.service",
    configChanged:false,
    serviceState:$serviceState,
    socketState:$socketState
  }' | tee "${out_file}"

[[ "${service_state}" == "active" ]] || fail "token broker service is not active: ${service_state}"
[[ "${socket_state}" != "missing" ]] || fail "token broker socket was not created"
