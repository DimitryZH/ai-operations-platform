#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/openclaw-codex-session-settings-code.txt}"

mkdir -p "$(dirname "${out_file}")"
{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== candidate_paths ===\n'
  for path in \
    /home/devclaw-svc/.openclaw/agents/main/agent/plugins/codex \
    /home/devclaw-svc/.openclaw/npm/projects/openclaw-codex-8902d781d4/node_modules/@openclaw/codex \
    /opt/devclaw/runtime/npm/lib/node_modules/openclaw
  do
    if [[ -e "${path}" ]]; then
      printf '%s\n' "${path}"
    fi
  done

  printf '\n=== focused_matches ===\n'
  if command -v rg >/dev/null 2>&1; then
    rg -n --glob '*.js' --glob '*.mjs' --glob '*.cjs' --glob '*.ts' \
      'permission_profile|sandbox_policy|approval_policy|workspace-write|sandbox_mode|writable_roots|danger-full-access|read-only|thread_settings_applied|workspace_roots' \
      /home/devclaw-svc/.openclaw/agents/main/agent/plugins/codex \
      /home/devclaw-svc/.openclaw/npm/projects/openclaw-codex-8902d781d4/node_modules/@openclaw/codex \
      /opt/devclaw/runtime/npm/lib/node_modules/openclaw \
      2>/dev/null |
      grep -v '/node_modules/.*/node_modules/' |
      head -n 240 || true
  else
    find \
      /home/devclaw-svc/.openclaw/agents/main/agent/plugins/codex \
      /home/devclaw-svc/.openclaw/npm/projects/openclaw-codex-8902d781d4/node_modules/@openclaw/codex \
      /opt/devclaw/runtime/npm/lib/node_modules/openclaw \
      -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.ts' \) 2>/dev/null |
      grep -v '/node_modules/.*/node_modules/' |
      xargs -r grep -n -E 'permission_profile|sandbox_policy|approval_policy|workspace-write|sandbox_mode|writable_roots|danger-full-access|read-only|thread_settings_applied|workspace_roots' |
      head -n 240 || true
  fi

  printf '\n=== openclaw_config ===\n'
  sed -n '1,260p' /home/devclaw-svc/.openclaw/openclaw.json 2>/dev/null || true
} | tee "${out_file}"
