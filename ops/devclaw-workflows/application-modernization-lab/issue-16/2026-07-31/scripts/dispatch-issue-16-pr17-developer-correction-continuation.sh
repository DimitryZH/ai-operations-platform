#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="16"
pr_id="17"
issue_url="https://github.com/${repo_full}/issues/${issue_id}"
pr_url="https://github.com/${repo_full}/pull/${pr_id}"
repo="/workspace/repos/application-modernization-lab"
implementation_branch="experiment-08/aks-store-aspire-migration"
expected_head="6722ff491c2a9053a9f76b4bb9223b64f3ec6b3b"
channel_id="openclaw-control-ui-main"
session_suffix="$(date -u +%Y%m%dt%H%M%Sz)"
session_key="agent:main:subagent:application-modernization-lab-developer-senior-ara-issue-16-pr17-continuation-${session_suffix}"
session_label="Application Modernization Lab - Developer Ara (Senior Issue 16 PR17 Continuation ${session_suffix})"
model="openai/gpt-5.5"
worker_name="Ara"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
prompt_file="${state_dir}/workspace/devclaw/projects/${project}/prompts/developer.md"
projects_file="${state_dir}/workspace/devclaw/projects.json"
workflow_file="${state_dir}/workspace/devclaw/projects/${project}/workflow.yaml"
boundary_file="${state_dir}/workspace/devclaw/stage6-boundary.json"
root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31"
preserve_latest_file="${root}/correction-recovery/latest-preserve-worktree-dir.txt"
capability_file="${root}/correction-recovery/execution-capability-current.json"
out_file="${1:-${root}/results/developer-correction-pr17-continuation-dispatch-result.json}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

fail() {
  printf '[dispatch-issue-16-pr17-developer-correction-continuation] ERROR: %s\n' "$*" >&2
  exit 1
}

run_as_devclaw() {
  runuser -u devclaw-svc -- env \
    HOME=/home/devclaw-svc \
    XDG_CONFIG_HOME=/home/devclaw-svc/.config \
    XDG_CACHE_HOME=/home/devclaw-svc/.cache \
    XDG_DATA_HOME=/home/devclaw-svc/.local/share \
    OPENCLAW_STATE_DIR="${state_dir}" \
    OPENCLAW_CONFIG_PATH="${state_dir}/openclaw.json" \
    OPENCLAW_NO_COLOR=1 \
    OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}" \
    "$@"
}

config_get() {
  run_as_devclaw /usr/local/bin/openclaw config get "$1" |
    sed -E 's/^\s+|\s+$//g; s/^"//; s/"$//' |
    tail -n1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v git >/dev/null 2>&1 || fail "missing git"
command -v jq >/dev/null 2>&1 || fail "missing jq"
command -v curl >/dev/null 2>&1 || fail "missing curl"
[[ -d "${repo}/.git" ]] || fail "missing repository checkout"
[[ -f "${gateway_env}" ]] || fail "missing gateway env"
[[ -f "${prompt_file}" ]] || fail "missing developer prompt"
[[ -f "${projects_file}" ]] || fail "missing projects.json"
[[ -f "${workflow_file}" ]] || fail "missing workflow"
[[ -f "${boundary_file}" ]] || fail "missing stage boundary"
[[ -f "${preserve_latest_file}" ]] || fail "missing preserve snapshot pointer"
[[ -f "${capability_file}" ]] || fail "missing capability preflight result"
[[ -S /run/devclaw/github-token-broker.sock ]] || fail "missing GitHub token broker socket"

set -a
# shellcheck disable=SC1090
source "${gateway_env}"
set +a

preserve_dir="$(cat "${preserve_latest_file}")"
[[ -d "${preserve_dir}" ]] || fail "preserve snapshot directory missing: ${preserve_dir}"
jq -e '.capabilityOk == true' "${capability_file}" >/dev/null || fail "capability preflight did not pass"

[[ "$(systemctl is-active openclaw-gateway.service)" == "active" ]] ||
  fail "openclaw-gateway.service is not active"
[[ "$(systemctl is-active devclaw-github-token-broker.service)" == "active" ]] ||
  fail "devclaw-github-token-broker.service is not active"

gateway_status="$(run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000)"
[[ "$(jq -r '.tasks.active // -1' <<<"${gateway_status}")" == "0" ]] || fail "Gateway has active tasks"

branch="$(run_as_devclaw git -C "${repo}" branch --show-current)"
head="$(run_as_devclaw git -C "${repo}" rev-parse HEAD)"
[[ "${branch}" == "${implementation_branch}" ]] || fail "repo branch must be ${implementation_branch}; found ${branch}"
[[ "${head}" == "${expected_head}" ]] || fail "repo HEAD must remain expected starting head ${expected_head}; found ${head}"

[[ "$(config_get plugins.entries.devclaw.config.work_heartbeat.enabled)" == "false" ]] ||
  fail "DevClaw heartbeat must remain disabled"
[[ "$(config_get plugins.entries.devclaw.config.projectExecution)" == "sequential" ]] ||
  fail "DevClaw execution must remain sequential"
[[ "$(config_get skills.workshop.autonomous.enabled)" == "false" ]] ||
  fail "Skill Workshop autonomous behavior must remain disabled"
[[ "$(config_get skills.workshop.approvalPolicy)" == "pending" ]] ||
  fail "Skill Workshop approvalPolicy must remain pending"
grep -q 'reviewPolicy: human' "${workflow_file}" || fail "workflow must keep human review policy"
grep -q 'roleExecution: sequential' "${workflow_file}" || fail "workflow must keep sequential role execution"
if grep -R -nE '\bmergePr\b|\bgitPull\b|\bcloseIssue\b' "${workflow_file}" >/dev/null; then
  fail "workflow contains automatic merge/pull/issue-close action"
fi
jq -e '
  .automaticMergeEnabled == false and
  .heartbeatEnabled == false and
  .skillWorkshop.autonomousEnabled == false and
  .skillWorkshop.approvalPolicy == "pending"
' "${boundary_file}" >/dev/null || fail "stage boundary must keep auto-merge, heartbeat, and autonomous Skill Workshop disabled"

github_token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r '.token // empty'
)"
[[ -n "${github_token}" ]] || fail "GitHub token broker did not return a token"

api_get() {
  local url="$1"
  curl --silent --show-error --fail-with-body -K - <<EOF_CURL
url = "${url}"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
}

api_patch() {
  local url="$1"
  local data="$2"
  local payload_file
  payload_file="$(mktemp)"
  printf '%s' "${data}" > "${payload_file}"
  curl --silent --show-error --fail-with-body -X PATCH --data-binary @"${payload_file}" -K - <<EOF_CURL
url = "${url}"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
  rm -f "${payload_file}"
}

issue_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}")"
pr_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_id}")"
labels_before="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"
pr_head_sha="$(jq -r '.head.sha' <<<"${pr_json}")"
pr_draft="$(jq -r '.draft' <<<"${pr_json}")"
[[ "${pr_head_sha}" == "${expected_head}" ]] || fail "remote PR head changed: ${pr_head_sha}"
[[ "${pr_draft}" == "true" ]] || fail "PR #17 must remain draft"

state_labels='[
  "Planning",
  "Source and Architecture Research",
  "Aspire Architecture Research",
  "Architecture Research",
  "Researching",
  "Human Baseline Approval",
  "Human Architecture Approval",
  "Implementation",
  "Implementing",
  "Validation",
  "Validating",
  "Human Review",
  "Knowledge Review",
  "Done",
  "Rejected",
  "To Improve",
  "Refining",
  "Agent Review Disabled"
]'
labels_payload="$(
  jq -nc --argjson issue "${issue_json}" --argjson stateLabels "${state_labels}" '
    {
      labels: (
        ([ $issue.labels[].name ] - $stateLabels - ["architect:junior", "architect:senior", "developer:junior", "developer:medior", "developer:senior", "tester:junior", "tester:medior", "tester:senior"]) +
        ["Refining", "notify:openclaw:primary", "owner:Josefina", "developer:senior", "review:human"]
        | unique
      )
    }'
)"
issue_after_json="$(api_patch "https://api.github.com/repos/${repo_full}/issues/${issue_id}" "${labels_payload}")"
labels_after="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_after_json}")"

projects_tmp="$(mktemp)"
jq \
  --arg project "${project}" \
  --arg issue "${issue_id}" \
  --arg key "${session_key}" \
  --arg now "${started_at}" \
  --arg name "${worker_name}" \
  '(.projects[] | select(.name==$project).workers.developer.levels.senior[0]) = {
    active: true,
    issueId: $issue,
    sessionKey: $key,
    startTime: $now,
    previousLabel: "Refining",
    name: $name,
    level: "senior",
    continuationFor: "PR #17 correction recovery",
    expectedStartingHead: "6722ff491c2a9053a9f76b4bb9223b64f3ec6b3b"
  }' "${projects_file}" > "${projects_tmp}"
mv "${projects_tmp}" "${projects_file}"
chown devclaw-svc:devclaw-svc "${projects_file}"

run_as_devclaw /usr/local/bin/openclaw gateway call sessions.patch \
  --params "$(jq -nc --arg key "${session_key}" --arg model "${model}" --arg label "${session_label}" '{key:$key, model:$model, label:$label}')" \
  --timeout 30000 \
  --json >/dev/null

task_message="$(cat <<EOF_MESSAGE
SENIOR DEVELOPER continuation task for issue #${issue_id}, draft PR #${pr_id}

Repository: ${repo_full}
Issue: ${issue_url}
Draft PR: ${pr_url}
Repo checkout: ${repo}
Existing branch: ${implementation_branch}
Expected remote PR head before correction: ${expected_head}
Recovery snapshot: ${preserve_dir}
Capability preflight result: ${capability_file}
Channel: ${channel_id}

Continue the existing targeted developer correction. The previous correction worker left uncommitted local worktree changes. Do not discard them. Review and preserve the existing uncommitted correction diff before editing further.

Required correction scope:
- Continue on ${implementation_branch}.
- Update existing draft PR #${pr_id} only; do not create another branch or PR.
- Complete persisted and verified AppHost/DCP creator identity handling.
- Ensure cleanup operates only on the exact owned Experiment 08B AppHost identity.
- Make cleanup fail safely on missing, stale, or ambiguous identity.
- Make negative validation start a fresh owned Experiment 08B stack rather than select an arbitrary existing Aspire stack.
- Add bounded traps that restore workloads and RabbitMQ where applicable.
- Preserve failure evidence while cleaning up only owned resources.
- Add or complete cleanup isolation and intentional failure tests.
- Record executable bits for all scripts.
- Update README, validation plan, and developer validation evidence.
- Keep "Relates to #16" in the PR description.

Required validation:
1. clean positive validation;
2. RabbitMQ negative validation;
3. fresh-order functional recovery;
4. unrelated Aspire/DCP resource isolation;
5. intentional failure recovery and cleanup;
6. second fresh clean positive validation;
7. Experiment 08A integrity;
8. Git hygiene;
9. secret scan.

After validation:
- commit the correction with an appropriate conventional commit;
- push to the existing branch;
- update draft PR #${pr_id};
- post a complete correction report to issue #${issue_id};
- report the new PR head SHA;
- stop before tester dispatch.

Do not modify Experiment 08A, application source, architecture scope, cloud resources, runtime security configuration, OpenClaw, DevClaw, or the active skill. Do not mark the PR ready, dispatch a tester, merge, or close the issue.

When complete or blocked, call work_finish with role "developer", channelId "${channel_id}", result "done" or "blocked", and a concise summary.
EOF_MESSAGE
)"

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "devclaw-${project}-${issue_id}-pr17-correction-continuation-${started_at}" \
  --arg prompt "$(cat "${prompt_file}")" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent", extraSystemPrompt:$prompt}')"

mkdir -p "${state_dir}/workspace/devclaw/audit"
jq -nc \
  --arg time "${started_at}" \
  --arg project "${project}" \
  --arg issue "${issue_id}" \
  --arg pr "${pr_id}" \
  --arg sessionKey "${session_key}" \
  --arg preserveDir "${preserve_dir}" \
  --arg capabilityFile "${capability_file}" \
  --arg branchName "${implementation_branch}" \
  --arg startingHead "${expected_head}" \
  '{
    time:$time,
    project:$project,
    issue:($issue|tonumber),
    pullRequest:($pr|tonumber),
    role:"developer",
    level:"senior",
    sessionAction:"targeted-developer-correction-continuation",
    sessionKey:$sessionKey,
    implementationBranch:$branchName,
    startingHead:$startingHead,
    preserveDir:$preserveDir,
    capabilityFile:$capabilityFile,
    labelTransition:"Refining -> Refining",
    operator:"codex-operator",
    gate:"developer correction continuation only; tester requires later human instruction"
  }' >> "${state_dir}/workspace/devclaw/audit/manual-dispatch.log"
chown -R devclaw-svc:devclaw-svc "${state_dir}/workspace/devclaw/audit"

agent_result="$(
  run_as_devclaw /usr/local/bin/openclaw gateway call agent \
    --params "${agent_params}" \
    --timeout 120000 \
    --json
)"

worker_final="$(
  jq -c --arg project "${project}" '
    .projects[] | select(.name==$project).workers.developer.levels.senior[0]
  ' "${projects_file}"
)"

mkdir -p "$(dirname "${out_file}")"
jq -nc \
  --arg startedAt "${started_at}" \
  --arg finishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg branch "${branch}" \
  --arg startingHead "${expected_head}" \
  --arg labelsBefore "${labels_before}" \
  --arg labelsAfter "${labels_after}" \
  --arg sessionKey "${session_key}" \
  --arg preserveDir "${preserve_dir}" \
  --arg capabilityFile "${capability_file}" \
  --argjson workerFinal "${worker_final}" \
  --arg agentResult "${agent_result}" \
  '{
    startedAt:$startedAt,
    finishedAt:$finishedAt,
    preDispatch:{
      repository:{branch:$branch, startingHead:$startingHead, preservedUncommittedWorktree:true},
      issue:{number:16, labelsBefore:$labelsBefore},
      pullRequest:{number:17, startingHead:$startingHead, draft:true},
      recovery:{preserveDir:$preserveDir, capabilityFile:$capabilityFile},
      runtime:{sequential:true, heartbeatDisabled:true, autoMergeDisabled:true, autonomousSkillWorkshopDisabled:true, humanReview:true}
    },
    issue:{number:16, labelTransition:"Refining -> Refining", labelsAfter:$labelsAfter},
    developerWorker:{active:($workerFinal.active == true), sessionKey:$sessionKey, final:$workerFinal},
    dispatchAccepted:($agentResult | length > 0),
    agentResult:$agentResult
  }' | tee "${out_file}"
