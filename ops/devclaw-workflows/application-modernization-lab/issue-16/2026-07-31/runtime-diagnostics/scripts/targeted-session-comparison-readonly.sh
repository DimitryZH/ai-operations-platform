#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics/results/targeted-session-comparison.txt}"
sessions_dir="/home/devclaw-svc/.openclaw/agents/main/sessions"

mkdir -p "$(dirname "${out_file}")"
{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for id in \
    54db9402-67d1-4740-9419-06c2fd9c0686 \
    445f00b0-e318-449d-9886-608c07ffbd03 \
    78c623b3-bff8-4c62-91a5-c41e0c7e78b2
  do
    file="${sessions_dir}/${id}.jsonl"
    printf '\n=== %s ===\n' "${id}"
    if [[ ! -f "${file}" ]]; then
      printf 'missing\n'
      continue
    fi
    printf '\n--- head ---\n'
    sed -n '1,8p' "${file}" || true
    printf '\n--- relevant tail ---\n'
    grep -n -Ei 'cwd|bwrap|RTM_NEWADDR|loopback|Operation not permitted|declined|Rejected|toolCall|toolResult|SMOKE|work_finish|Architecture|issue #?16|issues/16' "${file}" |
      tail -n 100 || true
  done
} | tee "${out_file}"
