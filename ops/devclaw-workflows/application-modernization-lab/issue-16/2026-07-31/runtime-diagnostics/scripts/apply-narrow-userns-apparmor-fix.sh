#!/usr/bin/env bash
set -euo pipefail

root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="${1:-${root}/results/narrow-userns-apparmor-fix-${ts}}"
backup_dir="${root}/backups/narrow-userns-apparmor-fix-${ts}"
profile_file="/etc/apparmor.d/openclaw-codex-bwrap"
profile_local_file="/etc/apparmor.d/local/openclaw-codex-bwrap"
user_name="devclaw-svc"
subid_count=65536

fail() {
  printf '[apply-narrow-userns-apparmor-fix] ERROR: %s\n' "$*" >&2
  exit 1
}

choose_subid_start() {
  local file="$1"
  awk -F: -v min_start=100000 -v count="${subid_count}" '
    BEGIN { start=min_start }
    NF >= 3 {
      range_start=$2 + 0
      range_count=$3 + 0
      range_end=range_start + range_count
      if (range_end > start) {
        start=range_end
      }
    }
    END {
      rem=start % count
      if (rem != 0) {
        start += count - rem
      }
      print start
    }
  ' "${file}"
}

ensure_subid() {
  local file="$1"
  local label="$2"
  if grep -qE "^${user_name}:" "${file}"; then
    printf '%s already present: %s\n' "${label}" "$(grep -E "^${user_name}:" "${file}")"
    return 0
  fi
  local start
  start="$(choose_subid_start "${file}")"
  printf '%s:%s:%s\n' "${user_name}" "${start}" "${subid_count}" >> "${file}"
  printf '%s added: %s:%s:%s\n' "${label}" "${user_name}" "${start}" "${subid_count}"
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on DevClaw VM"
command -v jq >/dev/null 2>&1 || fail "missing jq"
id "${user_name}" >/dev/null 2>&1 || fail "missing ${user_name} user"

mkdir -p "${out_dir}" "${backup_dir}" /etc/apparmor.d/local

cp -a /etc/subuid "${backup_dir}/subuid.bak"
cp -a /etc/subgid "${backup_dir}/subgid.bak"
if [[ -f "${profile_file}" ]]; then
  cp -a "${profile_file}" "${backup_dir}/openclaw-codex-bwrap.bak"
fi
if [[ -f "${profile_local_file}" ]]; then
  cp -a "${profile_local_file}" "${backup_dir}/local-openclaw-codex-bwrap.bak"
fi
aa-status > "${backup_dir}/aa-status.before.txt" 2>&1 || true
sysctl kernel.apparmor_restrict_unprivileged_userns kernel.unprivileged_userns_clone \
  > "${backup_dir}/userns-sysctl.before.txt" 2>&1 || true

uidmap_installed_before=true
if ! command -v newuidmap >/dev/null 2>&1 || ! command -v newgidmap >/dev/null 2>&1; then
  uidmap_installed_before=false
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y uidmap
fi

subuid_change="$(ensure_subid /etc/subuid subuid)"
subgid_change="$(ensure_subid /etc/subgid subgid)"

mapfile -t bwrap_paths < <(find /home/devclaw-svc/.openclaw/npm/projects -path '*/codex-resources/bwrap' -type f 2>/dev/null | sort)
[[ "${#bwrap_paths[@]}" -gt 0 ]] || fail "no OpenClaw-bundled Codex bwrap executable found"

{
  printf '# Managed by issue #16 runtime diagnostic recovery on %s.\n' "${ts}"
  printf '# Scope: only OpenClaw-bundled Codex Linux sandbox bwrap executables.\n'
  printf 'abi <abi/4.0>,\n'
  printf 'include <tunables/global>\n\n'
  for i in "${!bwrap_paths[@]}"; do
    profile_name="openclaw-codex-bwrap"
    if [[ "${i}" -ne 0 ]]; then
      profile_name="openclaw-codex-bwrap-${i}"
    fi
    printf 'profile %s %s flags=(unconfined) {\n' "${profile_name}" "${bwrap_paths[$i]}"
    printf '  userns,\n'
    printf '  include if exists <local/openclaw-codex-bwrap>\n'
    printf '}\n\n'
  done
} > "${profile_file}"

if [[ ! -f "${profile_local_file}" ]]; then
  {
    printf '# Local overrides for openclaw-codex-bwrap. Intentionally empty.\n'
  } > "${profile_local_file}"
fi

apparmor_parser -T -W "${profile_file}" > "${out_dir}/apparmor-parser-test.log" 2>&1
apparmor_parser -r "${profile_file}" > "${out_dir}/apparmor-parser-reload.log" 2>&1
aa-status > "${out_dir}/aa-status.after.txt" 2>&1 || true
sysctl kernel.apparmor_restrict_unprivileged_userns kernel.unprivileged_userns_clone \
  > "${out_dir}/userns-sysctl.after.txt" 2>&1 || true

cat > "${backup_dir}/rollback-narrow-userns-apparmor-fix.sh" <<'ROLLBACK'
#!/usr/bin/env bash
set -euo pipefail
backup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -a "${backup_dir}/subuid.bak" /etc/subuid
cp -a "${backup_dir}/subgid.bak" /etc/subgid
if [[ -f "${backup_dir}/openclaw-codex-bwrap.bak" ]]; then
  cp -a "${backup_dir}/openclaw-codex-bwrap.bak" /etc/apparmor.d/openclaw-codex-bwrap
  apparmor_parser -r /etc/apparmor.d/openclaw-codex-bwrap
else
  apparmor_parser -R /etc/apparmor.d/openclaw-codex-bwrap 2>/dev/null || true
  rm -f /etc/apparmor.d/openclaw-codex-bwrap
fi
if [[ -f "${backup_dir}/local-openclaw-codex-bwrap.bak" ]]; then
  cp -a "${backup_dir}/local-openclaw-codex-bwrap.bak" /etc/apparmor.d/local/openclaw-codex-bwrap
else
  rm -f /etc/apparmor.d/local/openclaw-codex-bwrap
fi
ROLLBACK
chmod 0755 "${backup_dir}/rollback-narrow-userns-apparmor-fix.sh"

jq -n \
  --arg appliedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg outDir "${out_dir}" \
  --arg backupDir "${backup_dir}" \
  --arg profileFile "${profile_file}" \
  --argjson uidmapInstalledBefore "${uidmap_installed_before}" \
  --arg subuidChange "${subuid_change}" \
  --arg subgidChange "${subgid_change}" \
  --argjson bwrapPaths "$(printf '%s\n' "${bwrap_paths[@]}" | jq -R . | jq -s .)" \
  '{
    appliedAt:$appliedAt,
    outDir:$outDir,
    backupDir:$backupDir,
    rollbackScript:($backupDir + "/rollback-narrow-userns-apparmor-fix.sh"),
    profileFile:$profileFile,
    uidmapInstalledBefore:$uidmapInstalledBefore,
    subuidChange:$subuidChange,
    subgidChange:$subgidChange,
    bwrapPaths:$bwrapPaths,
    globalAppArmorChanged:false,
    sysctlChanged:false
  }' | tee "${out_dir}/apply-summary.json"

printf '%s\n' "${out_dir}" | tee "${root}/results/latest-narrow-userns-apparmor-fix-dir.txt"
