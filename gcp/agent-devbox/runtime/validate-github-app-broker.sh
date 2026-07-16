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
HELPER_CONFIG=/var/lib/devclaw/gateway/github-app-helper.env
MARKER_FILE=/var/lib/devclaw/github-app-broker-configured
SOCKET=/run/devclaw/github-token-broker.sock
HELPER=/opt/devclaw/bin/github-app-git-credential-helper.sh

[[ "$EUID" -eq 0 ]] || fail "GitHub broker validator must run as root."
command -v curl >/dev/null 2>&1 || fail "Missing curl."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
command -v git >/dev/null 2>&1 || fail "Missing git."

[[ -f "$CONFIG_FILE" ]] || fail "Missing broker config file."
[[ -f "$HELPER_CONFIG" ]] || fail "Missing Git credential helper config file."
[[ -f "$MARKER_FILE" ]] || fail "Missing broker marker."
[[ -S "$SOCKET" ]] || fail "Missing broker UNIX socket."
[[ -x "$HELPER" ]] || fail "Missing Git credential helper."

require_value "broker config owner" "$(stat -c '%U:%G' "$CONFIG_FILE")" "root:devclaw-token"
require_value "broker config mode" "$(stat -c '%a' "$CONFIG_FILE")" "640"
require_value "helper config owner" "$(stat -c '%U:%G' "$HELPER_CONFIG")" "root:devclaw-broker"
require_value "helper config mode" "$(stat -c '%a' "$HELPER_CONFIG")" "640"
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
grep -q '^git_credential_helper=/opt/devclaw/bin/github-app-git-credential-helper.sh$' "$MARKER_FILE" ||
  fail "Broker marker credential helper mismatch."
grep -q '^git_credential_helper_config=/var/lib/devclaw/gateway/github-app-helper.env$' "$MARKER_FILE" ||
  fail "Broker marker credential helper config mismatch."

if grep -Eq 'APP_ID|INSTALLATION|PRIVATE_KEY|SECRET' "$HELPER_CONFIG"; then
  fail "Git credential helper config must contain only non-secret repository and socket settings."
fi

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

helper_output="$(
  runuser -u devclaw-svc -- env -i \
    HOME=/home/devclaw-svc \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$HELPER" <<EOF
protocol=https
host=github.com
path=${DEVCLAW_GITHUB_OWNER}/${DEVCLAW_GITHUB_REPO}.git

EOF
)"
helper_username="$(printf '%s\n' "$helper_output" | awk -F= '$1 == "username" { print $2; exit }')"
helper_password="$(printf '%s\n' "$helper_output" | awk -F= '$1 == "password" { print $2; exit }')"
require_value "credential helper username" "$helper_username" "x-access-token"
[[ -n "$helper_password" ]] || fail "Credential helper returned an empty password."
[[ "$helper_password" == "$token_1" ]] ||
  fail "Credential helper password did not match the broker-issued installation token."

negative_repo_output="$(
  runuser -u devclaw-svc -- env -i \
    HOME=/home/devclaw-svc \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$HELPER" <<EOF
protocol=https
host=github.com
path=${DEVCLAW_GITHUB_OWNER}/not-${DEVCLAW_GITHUB_REPO}.git

EOF
)"
[[ -z "$negative_repo_output" ]] ||
  fail "Credential helper returned credentials for an unapproved repository."

negative_host_output="$(
  runuser -u devclaw-svc -- env -i \
    HOME=/home/devclaw-svc \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$HELPER" <<EOF
protocol=https
host=example.com
path=${DEVCLAW_GITHUB_OWNER}/${DEVCLAW_GITHUB_REPO}.git

EOF
)"
[[ -z "$negative_host_output" ]] ||
  fail "Credential helper returned credentials for an unapproved host."

check_file_for_sensitive_material() {
  local path="$1"
  local token="$2"
  [[ -f "$path" && -r "$path" ]] || return 0
  local size
  size="$(stat -c '%s' "$path" 2>/dev/null || printf 0)"
  [[ "$size" -le 10485760 ]] || return 0

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" != *"$token"* ]] ||
      fail "Installation token appeared in $path."
    case "$line" in
      "-----BEGIN RSA PRIVATE KEY-----"|"-----BEGIN PRIVATE KEY-----"|"-----BEGIN OPENSSH PRIVATE KEY-----")
        fail "Private key material appeared in $path."
        ;;
    esac
  done < "$path"
}

while IFS= read -r -d '' candidate; do
  check_file_for_sensitive_material "$candidate" "$helper_password"
done < <(
  find /opt/devclaw/bin /opt/devclaw/config /opt/devclaw-broker /var/lib/devclaw /workspace \
    -xdev -type f -size -10M -print0 2>/dev/null
  find /var/log \
    -xdev -type f \( -name 'cloud-init*.log' -o -name 'syslog' -o -name 'auth.log' \) \
    -size -10M -print0 2>/dev/null
)

ls_remote_output="$(
  runuser -u devclaw-svc -- env -i \
    HOME=/home/devclaw-svc \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= \
      -c credential.helper="$HELPER" \
      -c credential.useHttpPath=true \
      ls-remote --heads "https://github.com/${DEVCLAW_GITHUB_OWNER}/${DEVCLAW_GITHUB_REPO}.git"
)"

[[ -n "$ls_remote_output" ]] ||
  fail "Git transport ls-remote returned no refs."

printf '[validate-github-app-broker] Live GitHub broker validation passed. No repository clone or mutation was performed.\n'
