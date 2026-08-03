#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="16"
issue_url="https://github.com/${repo_full}/issues/${issue_id}"
repo="/workspace/repos/application-modernization-lab"
base_branch="main"
implementation_branch="experiment-08/aks-store-aspire-migration"
channel_id="openclaw-control-ui-main"
session_suffix="$(date -u +%Y%m%dt%H%M%Sz)"
session_key="agent:main:subagent:application-modernization-lab-developer-senior-ara-issue-16-userns-recovery-${session_suffix}"
session_label="Application Modernization Lab - Developer Ara (Senior Issue 16 Userns Recovery ${session_suffix})"
model="openai/gpt-5.5"
worker_name="Ara"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
prompt_file="${state_dir}/workspace/devclaw/projects/${project}/prompts/developer.md"
projects_file="${state_dir}/workspace/devclaw/projects.json"
workflow_file="${state_dir}/workspace/devclaw/projects/${project}/workflow.yaml"
boundary_file="${state_dir}/workspace/devclaw/stage6-boundary.json"
workflow_root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31"
context_script="${workflow_root}/scripts/prepare-issue-16-developer-context-packet.sh"
context_result="${workflow_root}/results/issue-16-developer-context-packet-userns-recovery.json"
context_md="${workflow_root}/context/issue-16-authoritative-context.md"
context_json="${workflow_root}/context/issue-16-authoritative-context.json"
runtime_validation="${workflow_root}/runtime-diagnostics/results/narrow-userns-apparmor-validation-20260801T151310Z/validation-summary.json"
out_file="${1:-${workflow_root}/results/developer-dispatch-recovery-after-userns-fix-result.json}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

fail() {
  printf '[dispatch-issue-16-developer-dispatch-recovery-after-userns-fix] ERROR: %s\n' "$*" >&2
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
[[ -f "${gateway_env}" ]] || fail "missing gateway env: ${gateway_env}"
[[ -f "${prompt_file}" ]] || fail "missing developer prompt: ${prompt_file}"
[[ -f "${projects_file}" ]] || fail "missing projects.json: ${projects_file}"
[[ -f "${workflow_file}" ]] || fail "missing workflow: ${workflow_file}"
[[ -f "${boundary_file}" ]] || fail "missing stage boundary: ${boundary_file}"
[[ -f "${context_script}" ]] || fail "missing context script: ${context_script}"
[[ -f "${runtime_validation}" ]] || fail "missing runtime validation evidence: ${runtime_validation}"
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

validation_ok="$(
  jq -r '
    (.localSmoke.directBwrap.rc == 0) and
    (.subagentSmoke.session.status == "done") and
    ((.subagentSmoke.transcriptTail // "") | contains("SMOKE_OK"))
  ' "${runtime_validation}"
)"
[[ "${validation_ok}" == "true" ]] || fail "runtime validation evidence does not show direct bwrap + subagent SMOKE_OK"

pre_status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"
[[ -z "${pre_status}" ]] || fail "repository worktree is dirty before dispatch: ${pre_status}"
run_as_devclaw git -C "${repo}" fetch --prune origin
run_as_devclaw git -C "${repo}" switch "${base_branch}" >/dev/null
run_as_devclaw git -C "${repo}" pull --ff-only origin "${base_branch}" >/dev/null

branch="$(run_as_devclaw git -C "${repo}" branch --show-current)"
head="$(run_as_devclaw git -C "${repo}" rev-parse HEAD)"
origin_head="$(run_as_devclaw git -C "${repo}" rev-parse "origin/${base_branch}")"
upstream="$(run_as_devclaw git -C "${repo}" rev-parse --abbrev-ref --symbolic-full-name '@{u}')"
ahead_behind="$(run_as_devclaw git -C "${repo}" rev-list --left-right --count '@{u}...HEAD')"
post_status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"
[[ "${branch}" == "${base_branch}" ]] || fail "repo branch must be ${base_branch}; found ${branch}"
[[ "${head}" == "${origin_head}" ]] || fail "local ${base_branch} is not synchronized with origin/${base_branch}"
[[ "${upstream}" == "origin/${base_branch}" ]] || fail "upstream must be origin/${base_branch}; found ${upstream}"
[[ "${ahead_behind}" == $'0\t0' || "${ahead_behind}" == "0 0" ]] || fail "repo ahead/behind must be 0/0; found ${ahead_behind}"
[[ -z "${post_status}" ]] || fail "repository worktree is dirty after sync: ${post_status}"
[[ -d "${repo}/experiments/08-aks-store-demo/01-compose-baseline" ]] ||
  fail "missing immutable accepted 08A baseline directory"
if run_as_devclaw git -C "${repo}" show-ref --verify --quiet "refs/heads/${implementation_branch}"; then
  fail "local implementation branch already exists: ${implementation_branch}"
fi
if run_as_devclaw git -C "${repo}" ls-remote --exit-code --heads origin "${implementation_branch}" >/dev/null 2>&1; then
  fail "remote implementation branch already exists: ${implementation_branch}"
fi

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
comments_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments?per_page=100")"
prs_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls?state=open&per_page=100")"
issue_state="$(jq -r '.state' <<<"${issue_json}")"
issue_title="$(jq -r '.title' <<<"${issue_json}")"
labels_before="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"
body_hash="$(jq -r '.body // ""' <<<"${issue_json}" | sha256sum | awk '{print $1}')"
[[ "${issue_state}" == "open" ]] || fail "issue #${issue_id} must be open; found ${issue_state}"
if ! jq -e 'any(.labels[].name; . == "Implementation" or . == "Implementing" or . == "Refining")' <<<"${issue_json}" >/dev/null; then
  fail "issue #${issue_id} must be in implementation/recovery state; labels: ${labels_before}"
fi
if jq -e 'any(.labels[].name; . == "Validating" or . == "Human Review" or . == "Done" or . == "Rejected")' <<<"${issue_json}" >/dev/null; then
  fail "issue #${issue_id} has advanced or become terminal: ${labels_before}"
fi

architecture_report_index="$(jq -r 'map((.body // "") | test("Stage 1 Aspire Architecture Research Report|Aspire Architecture Research Report"; "i")) | to_entries | map(select(.value == true).key) | max // -1' <<<"${comments_json}")"
architecture_approval_index="$(jq -r 'map((((.user.login // "") | test("devclaw-agent|openclaw"; "i") | not) and ((.body // "") | test("^## Human Aspire Architecture Approval"; "im")))) | to_entries | map(select(.value == true).key) | max // -1' <<<"${comments_json}")"
implementation_approval_index="$(jq -r 'map((((.user.login // "") | test("devclaw-agent|openclaw"; "i") | not) and ((.body // "") | test("^## Human Implementation Approval"; "im")))) | to_entries | map(select(.value == true).key) | max // -1' <<<"${comments_json}")"
[[ "${architecture_report_index}" -ge 0 ]] || fail "architect report comment was not found"
[[ "${architecture_approval_index}" -gt "${architecture_report_index}" ]] || fail "Human Aspire Architecture Approval must exist after the architect report"
[[ "${implementation_approval_index}" -gt "${architecture_approval_index}" ]] || fail "Human Implementation Approval must exist after Human Aspire Architecture Approval"

open_pr_conflicts="$(
  jq -r '
    .[] |
    select(((.title // "") + " " + (.body // "") + " " + (.head.ref // "")) |
      test("issue[- ]?16|#16|08B|aks[- ]?store.*aspire|aspire.*aks[- ]?store"; "i")) |
    "#\(.number) \(.head.ref) \(.html_url)"
  ' <<<"${prs_json}"
)"
[[ -z "${open_pr_conflicts}" ]] || fail "conflicting open PR(s) found: ${open_pr_conflicts}"

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

"${context_script}" "${context_result}" >/dev/null
[[ -s "${context_md}" ]] || fail "context markdown was not created: ${context_md}"
[[ -s "${context_json}" ]] || fail "context json was not created: ${context_json}"
context_md_hash="$(sha256sum "${context_md}" | awk '{print $1}')"
context_json_hash="$(sha256sum "${context_json}" | awk '{print $1}')"

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
        ["Implementing", "notify:openclaw:primary", "owner:Josefina", "developer:senior", "review:human"]
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
    previousLabel: "Implementing",
    name: $name,
    level: "senior",
    recoveryFrom: "Codex bwrap AppArmor/userns runtime blocker",
    recoveredAt: $now
  }' "${projects_file}" > "${projects_tmp}"
mv "${projects_tmp}" "${projects_file}"
chown devclaw-svc:devclaw-svc "${projects_file}"

run_as_devclaw /usr/local/bin/openclaw gateway call sessions.patch \
  --params "$(jq -nc --arg key "${session_key}" --arg model "${model}" --arg label "${session_label}" '{key:$key, model:$model, label:$label}')" \
  --timeout 30000 \
  --json >/dev/null

task_message="$(cat <<EOF_MESSAGE
SENIOR DEVELOPER recovery task for project "${project}" - issue #${issue_id}

Resume the approved Experiment 08B implementation stage after the DevClaw/Codex runtime blocker was corrected.

Authoritative context packet:
- Markdown: ${context_md}
- JSON: ${context_json}
- Markdown SHA-256: ${context_md_hash}
- JSON SHA-256: ${context_json_hash}

Read the context packet first, then use the issue and comments directly as needed. It contains issue #16, accepted issue #14, merged PR #15, the architecture report, Human Aspire Architecture Approval revisions, and Human Implementation Approval.

Repository: ${repo_full}
Repo checkout: ${repo}
Base branch: ${base_branch}
Implementation branch to create: ${implementation_branch}
Channel: ${channel_id}

Runtime recovery evidence: ${runtime_validation}. The minimal DevClaw/Codex subagent smoke passed after the narrow AppArmor/userns fix.

Boundaries:
- Create and use only branch ${implementation_branch}.
- Implement only under experiments/08-aks-store-demo/02-compose-to-aspire/.
- Treat experiments/08-aks-store-demo/01-compose-baseline/ as immutable read-only input.
- Do not modify Experiment 08A, application source, active skills, cloud resources, workflow guardrails, or autonomous behavior.
- Do not dispatch tester workers, merge, close the issue, or advance beyond developer completion.

Outcome:
- Determine and pin exact compatible .NET SDK and stable Aspire versions before writing implementation code.
- Complete implementation, developer validation, hygiene checks, secret scanning, one draft PR linked to issue #${issue_id}, and a concise issue report.
- Stop before tester dispatch.
- When complete or blocked, call work_finish with role "developer", channelId "${channel_id}", result "done" or "blocked", and a concise summary.
EOF_MESSAGE
)"

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "devclaw-${project}-${issue_id}-developer-userns-recovery-${started_at}" \
  --arg prompt "$(cat "${prompt_file}")" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent", extraSystemPrompt:$prompt}')"

mkdir -p "${state_dir}/workspace/devclaw/audit"
jq -nc \
  --arg time "${started_at}" \
  --arg project "${project}" \
  --arg issue "${issue_id}" \
  --arg sessionKey "${session_key}" \
  --arg branchName "${implementation_branch}" \
  --arg contextMarkdown "${context_md}" \
  --arg contextJson "${context_json}" \
  --arg runtimeValidation "${runtime_validation}" \
  '{
    time:$time,
    project:$project,
    issue:($issue|tonumber),
    role:"developer",
    level:"senior",
    sessionAction:"developer-dispatch-recovery-after-userns-fix",
    sessionKey:$sessionKey,
    implementationBranch:$branchName,
    contextMarkdown:$contextMarkdown,
    contextJson:$contextJson,
    runtimeValidation:$runtimeValidation,
    labelTransition:"Implementation/Implementing/Refining -> Implementing",
    operator:"codex-operator",
    gate:"developer implementation only; tester requires later human instruction"
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
  --arg head "${head}" \
  --arg originHead "${origin_head}" \
  --arg upstream "${upstream}" \
  --arg aheadBehind "${ahead_behind}" \
  --arg implementationBranch "${implementation_branch}" \
  --arg labelsBefore "${labels_before}" \
  --arg labelsAfter "${labels_after}" \
  --arg bodyHash "${body_hash}" \
  --arg sessionKey "${session_key}" \
  --arg contextMarkdown "${context_md}" \
  --arg contextJson "${context_json}" \
  --arg contextMarkdownSha256 "${context_md_hash}" \
  --arg contextJsonSha256 "${context_json_hash}" \
  --arg runtimeValidation "${runtime_validation}" \
  --argjson workerFinal "${worker_final}" \
  --arg agentResult "${agent_result}" \
  '{
    startedAt:$startedAt,
    finishedAt:$finishedAt,
    preDispatch:{
      repo:{branch:$branch, head:$head, originHead:$originHead, upstream:$upstream, aheadBehind:$aheadBehind, clean:true, synchronized:true, implementationBranch:$implementationBranch, implementationBranchAvailable:true},
      issue:{number:16, labelsBefore:$labelsBefore, bodySha256:$bodyHash, noConflictingOpenPr:true},
      context:{markdown:$contextMarkdown, json:$contextJson, markdownSha256:$contextMarkdownSha256, jsonSha256:$contextJsonSha256},
      runtime:{usernsAppArmorFixValidated:true, runtimeValidation:$runtimeValidation, sequential:true, heartbeatDisabled:true, autoMergeDisabled:true, autonomousSkillWorkshopDisabled:true, humanReview:true}
    },
    issue:{number:16, labelTransition:"Implementation/Implementing/Refining -> Implementing", labelsAfter:$labelsAfter},
    developerWorker:{active:($workerFinal.active == true), sessionKey:$sessionKey, final:$workerFinal},
    dispatchAccepted:($agentResult | length > 0),
    agentResult:$agentResult
  }' | tee "${out_file}"
