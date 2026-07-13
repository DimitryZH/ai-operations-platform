#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

fail() {
  printf '[validate-runtime] ERROR: %s\n' "$*" >&2
  exit 1
}

require_dir() {
  [[ -d "$1" ]] || fail "Missing directory: $1"
}

require_owner() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(stat -c '%U:%G' "$path")"
  [[ "$actual" == "$expected" ]] || fail "Unexpected owner for $path: $actual, expected $expected."
}

for path in \
  /opt/devclaw/runtime \
  /opt/devclaw/config \
  /opt/devclaw/prompts \
  /opt/devclaw/bin \
  /var/lib/devclaw/projects \
  /var/lib/devclaw/sessions \
  /var/lib/devclaw/audit \
  /workspace/repos \
  /workspace/worktrees \
  /workspace/evidence \
  /var/cache/devclaw-experiment/docker \
  /var/cache/devclaw-experiment/nuget \
  /var/cache/devclaw-experiment/dotnet \
  /run/secrets/devclaw \
  /run/devclaw; do
  require_dir "$path"
done

require_owner /workspace devclaw-svc:devclaw-svc
require_owner /workspace/repos devclaw-svc:devclaw-svc
require_owner /workspace/worktrees devclaw-svc:devclaw-svc
require_owner /workspace/evidence devclaw-svc:devclaw-svc
require_owner /run/secrets/devclaw devclaw-token:devclaw-token

[[ -f /var/lib/devclaw/bootstrap-ready ]] || fail "Missing bootstrap readiness marker."
grep -q '^openclaw=not-installed$' /var/lib/devclaw/bootstrap-ready || fail "Readiness marker must not claim OpenClaw is installed."
grep -q '^devclaw=not-installed$' /var/lib/devclaw/bootstrap-ready || fail "Readiness marker must not claim DevClaw is installed."
grep -q '^credentials=not-configured$' /var/lib/devclaw/bootstrap-ready || fail "Readiness marker must not claim credentials are configured."

if id -nG devclaw-token | tr ' ' '\n' | grep -qx docker; then
  fail "devclaw-token must not be in the docker group."
fi

for home_dir in /home/devclaw-svc /home/devclaw-token /home/devclaw-validate /root; do
  [[ ! -f "$home_dir/.config/gh/hosts.yml" ]] || fail "Found local GitHub CLI auth file under $home_dir."
  [[ ! -f "$home_dir/.git-credentials" ]] || fail "Found local git credentials under $home_dir."
done

if command -v openclaw >/dev/null 2>&1; then
  fail "OpenClaw is installed, but this validation expects base prerequisites only."
fi

if npm list -g --depth=0 2>/dev/null | grep -q '@laurentenhoor/devclaw'; then
  fail "DevClaw is installed, but this validation expects base prerequisites only."
fi

printf '[validate-runtime] Runtime filesystem validation passed. No secrets were printed.\n'
