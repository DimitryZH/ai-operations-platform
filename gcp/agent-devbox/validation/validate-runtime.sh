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

require_marker_line() {
  local path="$1"
  local expected="$2"
  grep -q "^${expected}$" "$path" || fail "Marker $path is missing: $expected"
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

check_absent_dir() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "Unexpected runtime state exists: $path"
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
  /var/lib/devclaw/gateway \
  /workspace \
  /workspace/repos \
  /workspace/worktrees \
  /workspace/evidence \
  /var/cache/devclaw-experiment/docker \
  /var/cache/devclaw-experiment/nuget \
  /var/cache/devclaw-experiment/dotnet \
  /var/cache/devclaw-experiment/devclaw-compat \
  /run/secrets/devclaw \
  /run/devclaw; do
  require_dir "$path"
done

require_owner_group /opt/devclaw root:devclaw-svc
require_mode /opt/devclaw 750
require_owner_group /var/lib/devclaw devclaw-svc:devclaw-svc
require_mode /var/lib/devclaw 750
if [[ -d /var/lib/devclaw/gateway ]]; then
  require_owner_group /var/lib/devclaw/gateway root:devclaw-broker
  require_mode /var/lib/devclaw/gateway 750
fi
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
if [[ -f /opt/devclaw/bin/validate-openclaw-devclaw.sh ]]; then
  require_owner_group /opt/devclaw/bin/validate-openclaw-devclaw.sh root:devclaw-svc
  require_mode /opt/devclaw/bin/validate-openclaw-devclaw.sh 750
fi
if [[ -f /opt/devclaw/bin/install-openclaw-devclaw.sh ]]; then
  require_owner_group /opt/devclaw/bin/install-openclaw-devclaw.sh root:devclaw-svc
  require_mode /opt/devclaw/bin/install-openclaw-devclaw.sh 750
fi
if [[ -f /opt/devclaw/bin/install-openclaw-gateway-service.sh ]]; then
  require_owner_group /opt/devclaw/bin/install-openclaw-gateway-service.sh root:devclaw-svc
  require_mode /opt/devclaw/bin/install-openclaw-gateway-service.sh 750
fi
if [[ -f /opt/devclaw/bin/validate-openclaw-gateway.sh ]]; then
  require_owner_group /opt/devclaw/bin/validate-openclaw-gateway.sh root:devclaw-svc
  require_mode /opt/devclaw/bin/validate-openclaw-gateway.sh 750
fi
if [[ -f /opt/devclaw/bin/github-app-token-broker.js ]]; then
  if [[ -f /var/lib/devclaw/github-app-broker-configured ]]; then
    require_owner_group /opt/devclaw/bin/github-app-token-broker.js root:devclaw-token
  else
    require_owner_group /opt/devclaw/bin/github-app-token-broker.js root:devclaw-svc
  fi
  require_mode /opt/devclaw/bin/github-app-token-broker.js 750
fi
if [[ -f /opt/devclaw/bin/github-app-git-credential-helper.sh ]]; then
  if [[ -f /var/lib/devclaw/github-app-broker-configured ]]; then
    require_owner_group /opt/devclaw/bin/github-app-git-credential-helper.sh root:devclaw-broker
  else
    require_owner_group /opt/devclaw/bin/github-app-git-credential-helper.sh root:devclaw-svc
  fi
  require_mode /opt/devclaw/bin/github-app-git-credential-helper.sh 750
fi
if [[ -f /opt/devclaw/bin/install-github-app-broker.sh ]]; then
  require_owner_group /opt/devclaw/bin/install-github-app-broker.sh root:devclaw-svc
  require_mode /opt/devclaw/bin/install-github-app-broker.sh 750
fi
if [[ -f /opt/devclaw/bin/validate-github-app-broker.sh ]]; then
  require_owner_group /opt/devclaw/bin/validate-github-app-broker.sh root:devclaw-svc
  require_mode /opt/devclaw/bin/validate-github-app-broker.sh 750
fi
if [[ -f /opt/devclaw/bin/build-devclaw-compat-package.sh ]]; then
  require_owner_group /opt/devclaw/bin/build-devclaw-compat-package.sh root:devclaw-svc
  require_mode /opt/devclaw/bin/build-devclaw-compat-package.sh 750
fi
if [[ -f /opt/devclaw/bin/validate-devclaw-compat-package.sh ]]; then
  require_owner_group /opt/devclaw/bin/validate-devclaw-compat-package.sh root:devclaw-svc
  require_mode /opt/devclaw/bin/validate-devclaw-compat-package.sh 750
fi
if [[ -f /opt/devclaw/config/devclaw-manifest-overlay.json ]]; then
  require_owner_group /opt/devclaw/config/devclaw-manifest-overlay.json root:devclaw-svc
  require_mode /opt/devclaw/config/devclaw-manifest-overlay.json 640
fi
if [[ -f /opt/devclaw/config/versions.env ]]; then
  require_owner_group /opt/devclaw/config/versions.env root:devclaw-svc
  require_mode /opt/devclaw/config/versions.env 640
fi

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
  require_marker_line /var/lib/devclaw/bootstrap-ready 'base_prerequisites=installed'
  require_marker_line /var/lib/devclaw/bootstrap-ready 'base_validation=passed'
else
  [[ ! -f /var/lib/devclaw/bootstrap-ready ]] || fail "Readiness marker exists before bootstrap validation completed."
fi

for user_name in devclaw-svc devclaw-token devclaw-validate root; do
  check_user_credentials "$user_name"
done

if git config --system --get credential.helper >/dev/null 2>&1; then
  fail "System Git credential helper is configured."
fi

if [[ -f /var/lib/devclaw/openclaw-devclaw-installed ]]; then
  [[ -x /opt/devclaw/bin/validate-openclaw-devclaw.sh ]] ||
    fail "Installed runtime marker exists, but installed-stage validator is missing."
  /opt/devclaw/bin/validate-openclaw-devclaw.sh
  if [[ -f /var/lib/devclaw/openclaw-gateway-managed ]]; then
    [[ -x /opt/devclaw/bin/validate-openclaw-gateway.sh ]] ||
      fail "Managed Gateway marker exists, but Gateway validator is missing."
    /opt/devclaw/bin/validate-openclaw-gateway.sh
  fi
else
  if command -v openclaw >/dev/null 2>&1; then
    fail "OpenClaw is installed, but the installed marker is absent."
  fi
  if [[ -d /home/devclaw-svc/.openclaw ]]; then
    fail "OpenClaw state/config exists, but the installed marker is absent."
  fi
  if npm list --global --prefix /opt/devclaw/runtime/npm --depth=0 2>/dev/null | grep -Eq 'openclaw|@laurentenhoor/devclaw'; then
    fail "OpenClaw or DevClaw package exists, but the installed marker is absent."
  fi
  check_absent_dir /opt/devclaw/runtime/npm/lib/node_modules/openclaw
fi

if [[ -f /var/lib/devclaw/github-app-broker-configured ]]; then
  [[ -x /opt/devclaw/bin/validate-github-app-broker.sh ]] ||
    fail "GitHub broker marker exists, but validator is missing."
  /opt/devclaw/bin/validate-github-app-broker.sh --offline
fi

printf '[validate-runtime] Runtime filesystem validation passed. No secrets were printed.\n'
