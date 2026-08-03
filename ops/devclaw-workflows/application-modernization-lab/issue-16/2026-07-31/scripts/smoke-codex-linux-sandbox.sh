#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/codex-linux-sandbox-smoke.txt}"
sandbox="/home/devclaw-svc/.openclaw/agents/main/agent/codex-home/tmp/arg0/codex-arg0yl2y5v/codex-linux-sandbox"
cwd="/home/devclaw-svc/.openclaw/workspace"

mkdir -p "$(dirname "${out_file}")"
{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'sandbox=%s\n' "${sandbox}"
  printf '\n=== true ===\n'
  runuser -u devclaw-svc -- "${sandbox}" --sandbox-policy-cwd "${cwd}" /bin/true 2>&1 || true
  printf '\n=== echo ===\n'
  runuser -u devclaw-svc -- "${sandbox}" --sandbox-policy-cwd "${cwd}" /bin/bash -lc 'echo smoke' 2>&1 || true
  printf '\n=== true_no_proc ===\n'
  runuser -u devclaw-svc -- "${sandbox}" --no-proc --sandbox-policy-cwd "${cwd}" /bin/true 2>&1 || true
} | tee "${out_file}"
