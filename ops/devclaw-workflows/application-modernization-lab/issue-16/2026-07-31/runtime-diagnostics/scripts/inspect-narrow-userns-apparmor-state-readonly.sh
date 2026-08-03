#!/usr/bin/env bash
set -euo pipefail

root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics"
out_dir="${1:-${root}/results/narrow-userns-apparmor-inspect-$(date -u +%Y%m%dT%H%M%SZ)}"

fail() {
  printf '[inspect-narrow-userns-apparmor-state-readonly] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on DevClaw VM"
command -v jq >/dev/null 2>&1 || fail "missing jq"
mkdir -p "${out_dir}"

{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'kernel=%s\n' "$(uname -a)"
  printf 'ubuntu='
  . /etc/os-release
  printf '%s %s\n' "${PRETTY_NAME:-unknown}" "${VERSION_ID:-unknown}"
  printf 'apparmorRestrictUserns=%s\n' "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true)"
  printf 'unprivilegedUsernsClone=%s\n' "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || true)"
  printf 'newuidmap=%s\n' "$(command -v newuidmap || true)"
  printf 'newgidmap=%s\n' "$(command -v newgidmap || true)"
  dpkg-query -W -f='uidmap=${Version}\n' uidmap 2>/dev/null || true
} | tee "${out_dir}/system-summary.txt" >/dev/null

grep -E '^devclaw-svc:' /etc/subuid /etc/subgid > "${out_dir}/devclaw-subid.txt" 2>&1 || true
aa-status > "${out_dir}/aa-status.txt" 2>&1 || true
sysctl -a > "${out_dir}/sysctl-all.txt" 2>&1 || true

if [[ -f /etc/apparmor.d/unprivileged_userns ]]; then
  cp -a /etc/apparmor.d/unprivileged_userns "${out_dir}/apparmor-unprivileged_userns"
fi
if [[ -f /etc/apparmor.d/openclaw-codex-bwrap ]]; then
  cp -a /etc/apparmor.d/openclaw-codex-bwrap "${out_dir}/apparmor-openclaw-codex-bwrap"
fi

find /home/devclaw-svc/.openclaw/npm/projects \
  -path '*/codex-resources/bwrap' \
  -type f \
  -printf '%p\n' \
  > "${out_dir}/codex-bwrap-paths.txt" 2>/dev/null || true

journalctl -b -k --no-pager | grep -Ei 'bwrap|userns|apparmor|DENIED|net_admin|setpcap|RTM_NEWADDR' \
  > "${out_dir}/current-boot-userns-apparmor-lines.log" 2>/dev/null || true

jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg outDir "${out_dir}" \
  --rawfile summary "${out_dir}/system-summary.txt" \
  --rawfile subid "${out_dir}/devclaw-subid.txt" \
  --rawfile bwrap "${out_dir}/codex-bwrap-paths.txt" \
  '{
    checkedAt:$checkedAt,
    outDir:$outDir,
    systemSummary:$summary,
    devclawSubid:$subid,
    codexBwrapPaths:($bwrap | split("\n") | map(select(length > 0)))
  }' | tee "${out_dir}/inspect-summary.json"

printf '%s\n' "${out_dir}" | tee "${root}/results/latest-narrow-userns-apparmor-inspect-dir.txt"
