#!/usr/bin/env bash
set -euo pipefail

repo="/workspace/repos/application-modernization-lab"
branch="experiment-08/aks-store-aspire-migration"

token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r '.token // empty'
)"
[[ -n "${token}" ]] || { echo "missing GitHub token" >&2; exit 1; }

cd "${repo}"
askpass="$(mktemp)"
cat > "${askpass}" <<'EOF_ASKPASS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "x-access-token" ;;
  *Password*) printf '%s\n' "${GITHUB_TOKEN}" ;;
  *) printf '\n' ;;
esac
EOF_ASKPASS
chmod 0700 "${askpass}"
trap 'rm -f "${askpass}"' EXIT

GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="${askpass}" GITHUB_TOKEN="${token}" \
  git -c credential.helper= push origin "HEAD:${branch}"
git rev-parse HEAD
