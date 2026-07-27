#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="8"
issue_url="https://github.com/${repo_full}/issues/${issue_id}"
repo="/workspace/repos/application-modernization-lab"
base_branch="main"
channel_id="openclaw-control-ui-main"
session_key="agent:main:subagent:application-modernization-lab-tester-senior-sukey"
session_label="Application Modernization Lab - Tester Sukey (Senior)"
model="openai/gpt-5.5"
worker_name="Sukey"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
result_file="$(dirname "$0")/publish-result.json"

if [[ ! -f "${result_file}" ]]; then
  echo "Missing publish result: ${result_file}" >&2
  exit 1
fi

pr_url="$(jq -r '.prUrl' "${result_file}")"
pr_number="$(jq -r '.prNumber' "${result_file}")"
branch="$(jq -r '.branch' "${result_file}")"
commit="$(jq -r '.commit' "${result_file}")"

if [[ -z "${pr_url}" || "${pr_url}" == "null" ]]; then
  echo "publish-result.json does not contain a PR URL." >&2
  exit 1
fi

set -a
source /var/lib/devclaw/gateway/openclaw-gateway.env
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

api_issue="https://api.github.com/repos/${repo_full}/issues/${issue_id}"
api_get() {
  local url="$1"
  curl --silent --show-error --fail-with-body -K - <<EOF
url = "${url}"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF
}

api_patch() {
  local url="$1"
  local data="$2"
  local payload_file
  payload_file="$(mktemp)"
  printf '%s' "${data}" > "${payload_file}"
  curl --silent --show-error --fail-with-body -X PATCH --data-binary @"${payload_file}" -K - <<EOF
url = "${url}"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF
  rm -f "${payload_file}"
}

issue_json="$(api_get "${api_issue}")"
labels_before="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"

if jq -e 'any(.labels[].name; . == "Validating")' <<<"${issue_json}" >/dev/null; then
  echo "Issue is already in Validating." >&2
  exit 1
fi

runuser -u devclaw-svc -- env \
  HOME=/home/devclaw-svc \
  XDG_CONFIG_HOME=/home/devclaw-svc/.config \
  XDG_CACHE_HOME=/home/devclaw-svc/.cache \
  XDG_DATA_HOME=/home/devclaw-svc/.local/share \
  OPENCLAW_STATE_DIR=/home/devclaw-svc/.openclaw \
  OPENCLAW_CONFIG_PATH=/home/devclaw-svc/.openclaw/openclaw.json \
  OPENCLAW_NO_COLOR=1 \
  OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN}" \
  /usr/local/bin/openclaw gateway call sessions.delete \
    --params "$(jq -nc --arg key "${session_key}" '{key:$key}')" \
    --timeout 10000 \
    --json >/dev/null 2>&1 || true

runuser -u devclaw-svc -- env \
  HOME=/home/devclaw-svc \
  XDG_CONFIG_HOME=/home/devclaw-svc/.config \
  XDG_CACHE_HOME=/home/devclaw-svc/.cache \
  XDG_DATA_HOME=/home/devclaw-svc/.local/share \
  OPENCLAW_STATE_DIR=/home/devclaw-svc/.openclaw \
  OPENCLAW_CONFIG_PATH=/home/devclaw-svc/.openclaw/openclaw.json \
  OPENCLAW_NO_COLOR=1 \
  OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN}" \
  /usr/local/bin/openclaw gateway call sessions.patch \
    --params "$(jq -nc --arg key "${session_key}" --arg model "${model}" --arg label "${session_label}" '{key:$key, model:$model, label:$label}')" \
    --timeout 30000 \
    --json >/dev/null

task_message="$(cat <<EOF
TESTER task for project "${project}" - Issue #${issue_id}

Perform independent validation for Experiment 07A.

Issue: ${issue_url}
PR: ${pr_url}
Branch: ${branch}
Commit: ${commit}

Scope:
- Validate the completed Bank of Anthos Docker Compose baseline under \`experiments/07-bank-of-anthos/01-kubernetes-to-compose/\`.
- Use the issue body, architect report, and human approval comment as the authoritative contract.
- Confirm the PR satisfies the approved architecture and issue acceptance criteria.
- Run the committed validator and perform independent checks as needed.
- Verify no generated JWT keys, credentials, cookies, logs, database dumps, local evidence, unrelated experiment changes, Experiment 07B work, or skill creation are included.
- Do not implement fixes unless explicitly instructed by the workflow.

When you finish, call \`work_finish\` with:
- \`role\`: "tester"
- \`channelId\`: "${channel_id}"
- \`result\`: "pass", "fail", "refine", or "blocked"
- \`summary\`: concise validation result

Repo: ${repo} | Branch: ${base_branch} | ${issue_url}
Project: ${project} | Channel: ${channel_id}
EOF
)"

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "devclaw-${project}-${issue_id}-tester-senior-0-Validation-${session_key}-manual-launch-20260727" \
  --arg prompt "$(cat /home/devclaw-svc/.openclaw/workspace/devclaw/projects/application-modernization-lab/prompts/tester.md)" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent", extraSystemPrompt:$prompt}')"

agent_result="$(
  runuser -u devclaw-svc -- env \
    HOME=/home/devclaw-svc \
    XDG_CONFIG_HOME=/home/devclaw-svc/.config \
    XDG_CACHE_HOME=/home/devclaw-svc/.cache \
    XDG_DATA_HOME=/home/devclaw-svc/.local/share \
    OPENCLAW_STATE_DIR=/home/devclaw-svc/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/devclaw-svc/.openclaw/openclaw.json \
    OPENCLAW_NO_COLOR=1 \
    OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN}" \
    /usr/local/bin/openclaw gateway call agent \
      --params "${agent_params}" \
      --timeout 120000 \
      --json
)"

labels_payload="$(jq -nc '{labels:["Validating","notify:openclaw:primary","owner:Josefina","tester:senior:Sukey","review:human","test:agent"]}')"
issue_after_json="$(
  api_patch "${api_issue}" "${labels_payload}"
)"
labels_after="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_after_json}")"

projects_file="/home/devclaw-svc/.openclaw/workspace/devclaw/projects.json"
projects_tmp="$(mktemp)"
jq \
  --arg project "${project}" \
  --arg issue "${issue_id}" \
  --arg key "${session_key}" \
  --arg now "${now}" \
  --arg name "${worker_name}" \
  '(.projects[] | select(.name==$project).workers.tester.levels.senior[0]) = {
    active: true,
    issueId: $issue,
    sessionKey: $key,
    startTime: $now,
    previousLabel: "Validation",
    name: $name,
    level: "senior"
  }' "${projects_file}" > "${projects_tmp}"
mv "${projects_tmp}" "${projects_file}"
chown devclaw-svc:devclaw-svc "${projects_file}"

mkdir -p /home/devclaw-svc/.openclaw/workspace/devclaw/audit
cat >> /home/devclaw-svc/.openclaw/workspace/devclaw/audit/manual-dispatch.log <<EOF
{"time":"${now}","project":"${project}","issue":${issue_id},"role":"tester","level":"senior","sessionAction":"spawn","sessionKey":"${session_key}","labelTransition":"Refining -> Validating","operator":"codex-recovery","pr":"${pr_url}"}
EOF
chown -R devclaw-svc:devclaw-svc /home/devclaw-svc/.openclaw/workspace/devclaw/audit

jq -nc \
  --arg labelsBefore "${labels_before}" \
  --arg labelsAfter "${labels_after}" \
  --arg sessionKey "${session_key}" \
  --arg prUrl "${pr_url}" \
  --arg prNumber "${pr_number}" \
  --arg agentResult "${agent_result}" \
  '{
    labelsBefore:$labelsBefore,
    labelsAfter:$labelsAfter,
    testerSession:$sessionKey,
    prUrl:$prUrl,
    prNumber:($prNumber|tonumber),
    dispatchAccepted:true,
    gatewayAgentResult:$agentResult
  }'
