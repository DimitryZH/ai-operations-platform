#!/usr/bin/env bash
set -euo pipefail

backup_file="${1:-}"
out_file="${2:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/codex-trusted-workspace-sandbox-fix-rollback.json}"
config_file="/home/devclaw-svc/.openclaw/agents/main/agent/codex-home/config.toml"

fail() {
  printf '[rollback-codex-trusted-workspace-sandbox-fix] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v jq >/dev/null 2>&1 || fail "missing jq"
[[ -n "${backup_file}" ]] || fail "usage: $0 <backup-file> [out-file]"
[[ -f "${backup_file}" ]] || fail "backup file does not exist: ${backup_file}"

cp -a "${backup_file}" "${config_file}"
chown devclaw-svc:devclaw-svc "${config_file}"
chmod 0600 "${config_file}"

systemctl restart openclaw-gateway.service
sleep 3
systemctl is-active --quiet openclaw-gateway.service || fail "openclaw-gateway.service failed to restart"

mkdir -p "$(dirname "${out_file}")"
jq -n \
  --arg rolledBackAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg configFile "${config_file}" \
  --arg restoredFrom "${backup_file}" \
  --arg serviceStatus "$(systemctl is-active openclaw-gateway.service)" \
  '{
    rolledBackAt:$rolledBackAt,
    configFile:$configFile,
    restoredFrom:$restoredFrom,
    openclawGatewayService:$serviceStatus
  }' | tee "${out_file}"
