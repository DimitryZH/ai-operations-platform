#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="10"
issue_url="https://github.com/${repo_full}/issues/${issue_id}"
repo="/workspace/repos/application-modernization-lab"
approved_base_head="3de8845412853525aeb77d85db23f2d14b1bfc73"
base_branch="main"
channel_id="openclaw-control-ui-main"
session_key="agent:main:subagent:application-modernization-lab-developer-senior-ara"
session_label="Application Modernization Lab - Developer Ara (Senior)"
model="openai/gpt-5.5"
worker_name="Ara"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
prompt_file="${state_dir}/workspace/devclaw/projects/${project}/prompts/developer.md"
projects_file="${state_dir}/workspace/devclaw/projects.json"
workflow_file="${state_dir}/workspace/devclaw/projects/${project}/workflow.yaml"
boundary_file="${state_dir}/workspace/devclaw/stage6-boundary.json"
skill_file="${state_dir}/workspace/skills/compose-to-aspire-migration/SKILL.md"
out_file="${1:-$(dirname "$0")/developer-dispatch-result.json}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

fail() {
  printf '[dispatch-issue-10-developer] ERROR: %s\n' "$*" >&2
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
[[ -f "${prompt_file}" ]] || fail "missing developer prompt: ${prompt_file}"
[[ -f "${projects_file}" ]] || fail "missing projects.json: ${projects_file}"
[[ -f "${workflow_file}" ]] || fail "missing workflow: ${workflow_file}"
[[ -f "${boundary_file}" ]] || fail "missing stage boundary: ${boundary_file}"
[[ -r "${skill_file}" ]] || fail "active skill is not readable: ${skill_file}"

set -a
source "${gateway_env}"
set +a

current_branch="$(run_as_devclaw git -C "${repo}" branch --show-current)"
current_head="$(run_as_devclaw git -C "${repo}" rev-parse HEAD)"
upstream="$(run_as_devclaw git -C "${repo}" rev-parse --abbrev-ref --symbolic-full-name '@{u}')"
ahead_behind="$(run_as_devclaw git -C "${repo}" rev-list --left-right --count '@{u}...HEAD')"
status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"

[[ "${current_branch}" == "${base_branch}" ]] || fail "repo branch must be ${base_branch}; found ${current_branch}"
run_as_devclaw git -C "${repo}" merge-base --is-ancestor "${approved_base_head}" HEAD ||
  fail "repo HEAD must contain approved base ${approved_base_head}; found ${current_head}"
[[ "${upstream}" == "origin/${base_branch}" ]] || fail "repo upstream must be origin/${base_branch}; found ${upstream}"
[[ "${ahead_behind}" == $'0\t0' || "${ahead_behind}" == "0 0" ]] || fail "repo ahead/behind must be 0/0; found ${ahead_behind}"
[[ -z "${status}" ]] || fail "repo worktree is dirty: ${status}"

[[ "$(config_get plugins.entries.devclaw.config.work_heartbeat.enabled)" == "false" ]] ||
  fail "DevClaw heartbeat must remain disabled"
[[ "$(config_get plugins.entries.devclaw.config.projectExecution)" == "sequential" ]] ||
  fail "DevClaw execution must remain sequential"
[[ "$(config_get skills.workshop.autonomous.enabled)" == "false" ]] ||
  fail "Skill Workshop autonomous behavior must remain disabled"
[[ "$(config_get skills.workshop.approvalPolicy)" == "pending" ]] ||
  fail "Skill Workshop approvalPolicy must remain pending"

grep -q 'reviewPolicy: human' "${workflow_file}" || fail "workflow must keep human review policy"
grep -q 'Human Architecture Approval' "${workflow_file}" || fail "workflow must keep Human Architecture Approval gate"
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
[[ "${issue_state}" == "open" ]] || fail "issue #${issue_id} must be open; found ${issue_state}"
jq -e 'any(.labels[].name; . == "Implementation")' <<<"${issue_json}" >/dev/null ||
  fail "issue #${issue_id} must be in Implementation; labels: ${labels_before}"
if jq -e 'any(.labels[].name; . == "Implementing" or . == "Validating" or . == "Human Review" or . == "Done" or . == "Rejected" or . == "To Improve" or . == "Refining")' <<<"${issue_json}" >/dev/null; then
  fail "issue #${issue_id} already appears active, blocked, or terminal: ${labels_before}"
fi

approval_found="$(
  jq -r '
    any(.[]; ((.user.login // "") | test("devclaw-agent-devbox"; "i") | not) and
      ((.body // "") | test("approve|approved|approval|implementation|go ahead|start"; "i")))
  ' <<<"${comments_json}"
)"
[[ "${approval_found}" == "true" ]] || fail "human architecture approval comment was not found"

blocking_question_found="$(
  jq -r '
    if length == 0 then false else
      (.[-1].body // "") as $body |
      (($body | test("\\?")) and ($body | test("blocked|question|clarify|approval needed|need human"; "i")))
    end
  ' <<<"${comments_json}"
)"
[[ "${blocking_question_found}" == "false" ]] || fail "latest issue comment appears to contain an unresolved implementation-blocking question"

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
        ["Implementing", "notify:openclaw:primary", "owner:Josefina", "developer:senior", "review:human", "test:agent"]
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
DEVELOPER task for project "${project}" - Issue #${issue_id}

Start implementation for Experiment 07B only. The architecture report has been reviewed and explicitly approved by the human operator, and issue #10 is in the Implementation stage.

Issue: ${issue_url}
Issue title: ${issue_title}
Repository: ${repo_full}
Repo checkout: ${repo}
Base branch: ${base_branch}
Approved baseline commit: ${approved_base_head}
Validated Compose input: experiments/07-bank-of-anthos/01-kubernetes-to-compose/
Aspire target: experiments/07-bank-of-anthos/02-compose-to-aspire/
DevClaw project: ${project}
Channel: ${channel_id}

Fresh-session skill evidence requirement:
- This is a new developer session. Before making repository changes, post a concise issue comment titled "Developer skill pre-use checkpoint" confirming whether compose-to-aspire-migration is loaded in this fresh session.
- In that pre-use checkpoint, list the skill sections you expect to use and any known failure modes the skill should help avoid.
- In the final implementation report, include skill-reuse evidence covering:
  1. whether compose-to-aspire-migration was loaded in the fresh developer session;
  2. which sections were used during implementation;
  3. which repeated investigation or known failure modes it helped avoid;
  4. which Bank of Anthos-specific decisions still required independent discovery;
  5. which recommendations were incomplete, inapplicable, or adapted.
- Do not inspect, modify, or propose changes to the active skill.
- Do not create or apply a skill proposal.

Approved implementation boundaries:
- Create implementation only under experiments/07-bank-of-anthos/02-compose-to-aspire/.
- Use the validated 07A Compose baseline as authoritative input.
- Do not modify Experiment 07A.
- Do not modify Bank of Anthos application source without new explicit human approval.
- Model all Bank of Anthos application services as Aspire container resources.
- Preserve both pinned PostgreSQL services as separate containers.
- Preserve independent persistent volumes for the two databases.
- Preserve local JWT generation and private/public key mount boundaries.
- Publish only the frontend and bind it to loopback.
- Use port 8080 by default.
- Keep the load generator optional and disabled by default.
- Do not add ServiceDefaults to the prebuilt Bank of Anthos services.
- Preserve deterministic current-run transaction evidence.
- Include persistence, Compose/Aspire isolation, cleanup, reset, and negative validation.
- Prevent generated secrets, cookies, logs, dumps, runtime evidence, and local state from being tracked.

Deliverables:
- Create the implementation branch through the normal DevClaw workflow.
- Implement the approved Aspire AppHost and supporting files.
- Add a native validation entrypoint that exits non-zero on failure.
- Run developer validation.
- Create intentional implementation commits.
- Open a pull request linked to issue #10.
- Post a concise implementation and validation report to issue #10.
- Include the required skill-reuse observations in that report.
- Finish the developer worker normally by calling work_finish with role "developer", channelId "${channel_id}", result "done" or "blocked", and a concise summary.

Do not dispatch tester, reviewer, or any dependent worker. Do not review, approve, merge, or close the PR or issue.
EOF_MESSAGE
)"

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "devclaw-${project}-${issue_id}-developer-senior-implementation-${started_at}" \
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
  '(.projects[] | select(.name==$project).workers.developer.levels.senior[0]) = {
    active: true,
    issueId: $issue,
    sessionKey: $key,
    startTime: $now,
    previousLabel: "Implementation",
    name: $name,
    level: "senior"
  }' "${projects_file}" > "${projects_tmp}"
mv "${projects_tmp}" "${projects_file}"
chown devclaw-svc:devclaw-svc "${projects_file}"

mkdir -p "${state_dir}/workspace/devclaw/audit"
cat >> "${state_dir}/workspace/devclaw/audit/manual-dispatch.log" <<EOF_AUDIT
{"time":"${started_at}","project":"${project}","issue":${issue_id},"role":"developer","level":"senior","sessionAction":"spawn","sessionKey":"${session_key}","labelTransition":"Implementation -> Implementing","operator":"codex-operator","skill":"compose-to-aspire-migration"}
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
    .projects[] | select(.name==$project).workers.developer.levels.senior[0]
  ' "${projects_file}"
)"

mkdir -p "$(dirname "${out_file}")"
jq -nc \
  --arg startedAt "${started_at}" \
  --arg finishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg branch "${current_branch}" \
  --arg head "${current_head}" \
  --arg upstream "${upstream}" \
  --arg aheadBehind "${ahead_behind}" \
  --arg labelsBefore "${labels_before}" \
  --arg labelsAfter "${labels_after}" \
  --arg labelsFinal "${labels_final}" \
  --arg sessionKey "${session_key}" \
  --argjson workerFinal "${worker_final}" \
  --arg agentResult "${agent_result}" \
  '{
    startedAt:$startedAt,
    finishedAt:$finishedAt,
    preDispatch:{
      repo:{branch:$branch, head:$head, upstream:$upstream, aheadBehind:$aheadBehind, clean:true},
      issue:{number:10, labelsBefore:$labelsBefore, approvalFound:true, blockingQuestionFound:false},
      runtime:{sequential:true, heartbeatDisabled:true, autoMergeDisabled:true, autonomousSkillWorkshopDisabled:true, skillReadable:true}
    },
    issue:{number:10, labelsAfterDispatch:$labelsAfter, labelsFinal:$labelsFinal},
    developerWorker:{active:($workerFinal.active == true), sessionKey:$sessionKey, final:$workerFinal},
    dispatchAccepted:($agentResult | length > 0),
    agentResult:$agentResult
  }' | tee "${out_file}"
