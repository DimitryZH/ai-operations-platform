#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

fail() {
  printf '[validate-openclaw-devclaw] ERROR: %s\n' "$*" >&2
  exit 1
}

run_as_devclaw() {
  runuser -u devclaw-svc -- env \
    HOME=/home/devclaw-svc \
    XDG_CONFIG_HOME=/home/devclaw-svc/.config \
    XDG_CACHE_HOME=/home/devclaw-svc/.cache \
    XDG_DATA_HOME=/home/devclaw-svc/.local/share \
    OPENCLAW_NO_COLOR=1 \
    "$@"
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

normalize_cli_value() {
  sed -E 's/^\s+|\s+$//g; s/^"//; s/"$//'
}

config_get() {
  run_as_devclaw openclaw config get "$1" | normalize_cli_value | tail -n1
}

plugin_json_value() {
  local expr="$1"
  jq -r "$expr" /tmp/devclaw-plugin-inspect.json
}

VERSION_FILE="${AGENT_DEVBOX_VERSION_FILE:-/opt/devclaw/config/versions.env}"
[[ -f "$VERSION_FILE" ]] || fail "Missing versions file: $VERSION_FILE"
# shellcheck disable=SC1090
source "$VERSION_FILE"

require_value OPENCLAW_VERSION "$OPENCLAW_VERSION" "2026.7.1"
require_value DEVCLAW_VERSION "$DEVCLAW_VERSION" "1.6.10"
require_value OPENCLAW_PACKAGE "$OPENCLAW_PACKAGE" "openclaw"
require_value DEVCLAW_PACKAGE "$DEVCLAW_PACKAGE" "@laurentenhoor/devclaw"

command -v openclaw >/dev/null 2>&1 || fail "Missing openclaw binary."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
[[ -x /opt/devclaw/runtime/npm/bin/openclaw ]] || fail "Missing controlled OpenClaw executable."
[[ "$(readlink -f /usr/local/bin/openclaw)" == "/opt/devclaw/runtime/npm/bin/openclaw" ]] ||
  fail "/usr/local/bin/openclaw must point to the controlled prefix."

require_value "OpenClaw prefix owner" "$(stat -c '%U:%G' /opt/devclaw/runtime/npm)" "root:devclaw-svc"
if [[ "$(stat -c '%A' /opt/devclaw/runtime/npm | cut -c6)" == "w" ]]; then
  fail "OpenClaw prefix must not be group-writable."
fi
if run_as_devclaw test -w /opt/devclaw/runtime/npm; then
  fail "devclaw-svc must not be able to modify the OpenClaw package prefix."
fi

actual_openclaw="$(openclaw --version | grep -Eo '[0-9]{4}\.[0-9]+\.[0-9]+' | head -n1)"
require_value "OpenClaw version" "$actual_openclaw" "$OPENCLAW_VERSION"

npm list --global --prefix /opt/devclaw/runtime/npm --depth=0 "${OPENCLAW_PACKAGE}@${OPENCLAW_VERSION}" >/dev/null ||
  fail "Pinned OpenClaw package is not installed in the controlled prefix."

run_as_devclaw openclaw plugins list --json >/tmp/devclaw-plugins-list.json
run_as_devclaw openclaw plugins inspect devclaw --json >/tmp/devclaw-plugin-inspect.json

devclaw_version="$(plugin_json_value '.version // .package.version // .manifest.version // .meta.version // empty')"
require_value "DevClaw version" "$devclaw_version" "$DEVCLAW_VERSION"

devclaw_id="$(plugin_json_value '.id // .manifest.id // .plugin.id // empty')"
require_value "DevClaw plugin id" "$devclaw_id" "devclaw"

require_value "gateway.bind" "$(config_get gateway.bind)" "loopback"
require_value "tools.exec.mode" "$(config_get tools.exec.mode)" "deny"
require_value "plugins.entries.devclaw.enabled" "$(config_get plugins.entries.devclaw.enabled)" "false"
require_value "plugins.entries.devclaw.config.work_heartbeat.enabled" "$(config_get plugins.entries.devclaw.config.work_heartbeat.enabled)" "false"
require_value "plugins.entries.devclaw.config.projectExecution" "$(config_get plugins.entries.devclaw.config.projectExecution)" "sequential"

if systemctl list-unit-files 2>/dev/null | grep -Eiq 'openclaw|devclaw|gateway'; then
  fail "Unexpected system gateway/OpenClaw/DevClaw service is installed."
fi
if systemctl list-units --type=service --all 2>/dev/null | grep -Eiq 'openclaw|devclaw|gateway'; then
  fail "Unexpected system gateway/OpenClaw/DevClaw service exists."
fi
if run_as_devclaw systemctl --user list-unit-files 2>/dev/null | grep -Eiq 'openclaw|devclaw|gateway'; then
  fail "Unexpected user gateway/OpenClaw/DevClaw service is installed."
fi

if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)(127\.0\.0\.1|0\.0\.0\.0|\[::\]|::1)?:18789$|:18789$'; then
  fail "Unexpected listener on TCP 18789."
fi

for name in GH_TOKEN GITHUB_TOKEN OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY; do
  require_absent_env "$name"
done

for user_name in root devclaw-svc devclaw-token devclaw-validate; do
  home_dir="$(getent passwd "$user_name" | cut -d: -f6)"
  [[ -n "$home_dir" ]] || continue
  [[ ! -f "$home_dir/.config/gh/hosts.yml" ]] || fail "GitHub CLI auth exists for $user_name."
  [[ ! -f "$home_dir/.git-credentials" ]] || fail "Git credentials exist for $user_name."
  [[ ! -f "$home_dir/.netrc" ]] || fail "netrc credentials exist for $user_name."
done

if run_as_devclaw gh auth status >/dev/null 2>&1; then
  fail "GitHub CLI is authenticated for devclaw-svc."
fi

if find /workspace/repos -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  fail "/workspace/repos must remain empty."
fi

if find /var/lib/devclaw/projects -mindepth 1 -print -quit | grep -q .; then
  fail "No DevClaw projects may be registered in /var/lib/devclaw/projects."
fi

if find /home/devclaw-svc/.openclaw -type f \( -name '*projects*.json' -o -name 'projects.json' \) -print -quit 2>/dev/null | grep -q .; then
  fail "No OpenClaw projects.json registration is allowed."
fi

REQUIRE_INSTALLED_MARKER="${REQUIRE_INSTALLED_MARKER:-true}"
if [[ "$REQUIRE_INSTALLED_MARKER" == "true" ]]; then
  [[ -f /var/lib/devclaw/openclaw-devclaw-installed ]] || fail "Missing installed marker."
  require_value "installed marker owner" "$(stat -c '%U:%G' /var/lib/devclaw/openclaw-devclaw-installed)" "devclaw-svc:devclaw-svc"
  require_value "installed marker mode" "$(stat -c '%a' /var/lib/devclaw/openclaw-devclaw-installed)" "640"
  grep -q "^openclaw_version=${OPENCLAW_VERSION}$" /var/lib/devclaw/openclaw-devclaw-installed ||
    fail "Installed marker OpenClaw version mismatch."
  grep -q "^devclaw_version=${DEVCLAW_VERSION}$" /var/lib/devclaw/openclaw-devclaw-installed ||
    fail "Installed marker DevClaw version mismatch."
  grep -q '^activation=disabled$' /var/lib/devclaw/openclaw-devclaw-installed ||
    fail "Installed marker must keep activation disabled."
  grep -q '^credentials=not-configured$' /var/lib/devclaw/openclaw-devclaw-installed ||
    fail "Installed marker must record credentials as not configured."
fi

printf '[validate-openclaw-devclaw] Cold plugin installation and configuration validated. Live Gateway plugin loading not yet validated.\n'
