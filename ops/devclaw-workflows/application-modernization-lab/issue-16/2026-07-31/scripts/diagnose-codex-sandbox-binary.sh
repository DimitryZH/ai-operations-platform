#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/codex-sandbox-binary-diagnosis.txt}"
codex_home="/home/devclaw-svc/.openclaw/agents/main/agent/codex-home"
arg0_dir="${codex_home}/tmp/arg0/codex-arg0yl2y5v"
sandbox="${arg0_dir}/codex-linux-sandbox"
wrapper="${arg0_dir}/codex-execve-wrapper"

mkdir -p "$(dirname "${out_file}")"
{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== sandbox_file ===\n'
  ls -l "${sandbox}" "${wrapper}" || true
  file "${sandbox}" "${wrapper}" || true

  printf '\n=== sandbox_help ===\n'
  runuser -u devclaw-svc -- "${sandbox}" --help 2>&1 | sed -n '1,160p' || true

  printf '\n=== wrapper_help ===\n'
  runuser -u devclaw-svc -- "${wrapper}" --help 2>&1 | sed -n '1,160p' || true

  printf '\n=== sandbox_strings_relevant ===\n'
  strings "${sandbox}" 2>/dev/null | grep -Ei 'bwrap|loopback|net|namespace|sandbox|permission|RTM_NEWADDR|unshare|seccomp|network' | head -n 200 || true

  printf '\n=== config_references ===\n'
  grep -R -n -E 'sandbox_mode|danger-full-access|workspace-write|linux-sandbox|loopback|bwrap|approval_policy' "${codex_home}" 2>/dev/null | tail -n 200 || true
} | tee "${out_file}"
