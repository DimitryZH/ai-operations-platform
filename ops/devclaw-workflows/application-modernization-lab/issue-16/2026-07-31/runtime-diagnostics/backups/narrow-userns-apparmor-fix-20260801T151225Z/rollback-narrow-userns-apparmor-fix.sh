#!/usr/bin/env bash
set -euo pipefail
backup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -a "${backup_dir}/subuid.bak" /etc/subuid
cp -a "${backup_dir}/subgid.bak" /etc/subgid
if [[ -f "${backup_dir}/openclaw-codex-bwrap.bak" ]]; then
  cp -a "${backup_dir}/openclaw-codex-bwrap.bak" /etc/apparmor.d/openclaw-codex-bwrap
  apparmor_parser -r /etc/apparmor.d/openclaw-codex-bwrap
else
  apparmor_parser -R /etc/apparmor.d/openclaw-codex-bwrap 2>/dev/null || true
  rm -f /etc/apparmor.d/openclaw-codex-bwrap
fi
if [[ -f "${backup_dir}/local-openclaw-codex-bwrap.bak" ]]; then
  cp -a "${backup_dir}/local-openclaw-codex-bwrap.bak" /etc/apparmor.d/local/openclaw-codex-bwrap
else
  rm -f /etc/apparmor.d/local/openclaw-codex-bwrap
fi
