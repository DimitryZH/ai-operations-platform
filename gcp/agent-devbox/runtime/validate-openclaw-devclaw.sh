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

require_no_output() {
  local message="$1"
  shift
  local output
  output="$("$@" -print -quit 2>/dev/null || true)"
  [[ -z "$output" ]] || fail "$message: $output"
}

VERSION_FILE="${AGENT_DEVBOX_VERSION_FILE:-/opt/devclaw/config/versions.env}"
[[ -f "$VERSION_FILE" ]] || fail "Missing versions file: $VERSION_FILE"
# shellcheck disable=SC1090
source "$VERSION_FILE"

require_value OPENCLAW_VERSION "$OPENCLAW_VERSION" "2026.7.1"
require_value DEVCLAW_VERSION "$DEVCLAW_VERSION" "1.6.10"
require_value DEVCLAW_COMPAT_REVISION "$DEVCLAW_COMPAT_REVISION" "aiops-1"
require_value OPENCLAW_PACKAGE "$OPENCLAW_PACKAGE" "openclaw"
require_value DEVCLAW_PACKAGE "$DEVCLAW_PACKAGE" "@laurentenhoor/devclaw"

OPENCLAW_NPM_PREFIX=/opt/devclaw/runtime/npm
OPENCLAW_BIN="$OPENCLAW_NPM_PREFIX/bin/openclaw"
OPENCLAW_SYMLINK=/usr/local/bin/openclaw
DEVCLAW_COMPAT_OVERLAY=/opt/devclaw/config/devclaw-manifest-overlay.json
EXPECTED_DEVCLAW_TOOL_COUNT=23
MANAGED_GATEWAY_MARKER=/var/lib/devclaw/openclaw-gateway-managed
stage4_model_provider_enabled=false
if [[ -f "$MANAGED_GATEWAY_MARKER" ]] &&
  grep -q '^credentials=openai-oauth$' "$MANAGED_GATEWAY_MARKER"; then
  stage4_model_provider_enabled=true
fi

command -v openclaw >/dev/null 2>&1 || fail "Missing openclaw binary."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
command -v node >/dev/null 2>&1 || fail "Missing node."
[[ -f "$DEVCLAW_COMPAT_OVERLAY" ]] || fail "Missing DevClaw compatibility overlay."
[[ -L "$OPENCLAW_SYMLINK" ]] || fail "$OPENCLAW_SYMLINK must be a symlink."
literal_target="$(readlink "$OPENCLAW_SYMLINK")" ||
  fail "Cannot read literal OpenClaw symlink target."
require_value "OpenClaw symlink literal target" "$literal_target" "$OPENCLAW_BIN"

[[ -e "$OPENCLAW_BIN" ]] || fail "Missing controlled OpenClaw entry: $OPENCLAW_BIN"
[[ -x "$OPENCLAW_BIN" ]] || fail "Controlled OpenClaw entry is not executable by root: $OPENCLAW_BIN"

canonical_target="$(run_as_devclaw readlink -f "$OPENCLAW_SYMLINK" 2>/tmp/openclaw-readlink-error || true)"
if [[ -z "$canonical_target" ]]; then
  readlink_error="$(cat /tmp/openclaw-readlink-error 2>/dev/null || true)"
  fail "OpenClaw symlink target is configured correctly but cannot be resolved by devclaw-svc; inspect controlled-prefix traversal permissions. ${readlink_error}"
fi
case "$canonical_target" in
  "$OPENCLAW_NPM_PREFIX"/*) ;;
  *) fail "OpenClaw canonical target escaped the controlled prefix: $canonical_target" ;;
esac

require_value "OpenClaw prefix owner" "$(stat -c '%U:%G' "$OPENCLAW_NPM_PREFIX")" "root:devclaw-svc"
if [[ "$(stat -c '%A' "$OPENCLAW_NPM_PREFIX" | cut -c6)" == "w" ]]; then
  fail "OpenClaw prefix must not be group-writable."
fi
require_no_output "OpenClaw prefix contains non-root-owned path" \
  find "$OPENCLAW_NPM_PREFIX" ! -user root
require_no_output "OpenClaw prefix contains path outside devclaw-svc group" \
  find "$OPENCLAW_NPM_PREFIX" ! -group devclaw-svc
require_no_output "OpenClaw prefix grants permissions to others" \
  find "$OPENCLAW_NPM_PREFIX" ! -type l -perm /0007
require_no_output "OpenClaw prefix grants group write permission" \
  find "$OPENCLAW_NPM_PREFIX" ! -type l -perm /0020
require_no_output "OpenClaw prefix contains a directory not traversable by devclaw-svc group" \
  find "$OPENCLAW_NPM_PREFIX" -type d ! -perm -0050
require_no_output "OpenClaw prefix contains a regular file not readable by devclaw-svc group" \
  find "$OPENCLAW_NPM_PREFIX" -type f ! -perm -0040

if run_as_devclaw test -w "$OPENCLAW_NPM_PREFIX"; then
  fail "devclaw-svc must not be able to modify the OpenClaw package prefix."
fi

representative_file="$(find "$OPENCLAW_NPM_PREFIX/lib/node_modules/openclaw" -type f -name package.json -print -quit 2>/dev/null || true)"
[[ -n "$representative_file" ]] || fail "Missing representative OpenClaw package file."
if run_as_devclaw test -w "$representative_file"; then
  fail "devclaw-svc must not be able to modify OpenClaw package files."
fi

openclaw_version_output="$(run_as_devclaw openclaw --version 2>/tmp/openclaw-version-error || true)"
if [[ -z "$openclaw_version_output" ]]; then
  version_error="$(cat /tmp/openclaw-version-error 2>/dev/null || true)"
  fail "OpenClaw symlink resolved but execution as devclaw-svc failed. ${version_error}"
fi
actual_openclaw="$(printf '%s\n' "$openclaw_version_output" | grep -Eo '[0-9]{4}\.[0-9]+\.[0-9]+' | head -n1)"
require_value "OpenClaw version" "$actual_openclaw" "$OPENCLAW_VERSION"

npm list --global --prefix "$OPENCLAW_NPM_PREFIX" --depth=0 "${OPENCLAW_PACKAGE}@${OPENCLAW_VERSION}" >/dev/null ||
  fail "Pinned OpenClaw package is not installed in the controlled prefix."

run_as_devclaw openclaw plugins list --json >/tmp/devclaw-plugins-list.json
run_as_devclaw openclaw plugins inspect devclaw --json >/tmp/devclaw-plugin-inspect.json

devclaw_version="$(plugin_json_value '.plugin.version // .install.version // .version // .package.version // .manifest.version // .meta.version // empty')"
require_value "DevClaw version" "$devclaw_version" "$DEVCLAW_VERSION"

devclaw_id="$(plugin_json_value '.id // .manifest.id // .plugin.id // empty')"
require_value "DevClaw plugin id" "$devclaw_id" "devclaw"

devclaw_root="$(plugin_json_value '.plugin.rootDir // .install.rootDir // .rootDir // empty')"
if [[ -z "$devclaw_root" ]]; then
  devclaw_source="$(plugin_json_value '.plugin.source // .install.source // .source // empty')"
  [[ -n "$devclaw_source" ]] || fail "Cannot determine DevClaw plugin source/root directory."
  devclaw_root="$(dirname "$(dirname "$devclaw_source")")"
fi
devclaw_manifest="$devclaw_root/openclaw.plugin.json"
[[ -f "$devclaw_manifest" ]] || fail "Missing installed DevClaw manifest: $devclaw_manifest"
node - "$devclaw_manifest" "$DEVCLAW_COMPAT_OVERLAY" "$EXPECTED_DEVCLAW_TOOL_COUNT" <<'NODE'
const fs = require("fs");
const [manifestFile, overlayFile, expectedCount] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
const overlay = JSON.parse(fs.readFileSync(overlayFile, "utf8"));
if (manifest.id !== "devclaw") throw new Error(`unexpected plugin id: ${manifest.id}`);
if (manifest.activation?.onStartup !== true) throw new Error("activation.onStartup must be true");
const tools = manifest.contracts?.tools;
if (!Array.isArray(tools)) throw new Error("contracts.tools must be an array");
if (tools.length !== Number(expectedCount)) throw new Error(`expected ${expectedCount} tools, found ${tools.length}`);
if (new Set(tools).size !== tools.length) throw new Error("contracts.tools contains duplicate names");
if (JSON.stringify(tools) !== JSON.stringify(overlay.contracts.tools)) {
  throw new Error("installed contracts.tools does not match reviewed overlay");
}
NODE

require_value "gateway.bind" "$(config_get gateway.bind)" "loopback"
if [[ "$stage4_model_provider_enabled" == "true" ]]; then
  require_value "tools.exec.mode" "$(config_get tools.exec.mode)" "auto"
  require_value "tools.exec.strictInlineEval" "$(config_get tools.exec.strictInlineEval)" "true"
  require_value "tools.exec.commandHighlighting" "$(config_get tools.exec.commandHighlighting)" "true"
else
  require_value "tools.exec.mode" "$(config_get tools.exec.mode)" "deny"
fi
require_value "plugins.entries.devclaw.config.work_heartbeat.enabled" "$(config_get plugins.entries.devclaw.config.work_heartbeat.enabled)" "false"
require_value "plugins.entries.devclaw.config.projectExecution" "$(config_get plugins.entries.devclaw.config.projectExecution)" "sequential"

managed_gateway_enabled=false
if [[ -f "$MANAGED_GATEWAY_MARKER" ]]; then
  managed_gateway_enabled=true
  require_value "plugins.entries.devclaw.enabled" "$(config_get plugins.entries.devclaw.enabled)" "true"
  if [[ "$stage4_model_provider_enabled" == "true" ]]; then
    require_value "plugins.entries.codex.enabled" "$(config_get plugins.entries.codex.enabled)" "true"
  fi
  STAGE4_MODEL_PROVIDER_ENABLED="$stage4_model_provider_enabled" node <<'NODE'
const fs = require("fs");
const config = JSON.parse(fs.readFileSync("/home/devclaw-svc/.openclaw/openclaw.json", "utf8"));
const stage4 = process.env.STAGE4_MODEL_PROVIDER_ENABLED === "true";
const expected = stage4 ? ["devclaw", "codex"] : ["devclaw"];
if (JSON.stringify(config.plugins?.allow) !== JSON.stringify(expected)) {
  throw new Error(`plugins.allow must be exactly ${JSON.stringify(expected)} when managed Gateway is enabled`);
}
if (stage4) {
  const model = config.agents?.defaults?.models?.["openai/gpt-5.5"];
  if (model?.agentRuntime?.id !== "codex") {
    throw new Error("openai/gpt-5.5 must use codex agent runtime");
  }
  if (config.models?.providers?.openai) {
    throw new Error("Stage 4 must not configure a generic OpenAI provider override");
  }
}
NODE
  systemctl is-enabled openclaw-gateway.service >/dev/null ||
    fail "Managed Gateway marker exists, but openclaw-gateway.service is not enabled."
  systemctl is-active openclaw-gateway.service >/dev/null ||
    fail "Managed Gateway marker exists, but openclaw-gateway.service is not active."
else
  require_value "plugins.entries.devclaw.enabled" "$(config_get plugins.entries.devclaw.enabled)" "false"
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

stage6_marker=/var/lib/devclaw/stage6-compose-to-aspire-project-registered
if [[ -f "$stage6_marker" ]]; then
  grep -q '^stage6_project_registered=true$' "$stage6_marker" ||
    fail "Stage 6 marker exists but does not confirm project registration."
  grep -q '^repository=DimitryZH/application-modernization-lab$' "$stage6_marker" ||
    fail "Stage 6 marker references an unexpected repository."
  mapfile -t repo_entries < <(find /workspace/repos -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
  [[ "${#repo_entries[@]}" -eq 1 && "${repo_entries[0]}" == "application-modernization-lab" ]] ||
    fail "/workspace/repos must contain only application-modernization-lab after Stage 6."
  [[ -f /home/devclaw-svc/.openclaw/workspace/devclaw/projects.json ]] ||
    fail "Stage 6 marker exists but DevClaw projects.json is absent."
else
  if find /workspace/repos -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    fail "/workspace/repos must remain empty."
  fi

  if find /var/lib/devclaw/projects -mindepth 1 -print -quit | grep -q .; then
    fail "No DevClaw projects may be registered in /var/lib/devclaw/projects."
  fi

  if find /home/devclaw-svc/.openclaw -type f \( -name '*projects*.json' -o -name 'projects.json' \) -print -quit 2>/dev/null | grep -q .; then
    fail "No OpenClaw projects.json registration is allowed."
  fi
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
  grep -q "^devclaw_compat_revision=${DEVCLAW_COMPAT_REVISION}$" /var/lib/devclaw/openclaw-devclaw-installed ||
    fail "Installed marker DevClaw compatibility revision mismatch."
  grep -q '^activation=disabled$' /var/lib/devclaw/openclaw-devclaw-installed ||
    fail "Installed marker must keep activation disabled."
  grep -q '^credentials=not-configured$' /var/lib/devclaw/openclaw-devclaw-installed ||
    fail "Installed marker must record credentials as not configured."
fi

if [[ "$managed_gateway_enabled" == "true" ]]; then
  printf '[validate-openclaw-devclaw] Installed DevClaw state and managed Gateway guardrails validated. Live loading is covered by validate-openclaw-gateway.sh.\n'
else
  printf '[validate-openclaw-devclaw] Cold plugin installation and configuration validated. Live Gateway plugin loading not yet validated.\n'
fi
