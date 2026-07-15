#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

fail() {
  printf '[install-github-app-broker] ERROR: %s\n' "$*" >&2
  exit 1
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "Missing required environment variable: $name"
}

require_value() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  [[ "$actual" == "$expected" ]] || fail "$name must be $expected; found $actual."
}

[[ "$EUID" -eq 0 ]] || fail "GitHub broker installation must run as root."

for name in \
  DEVCLAW_GITHUB_APP_ID \
  DEVCLAW_GITHUB_INSTALLATION_ID \
  DEVCLAW_GITHUB_OWNER \
  DEVCLAW_GITHUB_REPO \
  DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_PROJECT \
  DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_ID; do
  require_env "$name"
done

[[ "$DEVCLAW_GITHUB_OWNER" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "Invalid GitHub owner."
[[ "$DEVCLAW_GITHUB_REPO" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "Invalid GitHub repo."
[[ "$DEVCLAW_GITHUB_APP_ID" =~ ^[0-9]+$ ]] || fail "GitHub App ID must be numeric."
[[ "$DEVCLAW_GITHUB_INSTALLATION_ID" =~ ^[0-9]+$ ]] || fail "GitHub installation ID must be numeric."
[[ "$DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_PROJECT" =~ ^[a-z][a-z0-9-]*$ ]] || fail "Invalid Secret Manager project ID."
[[ "$DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_ID" =~ ^[A-Za-z0-9_-]+$ ]] || fail "Invalid Secret Manager secret ID."

command -v node >/dev/null 2>&1 || fail "Missing node."
command -v curl >/dev/null 2>&1 || fail "Missing curl."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
command -v systemctl >/dev/null 2>&1 || fail "Missing systemctl."

id devclaw-token >/dev/null 2>&1 || fail "Missing devclaw-token user."
id devclaw-svc >/dev/null 2>&1 || fail "Missing devclaw-svc user."
getent group devclaw-broker >/dev/null || fail "Missing devclaw-broker group."

if id -nG devclaw-token | tr ' ' '\n' | grep -qx docker; then
  fail "devclaw-token must not be a member of docker."
fi

install -d -o root -g devclaw-svc -m 0750 /opt/devclaw/bin
install -d -o root -g devclaw-token -m 0750 /opt/devclaw/config
install -d -o devclaw-token -g devclaw-broker -m 0750 /run/devclaw
install -d -o devclaw-token -g devclaw-token -m 0700 /run/secrets/devclaw

if [[ -f /tmp/github-app-token-broker.js ]]; then
  install -o root -g devclaw-token -m 0750 \
    /tmp/github-app-token-broker.js \
    /opt/devclaw/bin/github-app-token-broker.js
else
  chown root:devclaw-token /opt/devclaw/bin/github-app-token-broker.js
  chmod 0750 /opt/devclaw/bin/github-app-token-broker.js
fi

if [[ -f /tmp/github-app-git-credential-helper.sh ]]; then
  install -o root -g devclaw-broker -m 0750 \
    /tmp/github-app-git-credential-helper.sh \
    /opt/devclaw/bin/github-app-git-credential-helper.sh
else
  chown root:devclaw-broker /opt/devclaw/bin/github-app-git-credential-helper.sh
  chmod 0750 /opt/devclaw/bin/github-app-git-credential-helper.sh
fi

cat > /opt/devclaw/config/github-app-broker.env.tmp <<EOF
DEVCLAW_GITHUB_APP_ID=${DEVCLAW_GITHUB_APP_ID}
DEVCLAW_GITHUB_INSTALLATION_ID=${DEVCLAW_GITHUB_INSTALLATION_ID}
DEVCLAW_GITHUB_OWNER=${DEVCLAW_GITHUB_OWNER}
DEVCLAW_GITHUB_REPO=${DEVCLAW_GITHUB_REPO}
DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_PROJECT=${DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_PROJECT}
DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_ID=${DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_ID}
DEVCLAW_GITHUB_BROKER_SOCKET=/run/devclaw/github-token-broker.sock
EOF
install -o root -g devclaw-token -m 0640 \
  /opt/devclaw/config/github-app-broker.env.tmp \
  /opt/devclaw/config/github-app-broker.env
rm -f /opt/devclaw/config/github-app-broker.env.tmp

cat > /etc/systemd/system/devclaw-github-token-broker.service <<'EOF'
[Unit]
Description=DevClaw GitHub App installation token broker
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=devclaw-token
Group=devclaw-broker
SupplementaryGroups=devclaw-token
EnvironmentFile=/opt/devclaw/config/github-app-broker.env
ExecStart=/usr/bin/node /opt/devclaw/bin/github-app-token-broker.js
Restart=on-failure
RestartSec=5s
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/run/devclaw
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF
chown root:root /etc/systemd/system/devclaw-github-token-broker.service
chmod 0644 /etc/systemd/system/devclaw-github-token-broker.service

marker_tmp="$(mktemp /var/lib/devclaw/.github-app-broker-configured.XXXXXX)"
cat > "$marker_tmp" <<EOF
github_app_broker=true
github_owner=${DEVCLAW_GITHUB_OWNER}
github_repo=${DEVCLAW_GITHUB_REPO}
github_app_id=${DEVCLAW_GITHUB_APP_ID}
github_installation_id=${DEVCLAW_GITHUB_INSTALLATION_ID}
private_key_secret_project=${DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_PROJECT}
private_key_secret_id=${DEVCLAW_GITHUB_PRIVATE_KEY_SECRET_ID}
permissions=contents:write,issues:write,pull_requests:write,metadata:read
token_storage=memory-only
git_credential_helper=/opt/devclaw/bin/github-app-git-credential-helper.sh
EOF
chown devclaw-token:devclaw-broker "$marker_tmp"
chmod 0640 "$marker_tmp"
mv -f "$marker_tmp" /var/lib/devclaw/github-app-broker-configured

systemctl daemon-reload
systemctl enable devclaw-github-token-broker.service >/dev/null
systemctl restart devclaw-github-token-broker.service
sleep 3

require_value "broker service active" "$(systemctl is-active devclaw-github-token-broker.service)" "active"
require_value "broker socket owner" "$(stat -c '%U:%G' /run/devclaw/github-token-broker.sock)" "devclaw-token:devclaw-broker"
require_value "broker socket mode" "$(stat -c '%a' /run/devclaw/github-token-broker.sock)" "660"

/opt/devclaw/bin/validate-github-app-broker.sh --offline
