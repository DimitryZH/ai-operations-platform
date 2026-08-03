#!/usr/bin/env bash
set -euo pipefail

root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics"
out_dir="${1:-${root}/results/runtime-session-search-$(date -u +%Y%m%dT%H%M%SZ)}"
state_dir="/home/devclaw-svc/.openclaw"
sessions_dir="${state_dir}/agents/main/sessions"
sessions_file="${sessions_dir}/sessions.json"
failed_key="agent:main:subagent:application-modernization-lab-developer-senior-ara-issue-16-20260731t194406z"

fail() {
  printf '[search-runtime-session-evidence] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on DevClaw VM"
command -v jq >/dev/null 2>&1 || fail "missing jq"
mkdir -p "${out_dir}"

{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== explicit_failed_key_lookup ===\n'
  jq -c --arg key "${failed_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}" 2>/dev/null || true
  printf '\n=== sessions_keys_matching_issue16_or_ara_or_zandra ===\n'
  jq -r '(.sessions // .) | to_entries[] | select(.key | test("issue-16|issue16|ara|zandra|application-modernization-lab"; "i")) | [.key, (.value.status // ""), (.value.label // ""), (.value.sessionId // .value.id // "")] | @tsv' "${sessions_file}" 2>/dev/null || true
  printf '\n=== transcript_files_matching_explicit_failed_key ===\n'
  grep -R -l -F "${failed_key}" "${sessions_dir}" 2>/dev/null || true
  printf '\n=== transcript_files_matching_issue16 ===\n'
  grep -R -l -Ei 'issue #?16|issue-16|/issues/16|Experiment 08B|08B|Aspire' "${sessions_dir}" 2>/dev/null | sort || true
  printf '\n=== transcript_files_matching_bwrap ===\n'
  grep -R -l -Ei 'bwrap|RTM_NEWADDR|loopback|bubblewrap' "${sessions_dir}" 2>/dev/null | sort || true
} > "${out_dir}/session-search-summary.txt"

{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== issue16_session_extracts ===\n'
  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    printf '\n--- file=%s ---\n' "${file}"
    sed -n '1,12p' "${file}" || true
    printf '\n--- relevant lines ---\n'
    grep -n -Ei 'issue #?16|issue-16|/issues/16|Experiment 08B|08B|Aspire|bwrap|RTM_NEWADDR|loopback|declined|failed|toolCall|toolResult' "${file}" | head -n 140 || true
    printf '\n--- tail ---\n'
    tail -n 60 "${file}" || true
  done < <(grep -R -l -Ei 'issue #?16|issue-16|/issues/16|Experiment 08B|08B|Aspire|bwrap|RTM_NEWADDR|loopback' "${sessions_dir}" 2>/dev/null | sort)
} > "${out_dir}/issue16-session-transcript-extracts.txt"

{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== passwd_groups ===\n'
  getent passwd devclaw-svc || true
  id devclaw-svc || true
  groups devclaw-svc || true
  printf '\n=== subuid_subgid ===\n'
  grep -n '^devclaw-svc:' /etc/subuid /etc/subgid 2>/dev/null || true
  printf '\n=== namespace_sysctls ===\n'
  sysctl kernel.unprivileged_userns_clone user.max_user_namespaces user.max_net_namespaces kernel.apparmor_restrict_unprivileged_userns 2>&1 || true
  printf '\n=== sandbox_binary_candidates ===\n'
  find "${state_dir}" /opt/devclaw -xdev \( -iname '*bwrap*' -o -iname '*bubblewrap*' -o -iname 'codex-linux-sandbox*' -o -iname '*sandbox*' \) -type f 2>/dev/null | sort || true
  printf '\n=== sandbox_binary_file_info ===\n'
  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    ls -l "${file}" || true
    file "${file}" || true
    "${file}" --version 2>&1 | head -n 5 || true
  done < <(find "${state_dir}" /opt/devclaw -xdev \( -iname '*bwrap*' -o -iname '*bubblewrap*' -o -iname 'codex-linux-sandbox*' \) -type f 2>/dev/null | sort)
} > "${out_dir}/sandbox-identity-subuid-evidence.txt"

{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== gateway_bwrap_lines ===\n'
  journalctl -u openclaw-gateway.service --since '2026-07-31 18:00:00 UTC' --no-pager 2>/dev/null |
    grep -Ei 'bwrap|RTM_NEWADDR|loopback|bubblewrap|sandbox|namespace|Operation not permitted|issue-16|20260731t194406|20260801t012303|minimal-smoke' || true
  printf '\n=== kernel_denials_filtered ===\n'
  journalctl -k --since '2026-07-31 18:00:00 UTC' --no-pager 2>/dev/null |
    grep -Ei 'apparmor|audit|denied|seccomp|bwrap|bubblewrap|namespace|RTM_NEWADDR|operation not permitted|codex' || true
} > "${out_dir}/runtime-error-log-lines.txt"

tar -C "${out_dir}/.." -czf "${out_dir}.tar.gz" "$(basename "${out_dir}")"
printf '%s\n' "${out_dir}" | tee "${root}/results/latest-runtime-session-search-dir.txt"
