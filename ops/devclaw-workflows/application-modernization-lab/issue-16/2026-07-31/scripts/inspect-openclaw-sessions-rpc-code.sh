#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/openclaw-sessions-rpc-code.txt}"
root="/opt/devclaw/runtime/npm/lib/node_modules/openclaw/dist"

mkdir -p "$(dirname "${out_file}")"
{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== sessions.patch matches ===\n'
  if command -v rg >/dev/null 2>&1; then
    rg -n 'sessions\.patch|sessions\.create|sessionPatch|patchSession|updateSession' "${root}" --glob '*.js' 2>/dev/null | head -n 160 || true
  else
    grep -R -n -E 'sessions\.patch|sessions\.create|sessionPatch|patchSession|updateSession' "${root}" 2>/dev/null | head -n 160 || true
  fi
} | tee "${out_file}"
