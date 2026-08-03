#!/usr/bin/env bash
set -euo pipefail

backup_file="${1:-}"
out_file="${2:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/codex-sandbox-apparmor-userns-profile-rollback.json}"
profile_name="openclaw-codex-linux-sandbox"
profile_file="/etc/apparmor.d/${profile_name}"

fail() {
  printf '[rollback-codex-sandbox-apparmor-userns-profile] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v jq >/dev/null 2>&1 || fail "missing jq"
command -v apparmor_parser >/dev/null 2>&1 || fail "missing apparmor_parser"
[[ -n "${backup_file}" && -f "${backup_file}" ]] || fail "missing backup file"

if [[ -s "${backup_file}" ]]; then
  cp -a "${backup_file}" "${profile_file}"
  apparmor_parser -r "${profile_file}"
  action="restored"
else
  apparmor_parser -R "${profile_file}" 2>/dev/null || true
  rm -f "${profile_file}"
  action="removed"
fi

mkdir -p "$(dirname "${out_file}")"
jq -n \
  --arg rolledBackAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg profileName "${profile_name}" \
  --arg profileFile "${profile_file}" \
  --arg backupFile "${backup_file}" \
  --arg action "${action}" \
  '{
    rolledBackAt:$rolledBackAt,
    profile:{name:$profileName, file:$profileFile},
    backupFile:$backupFile,
    action:$action
  }' | tee "${out_file}"
