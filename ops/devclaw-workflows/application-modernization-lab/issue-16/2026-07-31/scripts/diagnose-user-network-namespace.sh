#!/usr/bin/env bash
set -euo pipefail

out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/user-network-namespace-diagnosis.txt}"

mkdir -p "$(dirname "${out_file}")"
{
  printf 'checkedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n=== binaries ===\n'
  command -v unshare || true
  command -v ip || true
  command -v newuidmap || true
  command -v newgidmap || true
  command -v bwrap || true
  ls -l "$(command -v unshare)" "$(command -v ip)" 2>/dev/null || true
  if command -v newuidmap >/dev/null 2>&1; then ls -l "$(command -v newuidmap)" "$(command -v newgidmap)" || true; fi
  if command -v bwrap >/dev/null 2>&1; then ls -l "$(command -v bwrap)" || true; fi

  printf '\n=== subuid_subgid ===\n'
  grep '^devclaw-svc:' /etc/subuid /etc/subgid 2>/dev/null || true

  printf '\n=== unshare_user ===\n'
  runuser -u devclaw-svc -- unshare -Ur /bin/true 2>&1 || true

  printf '\n=== unshare_user_net_true ===\n'
  runuser -u devclaw-svc -- unshare -Urn /bin/true 2>&1 || true

  printf '\n=== unshare_user_net_loopback ===\n'
  runuser -u devclaw-svc -- unshare -Urn /bin/sh -c 'ip link set lo up && ip addr show lo' 2>&1 || true

  printf '\n=== root_unshare_user_net_loopback ===\n'
  unshare -Urn /bin/sh -c 'ip link set lo up && ip addr show lo' 2>&1 || true
} | tee "${out_file}"
