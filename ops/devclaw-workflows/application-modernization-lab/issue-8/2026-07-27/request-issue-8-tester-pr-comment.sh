#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="8"
pr_number="9"
pr_url="https://github.com/${repo_full}/pull/${pr_number}"
session_key="agent:main:subagent:application-modernization-lab-tester-senior-sukey"
session_label="Application Modernization Lab - Tester Sukey (Senior)"
model="openai/gpt-5.5"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
prompt_file="${state_dir}/workspace/devclaw/projects/${project}/prompts/tester.md"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ ! -f "${gateway_env}" ]]; then
  echo "missing gateway env: ${gateway_env}" >&2
  exit 1
fi

if [[ ! -f "${prompt_file}" ]]; then
  echo "missing tester prompt: ${prompt_file}" >&2
  exit 1
fi

set -a
source "${gateway_env}"
set +a

github_token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r '.token // empty'
)"

if [[ -z "${github_token}" ]]; then
  echo "GitHub App broker did not return a token." >&2
  exit 1
fi

api_get() {
  local url="$1"
  curl --silent --show-error --fail-with-body -K - <<EOF
url = "${url}"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF
}

issue_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}")"
labels="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"

run_as_devclaw() {
  runuser -u devclaw-svc -- env \
    HOME=/home/devclaw-svc \
    XDG_CONFIG_HOME=/home/devclaw-svc/.config \
    XDG_CACHE_HOME=/home/devclaw-svc/.cache \
    XDG_DATA_HOME=/home/devclaw-svc/.local/share \
    OPENCLAW_STATE_DIR="${state_dir}" \
    OPENCLAW_CONFIG_PATH="${state_dir}/openclaw.json" \
    OPENCLAW_NO_COLOR=1 \
    OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN}" \
    "$@"
}

run_as_devclaw /usr/local/bin/openclaw gateway call sessions.patch \
  --params "$(jq -nc --arg key "${session_key}" --arg model "${model}" --arg label "${session_label}" '{key:$key, model:$model, label:$label}')" \
  --timeout 30000 \
  --json >/dev/null

followup_message="$(cat <<EOF
TESTER follow-up for project "${project}" - Issue #${issue_id}

You already completed independent validation for Experiment 07A and reported PASS through DevClaw.

Do not re-run validation.
Do not inspect or modify implementation files.
Do not change labels, branches, commits, or PR state.

Post one standalone validation result comment on PR #${pr_number}: ${pr_url}

The comment must clearly identify this as the tester validation result and include:
- result: PASS;
- validated commit: cdffffd0703f13bad9d873ca3ed60e2f1ec9ba04;
- validation covered service identity/readiness, loopback frontend, demo login, deposit flow, ledger persistence across restart, negative ledger-db dependency failure, cleanup, and static forbidden-artifact/scope checks;
- no generated JWT keys, credentials, cookies, logs, database dumps, local evidence, Experiment 07B work, or skill creation were found in tracked changes;
- the PR is ready for human review.

After posting, reply with only the PR comment URL. If you cannot post the comment, reply with only the blocker.
EOF
)"

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${followup_message}" \
  --arg idk "devclaw-${project}-${issue_id}-tester-pr-comment-${started_at}" \
  --arg prompt "$(cat "${prompt_file}")" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent", extraSystemPrompt:$prompt}')"

agent_result="$(
  run_as_devclaw /usr/local/bin/openclaw gateway call agent \
    --params "${agent_params}" \
    --timeout 120000 \
    --json
)"

comment_url=""
for _ in $(seq 1 30); do
  comments_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${pr_number}/comments?since=${started_at}")"
  comment_url="$(
    jq -r '
      map(select((.body // "") | test("(?i)(tester validation|validation result|result:\\s*PASS|validated commit)"))) |
      last |
      .html_url // empty
    ' <<<"${comments_json}"
  )"
  if [[ -n "${comment_url}" ]]; then
    break
  fi
  sleep 10
done

unset github_token

jq -nc \
  --arg labels "${labels}" \
  --arg startedAt "${started_at}" \
  --arg agentResult "${agent_result}" \
  --arg commentUrl "${comment_url}" \
  '{
    issueLabels:$labels,
    testerSession:"agent:main:subagent:application-modernization-lab-tester-senior-sukey",
    followupAccepted:($agentResult | length > 0),
    agentResult:$agentResult,
    commentUrl:($commentUrl | select(length > 0) // null),
    commentObserved:($commentUrl | length > 0),
    startedAt:$startedAt
  }'
