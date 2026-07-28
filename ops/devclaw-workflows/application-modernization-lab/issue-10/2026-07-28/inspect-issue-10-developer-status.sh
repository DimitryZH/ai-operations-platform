#!/usr/bin/env bash
set -euo pipefail

state_dir=/home/devclaw-svc/.openclaw
project=application-modernization-lab
repo=/workspace/repos/application-modernization-lab

token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r .token
)"

api_get() {
  local url="$1"
  curl --silent --show-error --fail \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    "${url}"
}

issue="$(api_get https://api.github.com/repos/DimitryZH/application-modernization-lab/issues/10)"
comments="$(api_get 'https://api.github.com/repos/DimitryZH/application-modernization-lab/issues/10/comments?per_page=100')"
prs="$(api_get 'https://api.github.com/repos/DimitryZH/application-modernization-lab/pulls?state=open&per_page=100')"
worker="$(
  jq -c --arg project "${project}" \
    '.projects[] | select(.name==$project).workers.developer.levels.senior[0]' \
    "${state_dir}/workspace/devclaw/projects.json"
)"
repo_status="$(runuser -u devclaw-svc -- git -C "${repo}" status --porcelain=v1)"
repo_branch="$(runuser -u devclaw-svc -- git -C "${repo}" branch --show-current)"
repo_head="$(runuser -u devclaw-svc -- git -C "${repo}" rev-parse HEAD)"

jq -n \
  --argjson issue "${issue}" \
  --argjson comments "${comments}" \
  --argjson prs "${prs}" \
  --argjson worker "${worker}" \
  --arg repoStatus "${repo_status}" \
  --arg repoBranch "${repo_branch}" \
  --arg repoHead "${repo_head}" \
  '{
    issue: {
      state: $issue.state,
      labels: [$issue.labels[].name],
      updatedAt: $issue.updated_at,
      comments: $issue.comments
    },
    worker: $worker,
    repo: {
      branch: $repoBranch,
      head: $repoHead,
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
        body: (.body | split("\n") | .[0:14] | join("\n"))
      }) |
      .[-6:]
    )
  }'
