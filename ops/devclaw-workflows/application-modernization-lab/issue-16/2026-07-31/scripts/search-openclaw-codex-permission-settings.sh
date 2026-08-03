#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/openclaw-codex-permission-settings-search.txt}"

mkdir -p "$(dirname "${out_file}")"
{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  grep -R -n -E 'permission_profile|sandbox_mode|writable_roots|workspace-write|danger-full-access|sandboxPolicy|permissions|network_access' \
    /home/devclaw-svc/.openclaw/npm/projects/openclaw-codex-8902d781d4/node_modules/@openclaw/codex \
    /home/devclaw-svc/.openclaw/agents/main/agent/plugins/codex \
    /opt/devclaw/runtime/npm/lib/node_modules/openclaw \
    2>/dev/null |
    head -n 400 || true
} | tee "${out_file}"
