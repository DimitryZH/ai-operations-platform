#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="16"
issue_url="https://github.com/${repo_full}/issues/${issue_id}"
repo="/workspace/repos/application-modernization-lab"
base_branch="main"
channel_id="openclaw-control-ui-main"
session_key="agent:main:subagent:application-modernization-lab-architect-senior-zandra"
session_label="Application Modernization Lab - Architect Zandra (Senior)"
model="openai/gpt-5.5"
worker_name="Zandra"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
prompt_file="${state_dir}/workspace/devclaw/projects/${project}/prompts/architect.md"
projects_file="${state_dir}/workspace/devclaw/projects.json"
workflow_file="${state_dir}/workspace/devclaw/projects/${project}/workflow.yaml"
boundary_file="${state_dir}/workspace/devclaw/stage6-boundary.json"
out_file="${1:-$(dirname "$0")/../results/architect-dispatch-result.json}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

fail() {
  printf '[dispatch-issue-16-architect] ERROR: %s\n' "$*" >&2
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
[[ -f "${gateway_env}" ]] || fail "missing gateway env: ${gateway_env}"
[[ -f "${prompt_file}" ]] || fail "missing architect prompt: ${prompt_file}"
[[ -f "${projects_file}" ]] || fail "missing projects.json: ${projects_file}"
[[ -f "${workflow_file}" ]] || fail "missing workflow: ${workflow_file}"
[[ -f "${boundary_file}" ]] || fail "missing stage boundary: ${boundary_file}"

set -a
source "${gateway_env}"
set +a

branch="$(run_as_devclaw git -C "${repo}" branch --show-current)"
head="$(run_as_devclaw git -C "${repo}" rev-parse HEAD)"
origin_head="$(run_as_devclaw git -C "${repo}" rev-parse "origin/${base_branch}")"
upstream="$(run_as_devclaw git -C "${repo}" rev-parse --abbrev-ref --symbolic-full-name '@{u}')"
ahead_behind="$(run_as_devclaw git -C "${repo}" rev-list --left-right --count '@{u}...HEAD')"
status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"

[[ "${branch}" == "${base_branch}" ]] || fail "repo branch must be ${base_branch}; found ${branch}"
[[ "${head}" == "${origin_head}" ]] || fail "repo HEAD must match origin/${base_branch}; local ${head}, origin ${origin_head}"
[[ "${upstream}" == "origin/${base_branch}" ]] || fail "upstream must be origin/${base_branch}; found ${upstream}"
[[ "${ahead_behind}" == $'0\t0' || "${ahead_behind}" == "0 0" ]] || fail "repo ahead/behind must be 0/0; found ${ahead_behind}"
[[ -z "${status}" ]] || fail "repository worktree is dirty: ${status}"
[[ -d "${repo}/experiments/08-aks-store-demo/01-compose-baseline" ]] ||
  fail "missing accepted 08A baseline directory"

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
workflow_human_gate="$(
  if grep -q 'Human Baseline Approval' "${workflow_file}"; then
    printf 'Human Baseline Approval'
  elif grep -q 'Human Architecture Approval' "${workflow_file}"; then
    printf 'Human Architecture Approval'
  else
    printf ''
  fi
)"
[[ -n "${workflow_human_gate}" ]] || fail "workflow must expose a human architecture/baseline approval gate"
if grep -R -nE '\bmergePr\b|\bgitPull\b|\bcloseIssue\b' "${workflow_file}" >/dev/null; then
  fail "workflow contains automatic merge/pull/issue-close action"
fi
jq -e '
  .automaticMergeEnabled == false and
  .heartbeatEnabled == false and
  .skillWorkshop.autonomousEnabled == false and
  .skillWorkshop.approvalPolicy == "pending"
' "${boundary_file}" >/dev/null || fail "stage boundary must keep auto-merge, heartbeat, and autonomous Skill Workshop disabled"

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
comments_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments?per_page=100")"
issue_state="$(jq -r '.state' <<<"${issue_json}")"
issue_title="$(jq -r '.title' <<<"${issue_json}")"
labels_before="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"
body_hash="$(jq -r '.body // ""' <<<"${issue_json}" | sha256sum | awk '{print $1}')"
approval_found="$(
  jq -r '
    [
      .[] |
      select(((.user.login // "") | test("devclaw-agent|openclaw"; "i") | not)) |
      select((.body // "") | test("Human approval|approved|Approval|Stage 1|Aspire Architecture Research"; "i")) |
      {user:.user.login, createdAt:.created_at, bodyFirstLine:((.body // "") | split("\n")[0])}
    ] | .[-1] // empty
  ' <<<"${comments_json}"
)"
[[ "${issue_state}" == "open" ]] || fail "issue #${issue_id} must be open; found ${issue_state}"
[[ -n "${approval_found}" ]] || fail "no human approval comment found for Stage 1 architecture research"
if jq -e 'any(.labels[].name; . == "Implementing" or . == "Validating" or . == "Human Review" or . == "Human Baseline Approval" or . == "Human Architecture Approval" or . == "Done" or . == "Rejected" or . == "To Improve" or . == "Refining")' <<<"${issue_json}" >/dev/null; then
  fail "issue #${issue_id} already appears active, gated, blocked, or terminal: ${labels_before}"
fi

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
        ["Researching", "notify:openclaw:primary", "owner:Josefina", "architect:senior", "review:human"]
        | unique
      )
    }'
)"

run_as_devclaw /usr/local/bin/openclaw gateway call sessions.delete \
  --params "$(jq -nc --arg key "${session_key}" '{key:$key}')" \
  --timeout 10000 \
  --json >/dev/null 2>&1 || true

run_as_devclaw /usr/local/bin/openclaw gateway call sessions.patch \
  --params "$(jq -nc --arg key "${session_key}" --arg model "${model}" --arg label "${session_label}" '{key:$key, model:$model, label:$label}')" \
  --timeout 30000 \
  --json >/dev/null

task_message="$(cat <<EOF_MESSAGE
SENIOR ARCHITECT task for project "${project}" - issue #${issue_id}

Begin Stage 1: Aspire Architecture Research for Experiment 08B only.

Issue: ${issue_url}
Repository: ${repo_full}
Repo checkout: ${repo}
Base branch: ${base_branch}
Channel: ${channel_id}

Read the complete issue #${issue_id} contract directly and treat it as authoritative. Inspect accepted issue #14 and merged PR #15. Treat experiments/08-aks-store-demo/01-compose-baseline/ as immutable input. Inspect the active Compose-to-Aspire migration methodology in read-only mode.

Design the Experiment 08B .NET Aspire migration under experiments/08-aks-store-demo/02-compose-to-aspire/. Cover service/resource mapping, image/build strategy, endpoints, health/readiness, workload control, persistence classification, validation including negative tests, cleanup, rollback, and decisions requiring human approval.

Boundaries:
- Architecture research/report only; stop before implementation.
- Do not modify Experiment 08A, create a branch, commit, PR, AppHost code, cloud resources, skill changes, developer/tester dispatches, heartbeat, parallel execution, or auto-merge.
- Preserve human approval gates and stop at Human Baseline Approval.
- Post the complete architecture report to issue #${issue_id}.
- When done or blocked, call work_finish with role "architect", channelId "${channel_id}", result "done" or "blocked", and a concise summary.
EOF_MESSAGE
)"

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "devclaw-${project}-${issue_id}-architect-senior-aspire-architecture-research-${started_at}" \
  --arg prompt "$(cat "${prompt_file}")" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent", extraSystemPrompt:$prompt}')"

issue_after_json="$(api_patch "https://api.github.com/repos/${repo_full}/issues/${issue_id}" "${labels_payload}")"
labels_after="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_after_json}")"
label_transition="$(
  if grep -Eq '(^|, )Researching(, |$)' <<<"${labels_before}"; then
    printf 'Researching -> Researching (pre-existing)'
  else
    printf 'Architecture Research -> Researching'
  fi
)"

projects_tmp="$(mktemp)"
jq \
  --arg project "${project}" \
  --arg issue "${issue_id}" \
  --arg key "${session_key}" \
  --arg now "${started_at}" \
  --arg name "${worker_name}" \
  '(.projects[] | select(.name==$project).workers.architect.levels.senior[0]) = {
    active: true,
    issueId: $issue,
    sessionKey: $key,
    startTime: $now,
    previousLabel: "Aspire Architecture Research",
    name: $name,
    level: "senior"
  }' "${projects_file}" > "${projects_tmp}"
mv "${projects_tmp}" "${projects_file}"
chown devclaw-svc:devclaw-svc "${projects_file}"

mkdir -p "${state_dir}/workspace/devclaw/audit"
cat >> "${state_dir}/workspace/devclaw/audit/manual-dispatch.log" <<EOF_AUDIT
{"time":"${started_at}","project":"${project}","issue":${issue_id},"role":"architect","level":"senior","sessionAction":"spawn","sessionKey":"${session_key}","labelTransition":"${label_transition}","operator":"codex-operator","gate":"Human Baseline Approval","experiment":"08B"}
EOF_AUDIT
chown -R devclaw-svc:devclaw-svc "${state_dir}/workspace/devclaw/audit"

agent_result="$(
  run_as_devclaw /usr/local/bin/openclaw gateway call agent \
    --params "${agent_params}" \
    --timeout 120000 \
    --json
)"

issue_final_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}")"
labels_final="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_final_json}")"
worker_final="$(
  jq -c --arg project "${project}" '
    .projects[] | select(.name==$project).workers.architect.levels.senior[0]
  ' "${projects_file}"
)"

mkdir -p "$(dirname "${out_file}")"
jq -nc \
  --arg startedAt "${started_at}" \
  --arg finishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg branch "${branch}" \
  --arg head "${head}" \
  --arg originHead "${origin_head}" \
  --arg upstream "${upstream}" \
  --arg aheadBehind "${ahead_behind}" \
  --arg labelsBefore "${labels_before}" \
  --arg labelsAfter "${labels_after}" \
  --arg labelsFinal "${labels_final}" \
  --arg labelTransition "${label_transition}" \
  --arg bodyHash "${body_hash}" \
  --argjson approvalFound "${approval_found}" \
  --arg workflowHumanGate "${workflow_human_gate}" \
  --arg sessionKey "${session_key}" \
  --argjson workerFinal "${worker_final}" \
  --arg agentResult "${agent_result}" \
  '{
    startedAt:$startedAt,
    finishedAt:$finishedAt,
    preDispatch:{
      repo:{branch:$branch, head:$head, originHead:$originHead, upstream:$upstream, aheadBehind:$aheadBehind, clean:true, synchronized:true},
      issue:{number:16, labelsBefore:$labelsBefore, bodySha256:$bodyHash, humanApproval:$approvalFound},
      runtime:{sequential:true, heartbeatDisabled:true, autoMergeDisabled:true, autonomousSkillWorkshopDisabled:true, humanReview:true, workflowHumanGate:$workflowHumanGate, requestedStopGate:"Human Baseline Approval"}
    },
    issue:{number:16, labelTransition:$labelTransition, labelsAfterDispatch:$labelsAfter, labelsFinal:$labelsFinal},
    architectWorker:{active:($workerFinal.active == true), sessionKey:$sessionKey, final:$workerFinal},
    dispatchAccepted:($agentResult | length > 0),
    agentResult:$agentResult
  }' | tee "${out_file}"
