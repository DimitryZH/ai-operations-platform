#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

fail() {
  printf '[validate-tools] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

CONFIG_PATH="${AGENT_DEVBOX_VALIDATION_CONFIG:-/opt/devclaw/config/bootstrap-validation.env}"
if [[ -f "$CONFIG_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_PATH"
fi

: "${EXPECTED_NODEJS_MAJOR:?Missing EXPECTED_NODEJS_MAJOR validation setting.}"
: "${EXPECTED_DOTNET_SDK_CHANNEL:?Missing EXPECTED_DOTNET_SDK_CHANNEL validation setting.}"

for cmd in curl jq unzip git docker gh dotnet node npm; do
  require_cmd "$cmd"
done

docker info >/dev/null 2>&1 || fail "Docker daemon is not available."
docker compose version >/dev/null 2>&1 || fail "Docker Compose plugin is not available."

id devclaw-svc >/dev/null 2>&1 || fail "Missing user devclaw-svc."
id devclaw-token >/dev/null 2>&1 || fail "Missing user devclaw-token."
id devclaw-validate >/dev/null 2>&1 || fail "Missing user devclaw-validate."

if ! id -nG devclaw-svc | tr ' ' '\n' | grep -qx docker; then
  fail "devclaw-svc is not a member of the docker group."
fi

if ! id -nG devclaw-svc | tr ' ' '\n' | grep -qx devclaw-broker; then
  fail "devclaw-svc is not a member of the devclaw-broker group."
fi

if ! id -nG devclaw-token | tr ' ' '\n' | grep -qx devclaw-broker; then
  fail "devclaw-token is not a member of the devclaw-broker group."
fi

if ! runuser -u devclaw-svc -- docker info >/dev/null 2>&1; then
  fail "devclaw-svc cannot access Docker in a fresh non-interactive session."
fi

if id -nG devclaw-token | tr ' ' '\n' | grep -qx docker; then
  fail "devclaw-token must not be a member of the docker group."
fi

if runuser -u devclaw-token -- docker info >/dev/null 2>&1; then
  fail "devclaw-token can access Docker and must not have Docker access."
fi

gh --version >/dev/null 2>&1 || fail "GitHub CLI binary is not runnable."
dotnet --info >/dev/null 2>&1 || fail ".NET SDK is not runnable."
dotnet_channel_pattern="${EXPECTED_DOTNET_SDK_CHANNEL//./\\.}"
dotnet --list-sdks | awk '{print $1}' | grep -Eq "^${dotnet_channel_pattern}\\." ||
  fail ".NET SDK channel $EXPECTED_DOTNET_SDK_CHANNEL is not installed."

node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
if [[ "$node_major" -lt "$EXPECTED_NODEJS_MAJOR" ]]; then
  fail "Node.js major version must be >= $EXPECTED_NODEJS_MAJOR; found $node_major."
fi

printf '[validate-tools] Base tool validation passed. No GitHub authentication was required.\n'
