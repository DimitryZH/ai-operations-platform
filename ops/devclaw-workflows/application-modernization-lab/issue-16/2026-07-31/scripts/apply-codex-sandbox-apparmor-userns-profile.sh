#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/codex-sandbox-apparmor-userns-profile.json}"
profile_name="openclaw-codex-linux-sandbox"
profile_file="/etc/apparmor.d/${profile_name}"
backup_dir="/var/lib/devclaw/recovery/issue-16-codex-apparmor-userns"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="${backup_dir}/${profile_name}.${timestamp}.bak"
codex_home="/home/devclaw-svc/.openclaw/agents/main/agent/codex-home"
symlink_path="${codex_home}/tmp/arg0/codex-arg0yl2y5v/codex-linux-sandbox"
target_path="$(readlink -f "${symlink_path}")"

fail() {
  printf '[apply-codex-sandbox-apparmor-userns-profile] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v jq >/dev/null 2>&1 || fail "missing jq"
command -v apparmor_parser >/dev/null 2>&1 || fail "missing apparmor_parser"
[[ -x "${target_path}" ]] || fail "missing executable target: ${target_path}"

mkdir -p "${backup_dir}" "$(dirname "${out_file}")"
if [[ -f "${profile_file}" ]]; then
  cp -a "${profile_file}" "${backup_file}"
else
  : > "${backup_file}"
fi

cat > "${profile_file}" <<EOF_PROFILE
# Managed by DevClaw operator recovery for application-modernization-lab issue #16.
# Purpose: allow the OpenClaw-bundled Codex Linux sandbox helper to create
# unprivileged user namespaces on Ubuntu systems with
# kernel.apparmor_restrict_unprivileged_userns=1.
# This does not disable AppArmor globally and does not alter DevClaw workflow
# guardrails, labels, branches, PRs, skills, or autonomous behavior.
abi <abi/4.0>,
include <tunables/global>

profile ${profile_name} ${target_path} flags=(unconfined) {
  userns,
}
EOF_PROFILE

chmod 0644 "${profile_file}"
apparmor_parser -r "${profile_file}"

profile_loaded="false"
if aa-status 2>/dev/null | grep -q "${profile_name}"; then
  profile_loaded="true"
fi

aa_exec_userns_result="$(
  aa-exec -p "${profile_name}" -- unshare -Urn /bin/sh -c 'ip link set lo up && ip addr show lo >/dev/null' 2>&1 || true
)"
aa_exec_userns_ok="false"
if [[ -z "${aa_exec_userns_result}" ]]; then
  aa_exec_userns_ok="true"
fi

jq -n \
  --arg appliedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg profileName "${profile_name}" \
  --arg profileFile "${profile_file}" \
  --arg backupFile "${backup_file}" \
  --arg symlinkPath "${symlink_path}" \
  --arg targetPath "${target_path}" \
  --argjson profileLoaded "${profile_loaded}" \
  --argjson aaExecUsernsOk "${aa_exec_userns_ok}" \
  --arg aaExecUsernsOutput "${aa_exec_userns_result}" \
  '{
    appliedAt:$appliedAt,
    change:"Added narrow AppArmor userns allow profile for OpenClaw-bundled Codex Linux sandbox helper",
    reason:"Ubuntu AppArmor restricts unprivileged user namespace uid_map writes unless the executable profile grants userns",
    profile:{name:$profileName, file:$profileFile, loaded:$profileLoaded},
    executable:{symlink:$symlinkPath, target:$targetPath},
    backupFile:$backupFile,
    validation:{aaExecUsernsOk:$aaExecUsernsOk, aaExecUsernsOutput:$aaExecUsernsOutput}
  }' | tee "${out_file}"
