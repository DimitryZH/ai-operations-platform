#!/usr/bin/env bash
set -euo pipefail

root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics"
out_dir="${1:-${root}/results/post-reboot-smoke-logs-$(date -u +%Y%m%dT%H%M%SZ)}"
status_file="${2:-${root}/results/post-reboot-minimal-smoke-status.json}"
state_dir="/home/devclaw-svc/.openclaw"

fail() {
  printf '[collect-post-reboot-smoke-logs-readonly] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on DevClaw VM"
command -v jq >/dev/null 2>&1 || fail "missing jq"
mkdir -p "${out_dir}"

session_key=""
session_id=""
if [[ -f "${status_file}" ]]; then
  session_key="$(jq -r '.sessionKey // empty' "${status_file}")"
  session_id="$(jq -r '.sessionId // empty' "${status_file}")"
fi

{
  printf 'collectedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'statusFile=%s\n' "${status_file}"
  printf 'sessionKey=%s\n' "${session_key}"
  printf 'sessionId=%s\n' "${session_id}"
  printf 'bootId=%s\n' "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
  printf 'kernel=%s\n' "$(uname -a)"
  printf 'apparmorRestrictUserns=%s\n' "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true)"
} | tee "${out_dir}/summary.txt" >/dev/null

journalctl -b -k --no-pager > "${out_dir}/kernel-current-boot.log" 2>&1 || true
journalctl -b --no-pager -u openclaw-gateway.service > "${out_dir}/openclaw-gateway-current-boot.log" 2>&1 || true
journalctl -b --no-pager > "${out_dir}/journal-current-boot.log" 2>&1 || true
dmesg > "${out_dir}/dmesg-current-boot.log" 2>&1 || true

grep -Ei 'bwrap|bubblewrap|RTM_NEWADDR|loopback|Operation not permitted|apparmor|DENIED|net_admin|setpcap|unprivileged_userns|codex|openclaw|post-reboot-runtime-smoke' \
  "${out_dir}/kernel-current-boot.log" \
  "${out_dir}/openclaw-gateway-current-boot.log" \
  "${out_dir}/journal-current-boot.log" \
  "${out_dir}/dmesg-current-boot.log" \
  > "${out_dir}/relevant-runtime-lines.log" 2>/dev/null || true

if [[ -n "${session_id}" && -f "${state_dir}/agents/main/sessions/${session_id}.jsonl" ]]; then
  cp -a "${state_dir}/agents/main/sessions/${session_id}.jsonl" "${out_dir}/subagent-session-${session_id}.jsonl"
fi

if [[ -f "${status_file}" ]]; then
  cp -a "${status_file}" "${out_dir}/post-reboot-minimal-smoke-status.json"
fi

jq -n \
  --arg collectedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg outDir "${out_dir}" \
  --arg sessionKey "${session_key}" \
  --arg sessionId "${session_id}" \
  --rawfile relevant "${out_dir}/relevant-runtime-lines.log" \
  '{
    collectedAt:$collectedAt,
    outDir:$outDir,
    sessionKey:$sessionKey,
    sessionId:$sessionId,
    relevantRuntimeLines:$relevant
  }' | tee "${out_dir}/post-reboot-smoke-log-summary.json"

printf '%s\n' "${out_dir}" | tee "${root}/results/latest-post-reboot-smoke-logs-dir.txt"
