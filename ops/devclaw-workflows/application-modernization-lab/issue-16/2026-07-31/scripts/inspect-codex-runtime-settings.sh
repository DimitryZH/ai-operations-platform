#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/codex-runtime-settings-inspection.txt}"
codex_home="/home/devclaw-svc/.openclaw/agents/main/agent/codex-home"
codex_bin="${codex_home}/tmp/arg0/codex-arg0yl2y5v/codex-execve-wrapper"

mkdir -p "$(dirname "${out_file}")"
{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== version ===\n'
  runuser -u devclaw-svc -- "${codex_bin}" --version 2>&1 || true
  printf '\n=== help ===\n'
  runuser -u devclaw-svc -- "${codex_bin}" --help 2>&1 | sed -n '1,260p' || true
  printf '\n=== config_current ===\n'
  cat "${codex_home}/config.toml" || true
  printf '\n=== recent_turn_settings ===\n'
  find "${codex_home}/sessions/2026/07/31" -type f 2>/dev/null |
    sort |
    tail -n 20 |
    xargs -r grep -h -E 'thread_settings_applied|sandbox_policy|permission_profile|sandbox_mode|approval_policy' |
    tail -n 120 || true
  printf '\n=== binary_config_strings ===\n'
  strings "${codex_bin}" 2>/dev/null |
    grep -E 'sandbox_mode|danger-full-access|workspace-write|read-only|approval_policy|disable.*sandbox|sandbox.*mode|network_access|permission_profile' |
    sort -u |
    head -n 240 || true
} | tee "${out_file}"
