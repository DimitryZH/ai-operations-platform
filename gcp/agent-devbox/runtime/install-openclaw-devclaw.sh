#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

fail() {
  printf '[install-openclaw-devclaw] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[install-openclaw-devclaw] %s\n' "$*"
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

json_value() {
  local file="$1"
  local expr="$2"
  jq -r "$expr" "$file"
}

verify_npm_metadata() {
  local spec="$1"
  local expected_name="$2"
  local expected_version="$3"
  local output_file
  output_file="$(mktemp)"
  npm view "$spec" name version dist.tarball dist.integrity engines peerDependencies --json > "$output_file"
  require_value "$expected_name npm name" "$(json_value "$output_file" '.name')" "$expected_name"
  require_value "$expected_name npm version" "$(json_value "$output_file" '.version')" "$expected_version"
  json_value "$output_file" '."dist.tarball"' | grep -Eq '^https://registry\.npmjs\.org/' ||
    fail "$spec tarball must resolve to the official npm registry."
  [[ -n "$(json_value "$output_file" '."dist.integrity" // ""')" ]] ||
    fail "$spec must include npm integrity metadata."
  rm -f "$output_file"
}

installed_openclaw_version() {
  if [[ -x /opt/devclaw/runtime/npm/bin/openclaw ]]; then
    /opt/devclaw/runtime/npm/bin/openclaw --version 2>/dev/null | grep -Eo '[0-9]{4}\.[0-9]+\.[0-9]+' | head -n1 || true
  elif command -v openclaw >/dev/null 2>&1; then
    openclaw --version 2>/dev/null | grep -Eo '[0-9]{4}\.[0-9]+\.[0-9]+' | head -n1 || true
  fi
}

assert_node_supported_for_openclaw() {
  node <<'NODE'
const [major, minor, patch] = process.versions.node.split(".").map(Number);
const ok =
  (major === 22 && (minor > 22 || (minor === 22 && patch >= 3))) ||
  (major === 24 && (minor > 15 || (minor === 15 && patch >= 0))) ||
  (major === 25 && (minor > 9 || (minor === 9 && patch >= 0))) ||
  major > 25;
if (!ok) {
  console.error(`Node ${process.versions.node} does not satisfy OpenClaw >=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0`);
  process.exit(1);
}
NODE
}

write_installed_marker() {
  local marker_tmp
  marker_tmp="$(mktemp /var/lib/devclaw/.openclaw-devclaw-installed.XXXXXX)"
  cat > "$marker_tmp" <<EOF
openclaw_version=${OPENCLAW_VERSION}
devclaw_version=${DEVCLAW_VERSION}
activation=disabled
credentials=not-configured
EOF
  chown devclaw-svc:devclaw-svc "$marker_tmp"
  chmod 0640 "$marker_tmp"
  mv -f "$marker_tmp" /var/lib/devclaw/openclaw-devclaw-installed
}

normalize_base_marker() {
  [[ -f /var/lib/devclaw/bootstrap-ready ]] || fail "Missing base readiness marker."
  grep -q '^base_prerequisites=installed$' /var/lib/devclaw/bootstrap-ready ||
    fail "Base readiness marker is missing base_prerequisites=installed."

  if grep -q '^base_validation=passed$' /var/lib/devclaw/bootstrap-ready; then
    return
  fi

  grep -q '^openclaw=not-installed$' /var/lib/devclaw/bootstrap-ready ||
    fail "Legacy base readiness marker does not confirm OpenClaw absence."
  grep -q '^devclaw=not-installed$' /var/lib/devclaw/bootstrap-ready ||
    fail "Legacy base readiness marker does not confirm DevClaw absence."
  grep -q '^credentials=not-configured$' /var/lib/devclaw/bootstrap-ready ||
    fail "Legacy base readiness marker does not confirm credential absence."

  local marker_tmp
  marker_tmp="$(mktemp /var/lib/devclaw/.bootstrap-ready.XXXXXX)"
  cat > "$marker_tmp" <<EOF
base_prerequisites=installed
base_validation=passed
EOF
  chown devclaw-svc:devclaw-svc "$marker_tmp"
  chmod 0640 "$marker_tmp"
  mv -f "$marker_tmp" /var/lib/devclaw/bootstrap-ready
}

[[ "$EUID" -eq 0 ]] || fail "Installation script must run as root."

VERSION_FILE="${AGENT_DEVBOX_VERSION_FILE:-/opt/devclaw/config/versions.env}"
[[ -f "$VERSION_FILE" ]] || fail "Missing versions file: $VERSION_FILE"
# shellcheck disable=SC1090
source "$VERSION_FILE"

require_value OPENCLAW_VERSION "$OPENCLAW_VERSION" "2026.7.1"
require_value DEVCLAW_VERSION "$DEVCLAW_VERSION" "1.6.10"
require_value OPENCLAW_PACKAGE "$OPENCLAW_PACKAGE" "openclaw"
require_value DEVCLAW_PACKAGE "$DEVCLAW_PACKAGE" "@laurentenhoor/devclaw"

normalize_base_marker

command -v node >/dev/null 2>&1 || fail "Missing node."
command -v npm >/dev/null 2>&1 || fail "Missing npm."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
assert_node_supported_for_openclaw
npm --version >/dev/null 2>&1 || fail "npm is not usable."

if [[ -f /var/lib/devclaw/openclaw-devclaw-installed ]]; then
  grep -q "^openclaw_version=${OPENCLAW_VERSION}$" /var/lib/devclaw/openclaw-devclaw-installed ||
    fail "Installed marker contains a different OpenClaw version."
  grep -q "^devclaw_version=${DEVCLAW_VERSION}$" /var/lib/devclaw/openclaw-devclaw-installed ||
    fail "Installed marker contains a different DevClaw version."
fi

existing_openclaw="$(installed_openclaw_version)"
if [[ -n "$existing_openclaw" && "$existing_openclaw" != "$OPENCLAW_VERSION" ]]; then
  fail "A different OpenClaw version is already installed: $existing_openclaw."
fi

log "Verifying official npm metadata"
verify_npm_metadata "${OPENCLAW_PACKAGE}@${OPENCLAW_VERSION}" "$OPENCLAW_PACKAGE" "$OPENCLAW_VERSION"
verify_npm_metadata "${DEVCLAW_PACKAGE}@${DEVCLAW_VERSION}" "$DEVCLAW_PACKAGE" "$DEVCLAW_VERSION"

log "Installing pinned OpenClaw into /opt/devclaw/runtime/npm"
install -d -o root -g devclaw-svc -m 0755 /opt/devclaw/runtime/npm
npm install --global --prefix /opt/devclaw/runtime/npm --no-audit --no-fund \
  "${OPENCLAW_PACKAGE}@${OPENCLAW_VERSION}"
chown -R root:devclaw-svc /opt/devclaw/runtime/npm
find /opt/devclaw/runtime/npm -type d -exec chmod 0755 {} +
find /opt/devclaw/runtime/npm -type f -exec chmod go-w {} +
ln -sfn /opt/devclaw/runtime/npm/bin/openclaw /usr/local/bin/openclaw

actual_openclaw="$(installed_openclaw_version)"
require_value "Installed OpenClaw version" "$actual_openclaw" "$OPENCLAW_VERSION"
run_as_devclaw openclaw --version >/dev/null

log "Creating non-interactive OpenClaw baseline"
run_as_devclaw openclaw setup --baseline

log "Enforcing OpenClaw inactive baseline configuration"
run_as_devclaw openclaw config set gateway.bind loopback
run_as_devclaw openclaw config set tools.exec.mode deny

log "Installing pinned DevClaw plugin"
run_as_devclaw openclaw plugins install "${DEVCLAW_PACKAGE}@${DEVCLAW_VERSION}"

log "Enforcing DevClaw inactive safe-mode configuration"
run_as_devclaw openclaw config set plugins.entries.devclaw.enabled false
run_as_devclaw openclaw config set plugins.entries.devclaw.config.work_heartbeat.enabled false
run_as_devclaw openclaw config set plugins.entries.devclaw.config.projectExecution sequential

log "Validating installed state before marker creation"
REQUIRE_INSTALLED_MARKER=false /opt/devclaw/bin/validate-openclaw-devclaw.sh

write_installed_marker

log "Validating installed state with marker present"
/opt/devclaw/bin/validate-runtime.sh
/opt/devclaw/bin/validate-openclaw-devclaw.sh

log "Pinned OpenClaw and DevClaw are installed and configured in inactive safe mode."
