#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/codex-trusted-workspace-sandbox-fix.json}"
codex_home="/home/devclaw-svc/.openclaw/agents/main/agent/codex-home"
config_file="${codex_home}/config.toml"
backup_dir="/home/devclaw-svc/.openclaw/backups/issue-16-codex-sandbox-fix"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="${backup_dir}/config.toml.${timestamp}.bak"

fail() {
  printf '[apply-codex-trusted-workspace-sandbox-fix] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v jq >/dev/null 2>&1 || fail "missing jq"
[[ -d "${codex_home}" ]] || fail "missing codex home: ${codex_home}"
[[ -f "${config_file}" ]] || fail "missing Codex config: ${config_file}"

mkdir -p "${backup_dir}" "$(dirname "${out_file}")"
cp -a "${config_file}" "${backup_file}"

cat > "${config_file}.tmp" <<'EOF_CONFIG'
# Managed by DevClaw operator recovery for application-modernization-lab issue #16.
# Reason: Codex Linux sandbox helper fails on this VM with:
#   bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
# This keeps the workspace trusted and disables the broken local shell sandbox.
# DevClaw workflow guardrails, human review, sequential execution, and disabled
# autonomous project execution remain enforced by OpenClaw/DevClaw config.
sandbox_mode = "danger-full-access"

[projects."/home/devclaw-svc/.openclaw/workspace"]
trust_level = "trusted"
EOF_CONFIG

chown devclaw-svc:devclaw-svc "${config_file}.tmp"
chmod 0600 "${config_file}.tmp"
mv "${config_file}.tmp" "${config_file}"
chown devclaw-svc:devclaw-svc "${config_file}"
chmod 0600 "${config_file}"

systemctl restart openclaw-gateway.service
sleep 3
systemctl is-active --quiet openclaw-gateway.service || fail "openclaw-gateway.service failed to restart"

jq -n \
  --arg appliedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg configFile "${config_file}" \
  --arg backupFile "${backup_file}" \
  --arg sandboxMode "danger-full-access" \
  --arg serviceStatus "$(systemctl is-active openclaw-gateway.service)" \
  '{
    appliedAt:$appliedAt,
    change:"Codex trusted workspace shell sandbox workaround",
    reason:"Codex Linux sandbox helper fails with bwrap loopback RTM_NEWADDR permission error on this VM",
    configFile:$configFile,
    backupFile:$backupFile,
    sandboxMode:$sandboxMode,
    openclawGatewayService:$serviceStatus,
    preservedGuardrails:[
      "DevClaw workflow sequential execution remains configured separately",
      "DevClaw autonomous Skill Workshop behavior is not modified",
      "No issue labels, workers, branches, PRs, or application files are changed by this script"
    ]
  }' | tee "${out_file}"
