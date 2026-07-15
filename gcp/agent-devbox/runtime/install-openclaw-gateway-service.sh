#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

fail() {
  printf '[install-openclaw-gateway-service] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[install-openclaw-gateway-service] %s\n' "$*"
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

require_value() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  [[ "$actual" == "$expected" ]] || fail "$name must be $expected; found $actual."
}

write_json_config() {
  node <<'NODE'
const fs = require("fs");
const configPath = "/home/devclaw-svc/.openclaw/openclaw.json";
const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
const stage4ModelProvider = process.env.STAGE4_MODEL_PROVIDER_ENABLED === "true";
config.gateway = config.gateway || {};
config.gateway.mode = "local";
config.gateway.bind = "loopback";
config.tools = config.tools || {};
config.tools.exec = config.tools.exec || {};
delete config.tools.exec.security;
delete config.tools.exec.ask;
if (stage4ModelProvider) {
  config.tools.exec.mode = "auto";
  config.tools.exec.strictInlineEval = true;
  config.tools.exec.commandHighlighting = true;
} else {
  config.tools.exec.mode = "deny";
  delete config.tools.exec.strictInlineEval;
  delete config.tools.exec.commandHighlighting;
}
config.plugins = config.plugins || {};
config.plugins.allow = stage4ModelProvider ? ["devclaw", "codex"] : ["devclaw"];
config.plugins.entries = config.plugins.entries || {};
config.plugins.entries.devclaw = config.plugins.entries.devclaw || {};
config.plugins.entries.devclaw.enabled = true;
config.plugins.entries.devclaw.config = config.plugins.entries.devclaw.config || {};
config.plugins.entries.devclaw.config.work_heartbeat = config.plugins.entries.devclaw.config.work_heartbeat || {};
config.plugins.entries.devclaw.config.work_heartbeat.enabled = false;
config.plugins.entries.devclaw.config.projectExecution = "sequential";
if (stage4ModelProvider) {
  config.plugins.entries.codex = config.plugins.entries.codex || {};
  config.plugins.entries.codex.enabled = true;
  config.agents = config.agents || {};
  config.agents.defaults = config.agents.defaults || {};
  config.agents.defaults.models = config.agents.defaults.models || {};
  delete config.agents.defaults.models["openai/gpt-5.6-sol"];
  config.agents.defaults.models["openai/gpt-5.5"] = {
    ...(config.agents.defaults.models["openai/gpt-5.5"] || {}),
    agentRuntime: { id: "codex" }
  };
  if (config.models?.providers) {
    delete config.models.providers.openai;
    if (Object.keys(config.models.providers).length === 0) {
      delete config.models.providers;
    }
  }
  if (config.models && Object.keys(config.models).length === 0) {
    delete config.models;
  }
} else if (config.plugins.entries.codex?.enabled === false) {
  delete config.plugins.entries.codex;
}
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
NODE
  chown devclaw-svc:devclaw-svc /home/devclaw-svc/.openclaw/openclaw.json
  chmod 0600 /home/devclaw-svc/.openclaw/openclaw.json
}

[[ "$EUID" -eq 0 ]] || fail "Gateway service installation must run as root."

VERSION_FILE="${AGENT_DEVBOX_VERSION_FILE:-/opt/devclaw/config/versions.env}"
[[ -f "$VERSION_FILE" ]] || fail "Missing versions file: $VERSION_FILE"
# shellcheck disable=SC1090
source "$VERSION_FILE"

require_value OPENCLAW_VERSION "$OPENCLAW_VERSION" "2026.7.1"
require_value DEVCLAW_VERSION "$DEVCLAW_VERSION" "1.6.10"
require_value DEVCLAW_COMPAT_REVISION "$DEVCLAW_COMPAT_REVISION" "aiops-1"

command -v node >/dev/null 2>&1 || fail "Missing node."
command -v openssl >/dev/null 2>&1 || fail "Missing openssl."
command -v systemctl >/dev/null 2>&1 || fail "Missing systemctl."
[[ -x /usr/local/bin/openclaw ]] || fail "Missing OpenClaw CLI."
[[ -f /var/lib/devclaw/openclaw-devclaw-installed ]] || fail "DevClaw install marker is missing."

log "Stopping any existing Gateway service or foreground listener"
systemctl stop openclaw-gateway.service >/dev/null 2>&1 || true
pkill -TERM -u devclaw-svc -f 'openclaw.*gateway|openclaw-gatewa|gateway run' >/dev/null 2>&1 || true
sleep 2
pkill -KILL -u devclaw-svc -f 'openclaw.*gateway|openclaw-gatewa|gateway run' >/dev/null 2>&1 || true

log "Ensuring Gateway secret directory"
install -d -o root -g devclaw-broker -m 0750 /var/lib/devclaw/gateway

TOKEN_FILE=/var/lib/devclaw/gateway/openclaw-gateway-token
ENV_FILE=/var/lib/devclaw/gateway/openclaw-gateway.env
if [[ ! -f "$TOKEN_FILE" ]]; then
  umask 0077
  openssl rand -base64 48 | tr -d '\n' > "$TOKEN_FILE"
  printf '\n' >> "$TOKEN_FILE"
fi
chown root:devclaw-broker "$TOKEN_FILE"
chmod 0640 "$TOKEN_FILE"

gateway_token="$(tr -d '\r\n' < "$TOKEN_FILE")"
[[ "${#gateway_token}" -ge 32 ]] || fail "Gateway token is unexpectedly short."

umask 0077
cat > "$ENV_FILE.tmp" <<EOF
HOME=/home/devclaw-svc
XDG_CONFIG_HOME=/home/devclaw-svc/.config
XDG_CACHE_HOME=/home/devclaw-svc/.cache
XDG_DATA_HOME=/home/devclaw-svc/.local/share
OPENCLAW_STATE_DIR=/home/devclaw-svc/.openclaw
OPENCLAW_CONFIG_PATH=/home/devclaw-svc/.openclaw/openclaw.json
OPENCLAW_NO_COLOR=1
OPENCLAW_GATEWAY_TOKEN=${gateway_token}
EOF
install -o root -g devclaw-broker -m 0640 "$ENV_FILE.tmp" "$ENV_FILE"
rm -f "$ENV_FILE.tmp"

log "Configuring OpenClaw safe managed Gateway state"
run_as_devclaw /usr/local/bin/openclaw setup --baseline >/dev/null
STAGE4_MODEL_PROVIDER_ENABLED=false
if [[ -f /var/lib/devclaw/openclaw-gateway-managed ]] &&
  grep -q '^credentials=openai-oauth$' /var/lib/devclaw/openclaw-gateway-managed; then
  STAGE4_MODEL_PROVIDER_ENABLED=true
fi
export STAGE4_MODEL_PROVIDER_ENABLED
write_json_config
run_as_devclaw /usr/local/bin/openclaw plugins registry --refresh >/dev/null

require_value "gateway.mode" "$(run_as_devclaw /usr/local/bin/openclaw config get gateway.mode | tail -n1)" "local"
require_value "gateway.bind" "$(run_as_devclaw /usr/local/bin/openclaw config get gateway.bind | tail -n1)" "loopback"
if [[ "$STAGE4_MODEL_PROVIDER_ENABLED" == "true" ]]; then
  require_value "tools.exec.mode" "$(run_as_devclaw /usr/local/bin/openclaw config get tools.exec.mode | tail -n1)" "auto"
  require_value "tools.exec.strictInlineEval" "$(run_as_devclaw /usr/local/bin/openclaw config get tools.exec.strictInlineEval | tail -n1)" "true"
  require_value "plugins.entries.codex.enabled" "$(run_as_devclaw /usr/local/bin/openclaw config get plugins.entries.codex.enabled | tail -n1)" "true"
else
  require_value "tools.exec.mode" "$(run_as_devclaw /usr/local/bin/openclaw config get tools.exec.mode | tail -n1)" "deny"
fi
require_value "plugins.entries.devclaw.enabled" "$(run_as_devclaw /usr/local/bin/openclaw config get plugins.entries.devclaw.enabled | tail -n1)" "true"
require_value "plugins.entries.devclaw.config.work_heartbeat.enabled" "$(run_as_devclaw /usr/local/bin/openclaw config get plugins.entries.devclaw.config.work_heartbeat.enabled | tail -n1)" "false"
require_value "plugins.entries.devclaw.config.projectExecution" "$(run_as_devclaw /usr/local/bin/openclaw config get plugins.entries.devclaw.config.projectExecution | tail -n1)" "sequential"
node <<'NODE'
const fs = require("fs");
const config = JSON.parse(fs.readFileSync("/home/devclaw-svc/.openclaw/openclaw.json", "utf8"));
const expected = process.env.STAGE4_MODEL_PROVIDER_ENABLED === "true"
  ? ["devclaw", "codex"]
  : ["devclaw"];
if (JSON.stringify(config.plugins?.allow) !== JSON.stringify(expected)) {
  throw new Error(`plugins.allow must be exactly ${JSON.stringify(expected)}`);
}
if (process.env.STAGE4_MODEL_PROVIDER_ENABLED === "true") {
  const model = config.agents?.defaults?.models?.["openai/gpt-5.5"];
  if (model?.agentRuntime?.id !== "codex") {
    throw new Error("openai/gpt-5.5 must use codex agent runtime");
  }
}
NODE

log "Installing systemd service"
cat > /etc/systemd/system/openclaw-gateway.service <<'EOF'
[Unit]
Description=OpenClaw Gateway for Agent DevBox
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=devclaw-svc
Group=devclaw-svc
SupplementaryGroups=devclaw-broker
WorkingDirectory=/home/devclaw-svc
EnvironmentFile=/var/lib/devclaw/gateway/openclaw-gateway.env
ExecStart=/usr/local/bin/openclaw gateway run --port 18789 --auth token --bind loopback --verbose
Restart=on-failure
RestartSec=5s
UMask=0077
NoNewPrivileges=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF
chown root:root /etc/systemd/system/openclaw-gateway.service
chmod 0644 /etc/systemd/system/openclaw-gateway.service

marker_tmp="$(mktemp /var/lib/devclaw/.openclaw-gateway-managed.XXXXXX)"
cat > "$marker_tmp" <<EOF
gateway_managed=true
gateway_service=openclaw-gateway.service
gateway_port=18789
gateway_bind=loopback
gateway_auth=token
plugins_allow=$([[ "$STAGE4_MODEL_PROVIDER_ENABLED" == "true" ]] && printf 'devclaw,codex' || printf 'devclaw')
devclaw_enabled=true
devclaw_heartbeat=false
tools_exec_mode=$([[ "$STAGE4_MODEL_PROVIDER_ENABLED" == "true" ]] && printf 'auto' || printf 'deny')
credentials=$([[ "$STAGE4_MODEL_PROVIDER_ENABLED" == "true" ]] && printf 'openai-oauth' || printf 'not-configured')
EOF
if [[ "$STAGE4_MODEL_PROVIDER_ENABLED" == "true" ]]; then
  cat >> "$marker_tmp" <<'EOF'
model_provider=openai
model_auth=oauth
model_default=openai/gpt-5.5
EOF
fi
chown devclaw-svc:devclaw-svc "$marker_tmp"
chmod 0640 "$marker_tmp"
mv -f "$marker_tmp" /var/lib/devclaw/openclaw-gateway-managed

systemctl daemon-reload
systemctl enable openclaw-gateway.service >/dev/null
systemctl start openclaw-gateway.service

log "Managed Gateway service installed and started."
/opt/devclaw/bin/validate-openclaw-gateway.sh
