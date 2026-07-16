#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

fail() {
  printf '[validate-github-app-broker] ERROR: %s\n' "$*" >&2
  exit 1
}

mode=online
if [[ "${1:-}" == "--offline" ]]; then
  mode=offline
fi

require_value() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  [[ "$actual" == "$expected" ]] || fail "$name must be $expected; found $actual."
}

require_absent_env() {
  local name="$1"
  [[ -z "${!name:-}" ]] || fail "Unsafe credential environment variable is set: $name"
}

BROKER_SCRIPT=/opt/devclaw-broker/bin/github-app-token-broker.js
CONFIG_FILE=/opt/devclaw-broker/config/github-app-broker.env
MARKER_FILE=/var/lib/devclaw/github-app-broker-configured
SOCKET=/run/devclaw/github-token-broker.sock
HELPER=/opt/devclaw/bin/github-app-git-credential-helper.sh

[[ "$EUID" -eq 0 ]] || fail "GitHub broker validator must run as root."
command -v curl >/dev/null 2>&1 || fail "Missing curl."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
command -v git >/dev/null 2>&1 || fail "Missing git."

[[ -f "$CONFIG_FILE" ]] || fail "Missing broker config file."
[[ -f "$MARKER_FILE" ]] || fail "Missing broker marker."
[[ -S "$SOCKET" ]] || fail "Missing broker UNIX socket."
[[ -x "$HELPER" ]] || fail "Missing Git credential helper."

require_value "broker config owner" "$(stat -c '%U:%G' "$CONFIG_FILE")" "root:devclaw-token"
require_value "broker config mode" "$(stat -c '%a' "$CONFIG_FILE")" "640"
require_value "broker script owner" "$(stat -c '%U:%G' "$BROKER_SCRIPT")" "root:devclaw-token"
require_value "broker script mode" "$(stat -c '%a' "$BROKER_SCRIPT")" "750"
require_value "broker marker owner" "$(stat -c '%U:%G' "$MARKER_FILE")" "devclaw-token:devclaw-broker"
require_value "broker marker mode" "$(stat -c '%a' "$MARKER_FILE")" "640"
require_value "broker socket owner" "$(stat -c '%U:%G' "$SOCKET")" "devclaw-token:devclaw-broker"
require_value "broker socket mode" "$(stat -c '%a' "$SOCKET")" "660"
require_value "helper owner" "$(stat -c '%U:%G' "$HELPER")" "root:devclaw-broker"
require_value "helper mode" "$(stat -c '%a' "$HELPER")" "750"

# shellcheck disable=SC1090
source "$CONFIG_FILE"

for name in \
  DEVCLAW_GITHUB_APP_ID \
  DEVCLAW_GITHUB_INSTALLATION_ID \
  DEVCLAW_GITHUB_OWNER \
  DEVCLAW_GITHUB_REPO \
  DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_PROJECT \
  DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_ID; do
  [[ -n "${!name:-}" ]] || fail "Broker config missing $name."
done

grep -q '^github_app_broker=true$' "$MARKER_FILE" ||
  fail "Broker marker missing github_app_broker=true."
grep -q "^github_owner=${DEVCLAW_GITHUB_OWNER}$" "$MARKER_FILE" ||
  fail "Broker marker owner mismatch."
grep -q "^github_repo=${DEVCLAW_GITHUB_REPO}$" "$MARKER_FILE" ||
  fail "Broker marker repo mismatch."
grep -q '^permissions=contents:write,issues:write,pull_requests:write,metadata:read$' "$MARKER_FILE" ||
  fail "Broker marker permissions mismatch."
grep -q '^token_storage=memory-only$' "$MARKER_FILE" ||
  fail "Broker marker must record memory-only token storage."

systemctl is-enabled devclaw-github-token-broker.service >/dev/null ||
  fail "devclaw-github-token-broker.service must be enabled."
systemctl is-active devclaw-github-token-broker.service >/dev/null ||
  fail "devclaw-github-token-broker.service must be active."

for name in GH_TOKEN GITHUB_TOKEN GITHUB_APP_PRIVATE_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY; do
  require_absent_env "$name"
done

if find /workspace/repos -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  fail "/workspace/repos must remain empty."
fi
if find /var/lib/devclaw/projects -mindepth 1 -print -quit | grep -q .; then
  fail "No DevClaw projects may be registered."
fi
if find /var/lib/devclaw/sessions -mindepth 1 -print -quit | grep -q .; then
  fail "No DevClaw worker sessions may exist."
fi

health_json="$(runuser -u devclaw-svc -- curl --silent --show-error --fail --unix-socket "$SOCKET" http://localhost/health)"
[[ "$(printf '%s\n' "$health_json" | jq -r '.ok')" == "true" ]] ||
  fail "Broker health did not return ok=true."

if [[ "$mode" == "offline" ]]; then
  printf '[validate-github-app-broker] Offline broker validation passed. Live GitHub checks were skipped.\n'
  exit 0
fi

repo_json="$(runuser -u devclaw-svc -- curl --silent --show-error --fail --unix-socket "$SOCKET" http://localhost/repo)"
[[ "$(printf '%s\n' "$repo_json" | jq -r '.ok')" == "true" ]] ||
  fail "Broker repo API read failed."
require_value "GitHub full_name" "$(printf '%s\n' "$repo_json" | jq -r '.full_name')" "${DEVCLAW_GITHUB_OWNER}/${DEVCLAW_GITHUB_REPO}"

token_json_1="$(runuser -u devclaw-svc -- curl --silent --show-error --fail --unix-socket "$SOCKET" http://localhost/token)"
token_json_2="$(runuser -u devclaw-svc -- curl --silent --show-error --fail --unix-socket "$SOCKET" http://localhost/token)"

for permission in contents issues pull_requests metadata; do
  expected="write"
  [[ "$permission" == "metadata" ]] && expected="read"
  actual="$(printf '%s\n' "$token_json_1" | jq -r --arg permission "$permission" '.permissions[$permission] // empty')"
  require_value "GitHub permission $permission" "$actual" "$expected"
done

token_1="$(printf '%s\n' "$token_json_1" | jq -r '.token // empty')"
token_2="$(printf '%s\n' "$token_json_2" | jq -r '.token // empty')"
[[ -n "$token_1" && -n "$token_2" ]] || fail "Broker did not return installation tokens."
[[ "$token_1" == "$token_2" ]] || fail "Broker token cache/refresh returned inconsistent tokens inside the freshness window."

runuser -u devclaw-svc -- env \
  DEVCLAW_GITHUB_BROKER_CONFIG="$CONFIG_FILE" \
  DEVCLAW_GITHUB_BROKER_SOCKET="$SOCKET" \
  git -c credential.helper="$HELPER" \
    ls-remote --heads "https://github.com/${DEVCLAW_GITHUB_OWNER}/${DEVCLAW_GITHUB_REPO}.git" \
    >/tmp/devclaw-github-ls-remote.txt

[[ -s /tmp/devclaw-github-ls-remote.txt ]] ||
  fail "Git transport ls-remote returned no refs."

printf '[validate-github-app-broker] Live GitHub broker validation passed. No repository clone or mutation was performed.\n'
