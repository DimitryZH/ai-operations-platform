#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
issue_id="16"

token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r '.token // empty'
)"
[[ -n "${token}" ]] || { echo "missing GitHub token" >&2; exit 1; }

curl --silent --show-error --fail \
  -H "Authorization: Bearer ${token}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments?per_page=100" |
  jq -r '.[-8:][] | "---COMMENT---\nID: \(.id)\nUSER: \(.user.login)\nCREATED: \(.created_at)\nBODY:\n\(.body)\n"'
