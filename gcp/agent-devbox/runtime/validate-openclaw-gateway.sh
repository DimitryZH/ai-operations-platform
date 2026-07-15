#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

fail() {
  printf '[validate-openclaw-gateway] ERROR: %s\n' "$*" >&2
  exit 1
}

run_as_devclaw() {
  runuser -u devclaw-svc -- env \
    HOME=/home/devclaw-svc \
    XDG_CONFIG_HOME=/home/devclaw-svc/.config \
    XDG_CACHE_HOME=/home/devclaw-svc/.cache \
    XDG_DATA_HOME=/home/devclaw-svc/.local/share \
    OPENCLAW_STATE_DIR=/home/devclaw-svc/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/devclaw-svc/.openclaw/openclaw.json \
    OPENCLAW_NO_COLOR=1 \
    "$@"
}

config_get() {
  run_as_devclaw /usr/local/bin/openclaw config get "$1" |
    sed -E 's/^\s+|\s+$//g; s/^"//; s/"$//' |
    tail -n1
}

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

[[ "$EUID" -eq 0 ]] || fail "Gateway validator must run as root."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
command -v node >/dev/null 2>&1 || fail "Missing node."
command -v systemctl >/dev/null 2>&1 || fail "Missing systemctl."
[[ -f /var/lib/devclaw/openclaw-gateway-managed ]] || fail "Missing managed Gateway marker."

require_value "Gateway marker owner" "$(stat -c '%U:%G' /var/lib/devclaw/openclaw-gateway-managed)" "devclaw-svc:devclaw-svc"
require_value "Gateway marker mode" "$(stat -c '%a' /var/lib/devclaw/openclaw-gateway-managed)" "640"
grep -q '^gateway_managed=true$' /var/lib/devclaw/openclaw-gateway-managed ||
  fail "Managed Gateway marker is missing gateway_managed=true."
grep -q '^credentials=not-configured$' /var/lib/devclaw/openclaw-gateway-managed ||
  fail "Managed Gateway marker must preserve provider credentials as not configured."

require_value "Gateway token directory owner" "$(stat -c '%U:%G' /var/lib/devclaw/gateway)" "root:devclaw-broker"
require_value "Gateway token directory mode" "$(stat -c '%a' /var/lib/devclaw/gateway)" "750"
require_value "Gateway token file owner" "$(stat -c '%U:%G' /var/lib/devclaw/gateway/openclaw-gateway-token)" "root:devclaw-broker"
require_value "Gateway token file mode" "$(stat -c '%a' /var/lib/devclaw/gateway/openclaw-gateway-token)" "640"
require_value "Gateway env file owner" "$(stat -c '%U:%G' /var/lib/devclaw/gateway/openclaw-gateway.env)" "root:devclaw-broker"
require_value "Gateway env file mode" "$(stat -c '%a' /var/lib/devclaw/gateway/openclaw-gateway.env)" "640"
grep -q '^OPENCLAW_GATEWAY_TOKEN=' /var/lib/devclaw/gateway/openclaw-gateway.env ||
  fail "Gateway env file is missing OPENCLAW_GATEWAY_TOKEN."

require_value "gateway.mode" "$(config_get gateway.mode)" "local"
require_value "gateway.bind" "$(config_get gateway.bind)" "loopback"
require_value "tools.exec.mode" "$(config_get tools.exec.mode)" "deny"
require_value "plugins.entries.devclaw.enabled" "$(config_get plugins.entries.devclaw.enabled)" "true"
require_value "plugins.entries.devclaw.config.work_heartbeat.enabled" "$(config_get plugins.entries.devclaw.config.work_heartbeat.enabled)" "false"
require_value "plugins.entries.devclaw.config.projectExecution" "$(config_get plugins.entries.devclaw.config.projectExecution)" "sequential"

node <<'NODE'
const fs = require("fs");
const config = JSON.parse(fs.readFileSync("/home/devclaw-svc/.openclaw/openclaw.json", "utf8"));
if (JSON.stringify(config.plugins?.allow) !== JSON.stringify(["devclaw"])) {
  throw new Error("plugins.allow must be exactly [\"devclaw\"]");
}
NODE

systemctl is-enabled openclaw-gateway.service >/dev/null ||
  fail "openclaw-gateway.service must be enabled."
systemctl is-active openclaw-gateway.service >/dev/null ||
  fail "openclaw-gateway.service must be active."

ss -ltnp > /tmp/openclaw-gateway-listeners.txt 2>/dev/null || true
grep ':18789' /tmp/openclaw-gateway-listeners.txt >/dev/null ||
  fail "Gateway listener on TCP 18789 is absent."
if grep -E '(^|[[:space:]])(0\.0\.0\.0|\[::\]|10\.)[^[:space:]]*:18789' /tmp/openclaw-gateway-listeners.txt >/dev/null; then
  fail "Gateway listener is not loopback-only."
fi
grep -E '127\.0\.0\.1:18789|\[::1\]:18789' /tmp/openclaw-gateway-listeners.txt >/dev/null ||
  fail "Gateway loopback listener was not confirmed."

set -a
# shellcheck disable=SC1091
source /var/lib/devclaw/gateway/openclaw-gateway.env
set +a
[[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]] || fail "Gateway token was not loaded for validation."

run_gateway_cli_timeout() {
  local duration="$1"
  shift
  timeout "$duration" runuser -u devclaw-svc -- env \
    HOME=/home/devclaw-svc \
    XDG_CONFIG_HOME=/home/devclaw-svc/.config \
    XDG_CACHE_HOME=/home/devclaw-svc/.cache \
    XDG_DATA_HOME=/home/devclaw-svc/.local/share \
    OPENCLAW_STATE_DIR=/home/devclaw-svc/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/devclaw-svc/.openclaw/openclaw.json \
    OPENCLAW_NO_COLOR=1 \
    OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
    "$@"
}

run_gateway_cli_timeout 20s /usr/local/bin/openclaw gateway status \
  --url ws://127.0.0.1:18789 \
  --deep \
  --require-rpc \
  --json \
  --token "$OPENCLAW_GATEWAY_TOKEN" \
  --timeout 10000 > /tmp/openclaw-gateway-status.json

run_gateway_cli_timeout 20s /usr/local/bin/openclaw gateway call health \
  --url ws://127.0.0.1:18789 \
  --json \
  --token "$OPENCLAW_GATEWAY_TOKEN" \
  --timeout 10000 > /tmp/openclaw-gateway-health.json

run_gateway_cli_timeout 20s /usr/local/bin/openclaw gateway call status \
  --url ws://127.0.0.1:18789 \
  --json \
  --token "$OPENCLAW_GATEWAY_TOKEN" \
  --timeout 10000 > /tmp/openclaw-gateway-call-status.json

run_as_devclaw /usr/local/bin/openclaw plugins inspect devclaw --runtime --json > /tmp/openclaw-devclaw-runtime.json
run_as_devclaw /usr/local/bin/openclaw plugins doctor > /tmp/openclaw-plugins-doctor.txt 2>&1

[[ "$(jq -r '.rpc.ok' /tmp/openclaw-gateway-status.json)" == "true" ]] ||
  fail "Gateway status RPC did not report rpc.ok=true."
[[ "$(jq -r '(.plugins.loaded // []) | index("devclaw") != null' /tmp/openclaw-gateway-health.json)" == "true" ]] ||
  fail "Gateway health did not include devclaw in the active plugin set."
require_value "DevClaw runtime status" "$(jq -r '.plugin.status // empty' /tmp/openclaw-devclaw-runtime.json)" "loaded"
require_value "DevClaw runtime tool count" "$(jq -r '(.plugin.toolNames // []) | length' /tmp/openclaw-devclaw-runtime.json)" "23"
require_value "DevClaw runtime diagnostic count" "$(jq -r '(.diagnostics // []) | length' /tmp/openclaw-devclaw-runtime.json)" "0"
grep -q 'No plugin issues detected' /tmp/openclaw-plugins-doctor.txt ||
  fail "Plugin doctor reported an issue."

for name in GH_TOKEN GITHUB_TOKEN OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY SLACK_BOT_TOKEN DISCORD_TOKEN TELEGRAM_BOT_TOKEN; do
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

printf '[validate-openclaw-gateway] Managed Gateway validation passed. UI is ready for manual tunnel validation.\n'
