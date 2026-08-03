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
session_key="agent:main:subagent:application-modernization-lab-developer-senior-ara-issue-16-pr17-correction-${session_suffix}"
session_label="Application Modernization Lab - Developer Ara (Senior Issue 16 PR17 Correction ${session_suffix})"
model="openai/gpt-5.5"
worker_name="Ara"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
prompt_file="${state_dir}/workspace/devclaw/projects/${project}/prompts/developer.md"
projects_file="${state_dir}/workspace/devclaw/projects.json"
workflow_file="${state_dir}/workspace/devclaw/projects/${project}/workflow.yaml"
boundary_file="${state_dir}/workspace/devclaw/stage6-boundary.json"
out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/developer-correction-pr17-dispatch-result.json}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

fail() {
  printf '[dispatch-issue-16-targeted-developer-correction-pr17] ERROR: %s\n' "$*" >&2
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
[[ -d "${repo}/.git" ]] || fail "missing repository checkout: ${repo}"
[[ -f "${gateway_env}" ]] || fail "missing gateway env"
[[ -f "${prompt_file}" ]] || fail "missing developer prompt"
[[ -f "${projects_file}" ]] || fail "missing projects.json"
[[ -f "${workflow_file}" ]] || fail "missing workflow"
[[ -f "${boundary_file}" ]] || fail "missing stage boundary"
[[ -S /run/devclaw/github-token-broker.sock ]] || fail "missing GitHub token broker socket"

set -a
# shellcheck disable=SC1090
source "${gateway_env}"
set +a

[[ "$(systemctl is-active openclaw-gateway.service)" == "active" ]] ||
  fail "openclaw-gateway.service is not active"
[[ "$(systemctl is-active devclaw-github-token-broker.service)" == "active" ]] ||
  fail "devclaw-github-token-broker.service is not active"

gateway_status="$(run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000)"
gateway_active_tasks="$(jq -r '.tasks.active // -1' <<<"${gateway_status}")"
[[ "${gateway_active_tasks}" == "0" ]] || fail "Gateway has active tasks: ${gateway_active_tasks}"

worker_conflict="$(
  jq -r --arg project "${project}" '
    .projects[] | select(.name==$project).workers
    | to_entries[]
    | .key as $role
    | .value.levels
    | to_entries[]
    | .key as $level
    | .value[]
    | select(.active == true)
    | "\($role):\($level):issue=\(.issueId // "null"):session=\(.sessionKey // "null")"
  ' "${projects_file}"
)"
[[ -z "${worker_conflict}" ]] || fail "conflicting active worker(s): ${worker_conflict}"

pre_status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"
[[ -z "${pre_status}" ]] || fail "repository worktree is dirty before dispatch: ${pre_status}"
run_as_devclaw git -C "${repo}" fetch --prune origin
run_as_devclaw git -C "${repo}" switch "${implementation_branch}" >/dev/null
if ! run_as_devclaw git -C "${repo}" pull --ff-only origin "${implementation_branch}" >/dev/null; then
  local_tree="$(run_as_devclaw git -C "${repo}" rev-parse 'HEAD^{tree}')"
  origin_tree="$(run_as_devclaw git -C "${repo}" rev-parse "origin/${implementation_branch}^{tree}")"
  current_status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"
  if [[ -n "${current_status}" || "${local_tree}" != "${origin_tree}" ]]; then
    fail "branch diverged and cannot be safely aligned: status=${current_status}, local_tree=${local_tree}, origin_tree=${origin_tree}"
  fi
  run_as_devclaw git -C "${repo}" reset --hard "origin/${implementation_branch}" >/dev/null
fi
head="$(run_as_devclaw git -C "${repo}" rev-parse HEAD)"
origin_head="$(run_as_devclaw git -C "${repo}" rev-parse "origin/${implementation_branch}")"
upstream="$(run_as_devclaw git -C "${repo}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [[ -z "${upstream}" ]]; then
  run_as_devclaw git -C "${repo}" branch --set-upstream-to="origin/${implementation_branch}" "${implementation_branch}" >/dev/null
fi
ahead_behind="$(run_as_devclaw git -C "${repo}" rev-list --left-right --count '@{u}...HEAD')"
post_status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"
[[ "${head}" == "${expected_head}" ]] || fail "local branch head ${head} does not match expected ${expected_head}"
[[ "${origin_head}" == "${expected_head}" ]] || fail "origin branch head ${origin_head} does not match expected ${expected_head}"
[[ "${ahead_behind}" == $'0\t0' || "${ahead_behind}" == "0 0" ]] || fail "branch ahead/behind must be 0/0; found ${ahead_behind}"
[[ -z "${post_status}" ]] || fail "repository worktree is dirty after sync: ${post_status}"

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
issue_comments_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments?per_page=100")"
pr_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_id}")"
pr_issue_comments_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${pr_id}/comments?per_page=100")"
pr_reviews_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_id}/reviews?per_page=100")"
pr_review_comments_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_id}/comments?per_page=100")"

issue_state="$(jq -r '.state' <<<"${issue_json}")"
issue_labels_before="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"
pr_state="$(jq -r '.state' <<<"${pr_json}")"
pr_draft="$(jq -r '.draft' <<<"${pr_json}")"
pr_head_ref="$(jq -r '.head.ref' <<<"${pr_json}")"
pr_head_sha="$(jq -r '.head.sha' <<<"${pr_json}")"
pr_title="$(jq -r '.title' <<<"${pr_json}")"
[[ "${issue_state}" == "open" ]] || fail "issue #${issue_id} must be open"
[[ "${pr_state}" == "open" ]] || fail "PR #${pr_id} must be open"
[[ "${pr_draft}" == "true" ]] || fail "PR #${pr_id} must remain draft"
[[ "${pr_head_ref}" == "${implementation_branch}" ]] || fail "PR head ref mismatch: ${pr_head_ref}"
[[ "${pr_head_sha}" == "${expected_head}" ]] || fail "PR head sha mismatch: ${pr_head_sha}"

human_pr_correction_count="$(
  jq -s '
    ([.[0][]?, .[1][]?, .[2][]?]
     | map(select(((.user.login // "") | test("devclaw-agent|openclaw"; "i") | not)
       and ((.body // "") | test("Human Developer Review|Corrections Required|cleanup.*identity|Closes #16|Relates to #16|DCP|negative validation|isolation"; "i"))))
     | length)
  ' <(printf '%s' "${pr_issue_comments_json}") <(printf '%s' "${pr_reviews_json}") <(printf '%s' "${pr_review_comments_json}")
)"
human_issue_approval_count="$(
  jq '[.[] | select(((.user.login // "") | test("devclaw-agent|openclaw"; "i") | not)
    and ((.body // "") | test("Human Developer Correction Approval|Developer Correction Approval|Correction Approval"; "i")))] | length' \
    <<<"${issue_comments_json}"
)"
[[ "${human_pr_correction_count}" -ge 1 ]] || fail "Human Developer Review corrections were not found on PR #${pr_id}"
[[ "${human_issue_approval_count}" -ge 1 ]] || fail "Human Developer Correction Approval was not found on issue #${issue_id}"

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
issue_labels_after="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_after_json}")"

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
    previousLabel: "Human Developer Review - Corrections Required",
    name: $name,
    level: "senior",
    correctionFor: "PR #17",
    expectedStartingHead: "6722ff491c2a9053a9f76b4bb9223b64f3ec6b3b"
  }' "${projects_file}" > "${projects_tmp}"
mv "${projects_tmp}" "${projects_file}"
chown devclaw-svc:devclaw-svc "${projects_file}"

run_as_devclaw /usr/local/bin/openclaw gateway call sessions.patch \
  --params "$(jq -nc --arg key "${session_key}" --arg model "${model}" --arg label "${session_label}" '{key:$key, model:$model, label:$label}')" \
  --timeout 30000 \
  --json >/dev/null

task_message="$(cat <<EOF_MESSAGE
SENIOR DEVELOPER targeted correction task for project "${project}" - issue #${issue_id}, draft PR #${pr_id}

Repository: ${repo_full}
Issue: ${issue_url}
Draft PR: ${pr_url}
Repo checkout: ${repo}
Existing branch to keep: ${implementation_branch}
Expected starting PR head: ${expected_head}
Current PR title: ${pr_title}
Channel: ${channel_id}

Read the exact current PR head, PR #${pr_id}, issue #${issue_id}, the Human Developer Review - Corrections Required on PR #${pr_id}, and the Human Developer Correction Approval on issue #${issue_id}. Use those human comments as the authoritative correction contract.

Targeted correction scope only:
- Keep the existing branch ${implementation_branch}.
- Update the existing draft PR #${pr_id}; do not create another PR.
- Change the PR issue reference from "Closes #16" to a non-closing reference such as "Relates to #16".
- Bind cleanup to the exact creator identity of the current Experiment 08B AppHost instance.
- Persist and verify that identity instead of selecting the first matching global DCP container.
- Make cleanup fail safely when identity is absent or ambiguous.
- Prevent negative validation from selecting unrelated or stale Aspire resources.
- Add bounded failure handling that restores paused workloads, restores RabbitMQ when required, stops the owned AppHost, and cleans up only owned Experiment 08B resources.
- Preserve diagnostic evidence on failure.
- Add a targeted isolation test proving unrelated Aspire/DCP resources are not removed or modified.

Required validation before finishing:
1. clean positive validation;
2. RabbitMQ negative and recovery validation;
3. cleanup isolation validation;
4. intentional failure cleanup validation;
5. a second fresh clean positive validation;
6. Git hygiene and secret scan.

Update committed documentation and developer validation evidence. Commit and push corrections to PR #${pr_id}. Post a concise correction report to issue #${issue_id}. Stop before tester dispatch.

Do not modify Experiment 08A, application source, architecture scope, cloud resources, runtime security configuration, OpenClaw, DevClaw, or the active skill. Do not mark the PR ready, dispatch a tester, merge, or close the issue.

When complete or blocked, call work_finish with role "developer", channelId "${channel_id}", result "done" or "blocked", and a concise summary.
EOF_MESSAGE
)"

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "devclaw-${project}-${issue_id}-developer-pr17-correction-${started_at}" \
  --arg prompt "$(cat "${prompt_file}")" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent", extraSystemPrompt:$prompt}')"

mkdir -p "${state_dir}/workspace/devclaw/audit"
jq -nc \
  --arg time "${started_at}" \
  --arg project "${project}" \
  --arg issue "${issue_id}" \
  --arg pr "${pr_id}" \
  --arg sessionKey "${session_key}" \
  --arg branchName "${implementation_branch}" \
  --arg startingHead "${expected_head}" \
  '{
    time:$time,
    project:$project,
    issue:($issue|tonumber),
    pullRequest:($pr|tonumber),
    role:"developer",
    level:"senior",
    sessionAction:"targeted-developer-correction-dispatch",
    sessionKey:$sessionKey,
    implementationBranch:$branchName,
    startingHead:$startingHead,
    labelTransition:"Human Developer Review Corrections Required -> Refining",
    operator:"codex-operator",
    gate:"developer correction only; tester requires later human instruction"
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
  --arg branch "${implementation_branch}" \
  --arg startingHead "${expected_head}" \
  --arg labelsBefore "${issue_labels_before}" \
  --arg labelsAfter "${issue_labels_after}" \
  --arg sessionKey "${session_key}" \
  --argjson workerFinal "${worker_final}" \
  --arg agentResult "${agent_result}" \
  '{
    startedAt:$startedAt,
    finishedAt:$finishedAt,
    preDispatch:{
      repo:{branch:$branch, startingHead:$startingHead, clean:true, synchronized:true},
      issue:{number:16, labelsBefore:$labelsBefore},
      pullRequest:{number:17, startingHead:$startingHead, draft:true},
      runtime:{sequential:true, heartbeatDisabled:true, autoMergeDisabled:true, autonomousSkillWorkshopDisabled:true, humanReview:true}
    },
    issue:{number:16, labelTransition:"Human Developer Review Corrections Required -> Refining", labelsAfter:$labelsAfter},
    developerWorker:{active:($workerFinal.active == true), sessionKey:$sessionKey, final:$workerFinal},
    dispatchAccepted:($agentResult | length > 0),
    agentResult:$agentResult
  }' | tee "${out_file}"
