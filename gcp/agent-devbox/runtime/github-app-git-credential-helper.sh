#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CONFIG_FILE="${DEVCLAW_GITHUB_HELPER_CONFIG:-/var/lib/devclaw/gateway/github-app-helper.env}"

[[ -f "$CONFIG_FILE" ]] || exit 0
# shellcheck disable=SC1090
source "$CONFIG_FILE"

SOCKET="${DEVCLAW_GITHUB_BROKER_SOCKET:-/run/devclaw/github-token-broker.sock}"
[[ -n "${DEVCLAW_GITHUB_OWNER:-}" ]] || exit 0
[[ -n "${DEVCLAW_GITHUB_REPO:-}" ]] || exit 0
[[ -n "$SOCKET" ]] || exit 0

protocol=""
host=""
path=""
while IFS= read -r line; do
  [[ -n "$line" ]] || break
  case "$line" in
    protocol=*) protocol="${line#protocol=}" ;;
    host=*) host="${line#host=}" ;;
    path=*) path="${line#path=}" ;;
  esac
done

[[ "$protocol" == "https" ]] || exit 0
[[ "$host" == "github.com" ]] || exit 0

repo_path="${path%.git}"
repo_path="${repo_path#/}"
expected_path="${DEVCLAW_GITHUB_OWNER}/${DEVCLAW_GITHUB_REPO}"
[[ "$repo_path" == "$expected_path" ]] || exit 0

token_json="$(curl --silent --show-error --fail --unix-socket "$SOCKET" http://localhost/token)"
token="$(printf '%s\n' "$token_json" | jq -r '.token // empty')"
[[ -n "$token" ]] || exit 1

printf 'username=x-access-token\n'
printf 'password=%s\n' "$token"
