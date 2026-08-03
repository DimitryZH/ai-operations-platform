#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="16"
repo="/workspace/repos/application-modernization-lab"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
projects_file="${state_dir}/workspace/devclaw/projects.json"
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
session_key="agent:main:subagent:application-modernization-lab-architect-senior-zandra"
out_file="${1:-$(dirname "$0")/../results/architect-status-immediate.json}"

fail() {
  printf '[inspect-issue-16-architect-status] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v git >/dev/null 2>&1 || fail "missing git"
command -v jq >/dev/null 2>&1 || fail "missing jq"
command -v curl >/dev/null 2>&1 || fail "missing curl"
[[ -f "${gateway_env}" ]] || fail "missing gateway env: ${gateway_env}"
[[ -f "${projects_file}" ]] || fail "missing projects.json: ${projects_file}"

set -a
source "${gateway_env}"
set +a

github_token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r '.token // empty'
)"
[[ -n "${github_token}" ]] || fail "GitHub App broker did not return a token"

api_get() {
  local url="$1"
  curl --silent --show-error --fail-with-body -K - <<EOF_CURL
url = "${url}"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
}

issue="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}")"
comments="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments?per_page=100")"
prs="$(api_get "https://api.github.com/repos/${repo_full}/pulls?state=open&per_page=100")"
worker="$(
  jq -c --arg project "${project}" \
    '.projects[] | select(.name==$project).workers.architect.levels.senior[0]' \
    "${projects_file}"
)"
session="$(
  if [[ -f "${sessions_file}" ]]; then
    jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
)"
repo_status="$(runuser -u devclaw-svc -- git -C "${repo}" status --porcelain=v1)"
repo_branch="$(runuser -u devclaw-svc -- git -C "${repo}" branch --show-current)"
repo_head="$(runuser -u devclaw-svc -- git -C "${repo}" rev-parse HEAD)"

mkdir -p "$(dirname "${out_file}")"
jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson issue "${issue}" \
  --argjson comments "${comments}" \
  --argjson prs "${prs}" \
  --argjson worker "${worker}" \
  --argjson session "${session}" \
  --arg repoStatus "${repo_status}" \
  --arg repoBranch "${repo_branch}" \
  --arg repoHead "${repo_head}" \
  '{
    checkedAt:$checkedAt,
    issue: {
      number: $issue.number,
      state: $issue.state,
      labels: [$issue.labels[].name],
      updatedAt: $issue.updated_at,
      comments: $issue.comments
    },
    architectWorker: $worker,
    architectSession: $session,
    repo: {
      branch: $repoBranch,
      head: $repoHead,
      clean: ($repoStatus == ""),
      status: $repoStatus
    },
    openPrs: (
      $prs | map({
        number,
        title,
        head: .head.ref,
        url: .html_url,
        createdAt: .created_at,
        updatedAt: .updated_at
      })
    ),
    latestComments: (
      $comments |
      map({
        user: .user.login,
        createdAt: .created_at,
        bodyFirstLines: (.body | split("\n") | .[0:10] | join("\n"))
      }) |
      .[-5:]
    )
  }' | tee "${out_file}"
