#!/usr/bin/env bash
set -euo pipefail

state_dir=/home/devclaw-svc/.openclaw
project=application-modernization-lab
repo=/workspace/repos/application-modernization-lab
session_key=agent:main:subagent:application-modernization-lab-tester-senior-sukey

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
pr="$(api_get https://api.github.com/repos/DimitryZH/application-modernization-lab/pulls/11)"
worker="$(
  jq -c --arg project "${project}" \
    '.projects[] | select(.name==$project).workers.tester.levels.senior[0]' \
    "${state_dir}/workspace/devclaw/projects.json"
)"
session="$(
  jq -c --arg key "${session_key}" '.[$key] // null' \
    "${state_dir}/agents/main/sessions/sessions.json" 2>/dev/null || echo null
)"
repo_status="$(runuser -u devclaw-svc -- git -C "${repo}" status --porcelain=v1)"
repo_branch="$(runuser -u devclaw-svc -- git -C "${repo}" branch --show-current)"
repo_head="$(runuser -u devclaw-svc -- git -C "${repo}" rev-parse HEAD)"

jq -n \
  --argjson issue "${issue}" \
  --argjson comments "${comments}" \
  --argjson pr "${pr}" \
  --argjson worker "${worker}" \
  --argjson session "${session}" \
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
    pr: {
      state: $pr.state,
      head: $pr.head.ref,
      sha: $pr.head.sha,
      url: $pr.html_url,
      merged: ($pr.merged // false)
    },
    worker: $worker,
    session: {
      status: $session.status,
      sessionId: $session.sessionId,
      updatedAt: $session.updatedAt,
      sessionFile: $session.sessionFile,
      skills: ($session.skillsSnapshot.skills // [] | map(.name))
    },
    repo: {
      branch: $repoBranch,
      head: $repoHead,
      status: $repoStatus
    },
    latestComments: (
      $comments |
      map({
        user: .user.login,
        createdAt: .created_at,
        body: (.body | split("\n") | .[0:16] | join("\n"))
      }) |
      .[-8:]
    )
  }'
