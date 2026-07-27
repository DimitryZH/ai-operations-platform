#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="8"
pr_number="9"
branch="issue-8-bank-of-anthos-compose"
pr_url="https://github.com/${repo_full}/pull/${pr_number}"
human_comment_url="https://github.com/${repo_full}/pull/${pr_number}#issuecomment-5094102453"
session_key="agent:main:subagent:application-modernization-lab-tester-senior-sukey"
session_label="Application Modernization Lab - Tester Sukey (Senior)"
model="openai/gpt-5.5"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
prompt_file="${state_dir}/workspace/devclaw/projects/${project}/prompts/tester.md"
projects_file="${state_dir}/workspace/devclaw/projects.json"
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

issue_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}")"
labels_before="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"

comments_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${pr_number}/comments?per_page=100")"
human_comment_present="$(
  jq -r '
    any(.[]; (.html_url // "") == "https://github.com/DimitryZH/application-modernization-lab/pull/9#issuecomment-5094102453" and
      ((.body // "") | contains("one small correction is required before merge")))
  ' <<<"${comments_json}"
)"

if [[ "${human_comment_present}" != "true" ]]; then
  echo "human corrective review comment not found on PR #${pr_number}" >&2
  exit 1
fi

labels_payload="$(jq -nc '{labels:["Refining","notify:openclaw:primary","owner:Josefina","tester:senior:Sukey","test:agent"]}')"
issue_after_json="$(api_patch "https://api.github.com/repos/${repo_full}/issues/${issue_id}" "${labels_payload}")"
labels_after="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_after_json}")"

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

task_message="$(cat <<EOF
TESTER corrective follow-up for project "${project}" - Issue #${issue_id}

Human review accepted the implementation and independent validation overall, but requested one corrective commit before merge.

Authoritative review comment:
${human_comment_url}

PR: ${pr_url}
Branch: ${branch}

Task:
- Make only the two corrections requested in the human review comment:
  1. Strengthen the post-deposit UI validation so it confirms the newly created transaction, amount, or another transaction-specific marker becomes visible through the authenticated application UI, instead of matching only generic page text such as "Transactions" or "Balance".
  2. Correct ".34" to "\$12.34" in "validation-results.md".
- Do not begin Experiment 07B.
- Do not create or propose a skill.
- Do not include JWT keys, credentials, cookies, logs, database dumps, local evidence, or runtime artifacts.
- Rerun the full validator on fresh volumes after the correction.
- Create and push one corrective commit to branch "${branch}".
- Keep the repository's existing primary author and committer identity.
- Include this commit trailer after a blank line:

Co-authored-by: DmitryZhu <zhdm78@gmail.com>

After pushing, post a PR comment with:
- corrective commit SHA;
- validator command and result;
- targeted confirmation that the strengthened post-deposit UI validation now checks transaction-specific evidence.

When finished, call "work_finish" with:
- "role": "tester"
- "channelId": "openclaw-control-ui-main"
- "result": "pass", "fail", "refine", or "blocked"
- "summary": concise corrective result

Repo: /workspace/repos/application-modernization-lab | Branch: main | Issue: ${issue_id}
EOF
)"

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "devclaw-${project}-${issue_id}-tester-corrective-commit-${started_at}" \
  --arg prompt "$(cat "${prompt_file}")" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent", extraSystemPrompt:$prompt}')"

agent_result="$(
  run_as_devclaw /usr/local/bin/openclaw gateway call agent \
    --params "${agent_params}" \
    --timeout 120000 \
    --json
)"

projects_tmp="$(mktemp)"
jq \
  --arg project "${project}" \
  --arg issue "${issue_id}" \
  --arg key "${session_key}" \
  --arg now "${started_at}" \
  '(.projects[] | select(.name==$project).workers.tester.levels.senior[0]) = {
    active: true,
    issueId: $issue,
    sessionKey: $key,
    startTime: $now,
    previousLabel: "Human Review",
    name: "Sukey",
    level: "senior"
  }' "${projects_file}" > "${projects_tmp}"
mv "${projects_tmp}" "${projects_file}"
chown devclaw-svc:devclaw-svc "${projects_file}"

mkdir -p "${state_dir}/workspace/devclaw/audit"
cat >> "${state_dir}/workspace/devclaw/audit/manual-dispatch.log" <<EOF
{"time":"${started_at}","project":"${project}","issue":${issue_id},"role":"tester","level":"senior","sessionAction":"followup","sessionKey":"${session_key}","labelTransition":"Human Review -> Refining","operator":"codex-corrective-followup","pr":"${pr_url}","humanComment":"${human_comment_url}"}
EOF
chown -R devclaw-svc:devclaw-svc "${state_dir}/workspace/devclaw/audit"

unset github_token

jq -nc \
  --arg labelsBefore "${labels_before}" \
  --arg labelsAfter "${labels_after}" \
  --arg sessionKey "${session_key}" \
  --arg humanComment "${human_comment_url}" \
  --arg agentResult "${agent_result}" \
  '{
    labelsBefore:$labelsBefore,
    labelsAfter:$labelsAfter,
    humanComment:$humanComment,
    testerSession:$sessionKey,
    correctiveTaskAccepted:($agentResult | length > 0),
    agentResult:$agentResult
  }'
