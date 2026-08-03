#!/usr/bin/env bash
set -euo pipefail

subuid_backup="${1:-}"
subgid_backup="${2:-}"
out_file="${3:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/devclaw-userns-subid-fix-rollback.json}"

fail() {
  printf '[rollback-devclaw-userns-subid-fix] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v jq >/dev/null 2>&1 || fail "missing jq"
[[ -n "${subuid_backup}" && -f "${subuid_backup}" ]] || fail "missing subuid backup"
[[ -n "${subgid_backup}" && -f "${subgid_backup}" ]] || fail "missing subgid backup"

cp -a "${subuid_backup}" /etc/subuid
cp -a "${subgid_backup}" /etc/subgid
chmod 0644 /etc/subuid /etc/subgid

mkdir -p "$(dirname "${out_file}")"
jq -n \
  --arg rolledBackAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg subuidRestoredFrom "${subuid_backup}" \
  --arg subgidRestoredFrom "${subgid_backup}" \
  '{
    rolledBackAt:$rolledBackAt,
    restored:{subuid:$subuidRestoredFrom, subgid:$subgidRestoredFrom}
  }' | tee "${out_file}"
