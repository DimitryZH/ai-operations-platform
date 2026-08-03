#!/usr/bin/env bash
set -euo pipefail

session_id="${1:-7f439873-b1b4-4539-9ecb-0bfd0ee923a1}"
out_file="${2:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/devclaw-codex-sandbox-diagnosis.txt}"
session_file="/home/devclaw-svc/.openclaw/agents/main/sessions/${session_id}.jsonl"

mkdir -p "$(dirname "${out_file}")"
{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== session_tail ===\n'
  if [[ -f "${session_file}" ]]; then
    tail -n 160 "${session_file}"
  else
    printf 'missing session file: %s\n' "${session_file}"
  fi

  printf '\n=== processes ===\n'
  ps -ef | grep -E 'codex|openclaw|bwrap|bubblewrap' | grep -v grep || true

  printf '\n=== bwrap_binary ===\n'
  bwrap_path="$(command -v bwrap || true)"
  printf 'bwrap_path=%s\n' "${bwrap_path}"
  if [[ -n "${bwrap_path}" ]]; then
    ls -l "${bwrap_path}" || true
    getcap "${bwrap_path}" 2>/dev/null || true
    dpkg -S "${bwrap_path}" 2>/dev/null || true
    dpkg -l bubblewrap 2>/dev/null || true
  fi

  printf '\n=== namespace_sysctl ===\n'
  sysctl kernel.unprivileged_userns_clone 2>/dev/null || true
  sysctl user.max_user_namespaces 2>/dev/null || true
  sysctl user.max_net_namespaces 2>/dev/null || true

  printf '\n=== devclaw_user_limits ===\n'
  id devclaw-svc || true
  runuser -u devclaw-svc -- bash -lc 'ulimit -a' || true

  printf '\n=== bwrap_smoke_as_devclaw ===\n'
  runuser -u devclaw-svc -- bash -lc 'bwrap --unshare-user --uid 0 --gid 0 --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 --proc /proc /bin/true' 2>&1 || true
  runuser -u devclaw-svc -- bash -lc 'bwrap --unshare-user --unshare-net --uid 0 --gid 0 --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 --proc /proc /bin/true' 2>&1 || true

  printf '\n=== openclaw_config_selected ===\n'
  if [[ -f /home/devclaw-svc/.openclaw/openclaw.json ]]; then
    jq '{tools, plugins:{codex:.plugins.entries.codex, devclaw:.plugins.entries.devclaw}, models}' /home/devclaw-svc/.openclaw/openclaw.json 2>/dev/null || cat /home/devclaw-svc/.openclaw/openclaw.json
  fi

  printf '\n=== service ===\n'
  systemctl cat openclaw-gateway.service || true
  systemctl status openclaw-gateway.service --no-pager -l || true

  printf '\n=== recent_gateway_journal ===\n'
  journalctl -u openclaw-gateway.service --since '2 hours ago' --no-pager -n 220 || true

  printf '\n=== codex_related_files ===\n'
  find /home/devclaw-svc/.openclaw -maxdepth 6 -type f \( -iname '*codex*' -o -iname '*sandbox*' -o -iname '*approval*' -o -iname 'config.toml' -o -iname 'settings.json' \) -print | sort || true
} | tee "${out_file}"
