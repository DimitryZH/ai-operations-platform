#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/devclaw-userns-subid-fix.json}"
backup_dir="/var/lib/devclaw/recovery/issue-16-userns-subid-fix"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
subuid_backup="${backup_dir}/subuid.${timestamp}.bak"
subgid_backup="${backup_dir}/subgid.${timestamp}.bak"
user_name="devclaw-svc"
subid_start="200000"
subid_count="65536"

fail() {
  printf '[apply-devclaw-userns-subid-fix] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v jq >/dev/null 2>&1 || fail "missing jq"
id "${user_name}" >/dev/null 2>&1 || fail "missing user ${user_name}"

mkdir -p "${backup_dir}" "$(dirname "${out_file}")"
cp -a /etc/subuid "${subuid_backup}" 2>/dev/null || touch "${subuid_backup}"
cp -a /etc/subgid "${subgid_backup}" 2>/dev/null || touch "${subgid_backup}"

if ! command -v newuidmap >/dev/null 2>&1 || ! command -v newgidmap >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y uidmap
fi

touch /etc/subuid /etc/subgid
if ! grep -q "^${user_name}:" /etc/subuid; then
  printf '%s:%s:%s\n' "${user_name}" "${subid_start}" "${subid_count}" >> /etc/subuid
fi
if ! grep -q "^${user_name}:" /etc/subgid; then
  printf '%s:%s:%s\n' "${user_name}" "${subid_start}" "${subid_count}" >> /etc/subgid
fi

chmod 0644 /etc/subuid /etc/subgid

unshare_user_result="$(runuser -u "${user_name}" -- unshare -Ur /bin/true 2>&1 || true)"
unshare_net_result="$(runuser -u "${user_name}" -- unshare -Urn /bin/sh -c 'ip link set lo up && ip addr show lo >/dev/null' 2>&1 || true)"
unshare_user_ok="false"
unshare_net_ok="false"
if [[ -z "${unshare_user_result}" ]]; then
  unshare_user_ok="true"
fi
if [[ -z "${unshare_net_result}" ]]; then
  unshare_net_ok="true"
fi

jq -n \
  --arg appliedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg user "${user_name}" \
  --arg subuidBackup "${subuid_backup}" \
  --arg subgidBackup "${subgid_backup}" \
  --arg subuidEntry "$(grep "^${user_name}:" /etc/subuid | head -n1)" \
  --arg subgidEntry "$(grep "^${user_name}:" /etc/subgid | head -n1)" \
  --arg newuidmap "$(command -v newuidmap || true)" \
  --arg newgidmap "$(command -v newgidmap || true)" \
  --arg unshareUserResult "${unshare_user_result}" \
  --arg unshareNetResult "${unshare_net_result}" \
  --argjson unshareUserOk "${unshare_user_ok}" \
  --argjson unshareNetOk "${unshare_net_ok}" \
  '{
    appliedAt:$appliedAt,
    change:"Configured subordinate UID/GID mappings for DevClaw service user",
    reason:"Codex Linux sandbox requires user namespace UID/GID mapping; devclaw-svc unshare failed at uid_map",
    user:$user,
    backups:{subuid:$subuidBackup, subgid:$subgidBackup},
    entries:{subuid:$subuidEntry, subgid:$subgidEntry},
    binaries:{newuidmap:$newuidmap, newgidmap:$newgidmap},
    validation:{
      unshareUserOk:$unshareUserOk,
      unshareNetLoopbackOk:$unshareNetOk,
      unshareUserOutput:$unshareUserResult,
      unshareNetOutput:$unshareNetResult
    }
  }' | tee "${out_file}"
