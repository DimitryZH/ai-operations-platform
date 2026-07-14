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

require_owner_group() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(stat -c '%U:%G' "$path")"
  [[ "$actual" == "$expected" ]] || fail "Unexpected owner for $path: $actual, expected $expected."
}

require_mode() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(stat -c '%a' "$path")"
  [[ "$actual" == "$expected" ]] || fail "Unexpected mode for $path: $actual, expected $expected."
}

require_member() {
  local user_name="$1"
  local group_name="$2"
  id -nG "$user_name" | tr ' ' '\n' | grep -qx "$group_name" ||
    fail "$user_name must be a member of $group_name."
}

require_not_member() {
  local user_name="$1"
  local group_name="$2"
  if id -nG "$user_name" | tr ' ' '\n' | grep -qx "$group_name"; then
    fail "$user_name must not be a member of $group_name."
  fi
}

check_absent_file() {
  local path="$1"
  [[ ! -f "$path" ]] || fail "Unsafe credential location exists: $path"
}

check_user_credentials() {
  local user_name="$1"
  local home_dir
  home_dir="$(getent passwd "$user_name" | cut -d: -f6)"
  [[ -n "$home_dir" && -d "$home_dir" ]] || return 0

  check_absent_file "$home_dir/.config/gh/hosts.yml"
  check_absent_file "$home_dir/.git-credentials"
  check_absent_file "$home_dir/.netrc"
  check_absent_file "$home_dir/.ssh/id_rsa"
  check_absent_file "$home_dir/.ssh/id_ed25519"
  check_absent_file "$home_dir/.ssh/id_ecdsa"

  if runuser -u "$user_name" -- git config --global --get credential.helper >/dev/null 2>&1; then
    fail "Git credential helper is configured for $user_name."
  fi
}

REQUIRE_BOOTSTRAP_MARKER="${REQUIRE_BOOTSTRAP_MARKER:-true}"

if [[ -n "${GH_TOKEN:-}" ]]; then
  fail "Unsafe credential environment variable is set: GH_TOKEN"
fi
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  fail "Unsafe credential environment variable is set: GITHUB_TOKEN"
fi

for path in \
  /opt/devclaw \
  /opt/devclaw/runtime \
  /opt/devclaw/config \
  /opt/devclaw/prompts \
  /opt/devclaw/bin \
  /var/lib/devclaw \
  /var/lib/devclaw/projects \
  /var/lib/devclaw/sessions \
  /var/lib/devclaw/audit \
  /workspace \
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

require_owner_group /opt/devclaw root:devclaw-svc
require_mode /opt/devclaw 750
require_owner_group /var/lib/devclaw devclaw-svc:devclaw-svc
require_mode /var/lib/devclaw 750
require_owner_group /workspace devclaw-svc:devclaw-svc
require_mode /workspace 750
require_owner_group /workspace/repos devclaw-svc:devclaw-svc
require_owner_group /workspace/worktrees devclaw-svc:devclaw-svc
require_owner_group /workspace/evidence devclaw-svc:devclaw-svc
require_owner_group /run/secrets/devclaw devclaw-token:devclaw-token
require_mode /run/secrets/devclaw 700
require_owner_group /run/devclaw devclaw-token:devclaw-broker
require_mode /run/devclaw 750
require_owner_group /opt/devclaw/bin/validate-tools.sh root:devclaw-svc
require_mode /opt/devclaw/bin/validate-tools.sh 750
require_owner_group /opt/devclaw/bin/validate-runtime.sh root:devclaw-svc
require_mode /opt/devclaw/bin/validate-runtime.sh 750

require_member devclaw-svc docker
require_member devclaw-svc devclaw-broker
require_member devclaw-token devclaw-broker
require_not_member devclaw-token docker
require_not_member devclaw-validate docker
require_not_member devclaw-validate devclaw-broker

if [[ "$REQUIRE_BOOTSTRAP_MARKER" == "true" ]]; then
  [[ -f /var/lib/devclaw/bootstrap-ready ]] || fail "Missing bootstrap readiness marker."
  require_owner_group /var/lib/devclaw/bootstrap-ready devclaw-svc:devclaw-svc
  require_mode /var/lib/devclaw/bootstrap-ready 640
  grep -q '^base_prerequisites=installed$' /var/lib/devclaw/bootstrap-ready || fail "Readiness marker must confirm base prerequisites only."
  grep -q '^openclaw=not-installed$' /var/lib/devclaw/bootstrap-ready || fail "Readiness marker must not claim OpenClaw is installed."
  grep -q '^devclaw=not-installed$' /var/lib/devclaw/bootstrap-ready || fail "Readiness marker must not claim DevClaw is installed."
  grep -q '^credentials=not-configured$' /var/lib/devclaw/bootstrap-ready || fail "Readiness marker must not claim credentials are configured."
else
  [[ ! -f /var/lib/devclaw/bootstrap-ready ]] || fail "Readiness marker exists before bootstrap validation completed."
fi

for user_name in devclaw-svc devclaw-token devclaw-validate root; do
  check_user_credentials "$user_name"
done

if git config --system --get credential.helper >/dev/null 2>&1; then
  fail "System Git credential helper is configured."
fi

if command -v openclaw >/dev/null 2>&1; then
  fail "OpenClaw is installed, but this validation expects base prerequisites only."
fi

if npm list -g --depth=0 2>/dev/null | grep -q '@laurentenhoor/devclaw'; then
  fail "DevClaw is installed, but this validation expects base prerequisites only."
fi

printf '[validate-runtime] Runtime filesystem validation passed. No secrets were printed.\n'
