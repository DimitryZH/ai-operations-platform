#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="10"
pr_number="11"
issue_url="https://github.com/${repo_full}/issues/${issue_id}"
pr_url="https://github.com/${repo_full}/pull/${pr_number}"
repo="/workspace/repos/application-modernization-lab"
implementation_branch="issue-10-bank-of-anthos-aspire"
base_branch="main"
channel_id="openclaw-control-ui-main"
session_key="agent:main:subagent:application-modernization-lab-tester-senior-sukey"
session_label="Application Modernization Lab - Tester Sukey (Senior)"
model="openai/gpt-5.5"
worker_name="Sukey"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
prompt_file="${state_dir}/workspace/devclaw/projects/${project}/prompts/tester.md"
projects_file="${state_dir}/workspace/devclaw/projects.json"
boundary_file="${state_dir}/workspace/devclaw/stage6-boundary.json"
skill_file="${state_dir}/workspace/skills/compose-to-aspire-migration/SKILL.md"
out_file="${1:-$(dirname "$0")/tester-dispatch-result.json}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

fail() {
  printf '[dispatch-issue-10-tester] ERROR: %s\n' "$*" >&2
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
[[ -f "${prompt_file}" ]] || fail "missing tester prompt: ${prompt_file}"
[[ -f "${projects_file}" ]] || fail "missing projects.json: ${projects_file}"
[[ -f "${boundary_file}" ]] || fail "missing stage boundary: ${boundary_file}"
[[ -r "${skill_file}" ]] || fail "active skill is not readable: ${skill_file}"

set -a
source "${gateway_env}"
set +a

[[ "$(config_get plugins.entries.devclaw.config.work_heartbeat.enabled)" == "false" ]] ||
  fail "DevClaw heartbeat must remain disabled"
[[ "$(config_get plugins.entries.devclaw.config.projectExecution)" == "sequential" ]] ||
  fail "DevClaw execution must remain sequential"
jq -e '.automaticMergeEnabled == false and .heartbeatEnabled == false and .skillWorkshop.autonomousEnabled == false' \
  "${boundary_file}" >/dev/null || fail "auto-merge, heartbeat, and autonomous Skill Workshop must remain disabled"

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
pr_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_number}")"
issue_state="$(jq -r '.state' <<<"${issue_json}")"
labels_before="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"
pr_state="$(jq -r '.state' <<<"${pr_json}")"
pr_base="$(jq -r '.base.ref' <<<"${pr_json}")"
pr_head="$(jq -r '.head.ref' <<<"${pr_json}")"
pr_sha="$(jq -r '.head.sha' <<<"${pr_json}")"

[[ "${issue_state}" == "open" ]] || fail "issue #${issue_id} must be open; found ${issue_state}"
jq -e 'any(.labels[].name; . == "Validation")' <<<"${issue_json}" >/dev/null ||
  fail "issue #${issue_id} must be in Validation; labels: ${labels_before}"
[[ "${pr_state}" == "open" ]] || fail "PR #${pr_number} must be open; found ${pr_state}"
[[ "${pr_base}" == "${base_branch}" ]] || fail "PR #${pr_number} must target ${base_branch}; found ${pr_base}"
[[ "${pr_head}" == "${implementation_branch}" ]] || fail "PR #${pr_number} must use ${implementation_branch}; found ${pr_head}"

repo_branch="$(run_as_devclaw git -C "${repo}" branch --show-current)"
repo_status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"
[[ "${repo_branch}" == "${implementation_branch}" ]] || fail "DevBox repo should be on ${implementation_branch}; found ${repo_branch}"
[[ -z "${repo_status}" ]] || fail "DevBox repo worktree must be clean before tester dispatch: ${repo_status}"

state_labels='[
  "Planning",
  "Architecture Research",
  "Researching",
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
        ["Validating", "notify:openclaw:primary", "owner:Josefina", "tester:senior", "review:human", "test:agent"]
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
TESTER task for project "${project}" - Issue #${issue_id}

Run independent validation for Experiment 07B. The human operator approved starting tester validation only. This is not approval to merge.

Issue: ${issue_url}
PR: ${pr_url}
PR head commit: ${pr_sha}
Branch: ${implementation_branch}
Repo checkout: ${repo}
Base branch: ${base_branch}
DevClaw project: ${project}
Channel: ${channel_id}

Before substantive validation begins:
- Post a brief checkpoint comment on issue #10 confirming this is a fresh tester session.
- State whether compose-to-aspire-migration is visible and loaded.
- Identify the skill sections that appear relevant to your planned independent validation.
- State that the skill is guidance, not evidence that PR #11 is correct.

Validation expectations:
- Inspect PR #11 and issue #10 independently. Do not accept the developer report as proof.
- Choose your own validation strategy, commands, negative tests, and evidence collection method.
- Use compose-to-aspire-migration as a validation playbook, especially validation checklist, failure modes, isolation, persistence, cleanup, and approval-boundary guidance.
- Evaluate the issue #10 acceptance criteria and the human validation approval comment.
- Pay particular attention to persistence across controlled AppHost shutdown/restart without deleting database volumes, functional checks for account/balance/contacts/transactions/history, Compose/Aspire isolation, deterministic negative behavior, cleanup/reset/repeatability, and untracked local artifacts.
- Do not modify, replace, or create a skill proposal.
- Do not merge PR #11, close issue #10, dispatch reviewer, or perform closeout.
- If defects are found, report them and return work to implementation through normal workflow; do not fix code directly unless the workflow explicitly instructs you to.

Completion:
- Post a complete independent validation report to issue #10.
- Identify the tested PR commit SHA.
- Distinguish fresh tester evidence from developer evidence.
- Report PASS, FAIL, or PASS WITH REQUIRED CORRECTIONS.
- Document defects, missing acceptance criteria, or required implementation changes.
- Record how the skill helped, where it was incomplete, and what project-specific testing remained necessary.
- Finish normally by calling work_finish with role "tester", channelId "${channel_id}", result "pass", "fail", "refine", or "blocked", and a concise summary.
EOF_MESSAGE
)"

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "devclaw-${project}-${issue_id}-tester-senior-validation-${started_at}" \
  --arg prompt "$(cat "${prompt_file}")" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent", extraSystemPrompt:$prompt}')"

issue_after_json="$(api_patch "https://api.github.com/repos/${repo_full}/issues/${issue_id}" "${labels_payload}")"
labels_after="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_after_json}")"

projects_tmp="$(mktemp)"
jq \
  --arg project "${project}" \
  --arg issue "${issue_id}" \
  --arg key "${session_key}" \
  --arg now "${started_at}" \
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

mkdir -p "${state_dir}/workspace/devclaw/audit"
cat >> "${state_dir}/workspace/devclaw/audit/manual-dispatch.log" <<EOF_AUDIT
{"time":"${started_at}","project":"${project}","issue":${issue_id},"role":"tester","level":"senior","sessionAction":"spawn","sessionKey":"${session_key}","labelTransition":"Validation -> Validating","operator":"codex-operator","pr":"${pr_url}","commit":"${pr_sha}","skill":"compose-to-aspire-migration"}
EOF_AUDIT
chown -R devclaw-svc:devclaw-svc "${state_dir}/workspace/devclaw/audit"

agent_result="$(
  run_as_devclaw /usr/local/bin/openclaw gateway call agent \
    --params "${agent_params}" \
    --timeout 120000 \
    --json
)"

worker_final="$(
  jq -c --arg project "${project}" \
    '.projects[] | select(.name==$project).workers.tester.levels.senior[0]' \
    "${projects_file}"
)"

mkdir -p "$(dirname "${out_file}")"
jq -nc \
  --arg startedAt "${started_at}" \
  --arg finishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg labelsBefore "${labels_before}" \
  --arg labelsAfter "${labels_after}" \
  --arg prSha "${pr_sha}" \
  --arg prUrl "${pr_url}" \
  --arg sessionKey "${session_key}" \
  --argjson workerFinal "${worker_final}" \
  --arg agentResult "${agent_result}" \
  '{
    startedAt:$startedAt,
    finishedAt:$finishedAt,
    preDispatch:{
      issue:{number:10, labelsBefore:$labelsBefore, validationState:true},
      pr:{number:11, url:$prUrl, headSha:$prSha, open:true, base:"main"},
      workersClear:true,
      runtime:{sequential:true, heartbeatDisabled:true, autoMergeDisabled:true, skillReadable:true}
    },
    issue:{labelsAfterDispatch:$labelsAfter},
    testerWorker:{active:($workerFinal.active == true), sessionKey:$sessionKey, final:$workerFinal},
    dispatchAccepted:($agentResult | length > 0),
    agentResult:$agentResult
  }' | tee "${out_file}"
