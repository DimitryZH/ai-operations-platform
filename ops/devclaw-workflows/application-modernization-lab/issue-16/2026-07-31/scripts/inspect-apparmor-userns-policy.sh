#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/apparmor-userns-policy-inspection.txt}"

mkdir -p "$(dirname "${out_file}")"
{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== apparmor_profiles_related ===\n'
  ls -l /etc/apparmor.d | grep -E 'userns|sandbox|linux|codex|openclaw' || true
  printf '\n=== unprivileged_userns_profile ===\n'
  sed -n '1,220p' /etc/apparmor.d/unprivileged_userns 2>/dev/null || true
  printf '\n=== userns_references ===\n'
  grep -R -n -E 'linux-sandbox|codex|userns|unconfined' /etc/apparmor.d 2>/dev/null | head -n 240 || true
  printf '\n=== apparmor_features_userns ===\n'
  find /sys/kernel/security/apparmor/features -maxdepth 4 -type f 2>/dev/null |
    grep userns |
    while read -r f; do
      printf -- '--- %s\n' "${f}"
      cat "${f}" || true
    done
} | tee "${out_file}"
