#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="16"
repo="/workspace/repos/application-modernization-lab"
base_branch="main"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
projects_file="${state_dir}/workspace/devclaw/projects.json"
workflow_file="${state_dir}/workspace/devclaw/projects/${project}/workflow.yaml"
boundary_file="${state_dir}/workspace/devclaw/stage6-boundary.json"
architect_prompt="${state_dir}/workspace/devclaw/projects/${project}/prompts/architect.md"
compose_skill="${state_dir}/workspace/skills/compose-to-aspire-migration/SKILL.md"
out_file="${1:-$(dirname "$0")/../results/preflight-result.json}"

fail() {
  printf '[preflight-issue-16-architect] ERROR: %s\n' "$*" >&2
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
[[ -f "${projects_file}" ]] || fail "missing projects.json: ${projects_file}"
[[ -f "${workflow_file}" ]] || fail "missing workflow: ${workflow_file}"
[[ -f "${boundary_file}" ]] || fail "missing stage boundary: ${boundary_file}"
[[ -r "${architect_prompt}" ]] || fail "architect prompt is not readable: ${architect_prompt}"
[[ -r "${compose_skill}" ]] || fail "active Compose-to-Aspire skill is not readable: ${compose_skill}"

set -a
source "${gateway_env}"
set +a

service_state="$(systemctl is-active openclaw-gateway.service)"
[[ "${service_state}" == "active" ]] || fail "openclaw-gateway.service is not active: ${service_state}"

pre_status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"
[[ -z "${pre_status}" ]] || fail "repository worktree is dirty before sync: ${pre_status}"

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
  fail "missing accepted 08A baseline directory"
[[ -f "${repo}/experiments/08-aks-store-demo/01-compose-baseline/compose.yaml" || -f "${repo}/experiments/08-aks-store-demo/01-compose-baseline/docker-compose.yml" || -f "${repo}/experiments/08-aks-store-demo/01-compose-baseline/docker-compose.yaml" ]] ||
  fail "accepted 08A baseline directory does not contain a compose file"

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

issue_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}")"
comments_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments?per_page=100")"
issue14_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/14")"
pr15_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/15")"

issue_state="$(jq -r '.state' <<<"${issue_json}")"
issue_title="$(jq -r '.title' <<<"${issue_json}")"
labels="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"
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
  fail "issue #${issue_id} already appears active, gated, blocked, or terminal: ${labels}"
fi
[[ "$(jq -r '.state' <<<"${issue14_json}")" == "closed" ]] || fail "issue #14 must be closed"
[[ "$(jq -r '.merged' <<<"${pr15_json}")" == "true" ]] || fail "PR #15 must be merged"

worker_state="$(
  jq -c --arg project "${project}" '
    .projects[] | select(.name==$project) |
    {
      architect:.workers.architect.levels.senior[0],
      developer:.workers.developer.levels.senior[0],
      tester:.workers.tester.levels.senior[0]
    }' "${projects_file}"
)"

mkdir -p "$(dirname "${out_file}")"
jq -nc \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg serviceState "${service_state}" \
  --arg repoPath "${repo}" \
  --arg branch "${branch}" \
  --arg head "${head}" \
  --arg originHead "${origin_head}" \
  --arg upstream "${upstream}" \
  --arg aheadBehind "${ahead_behind}" \
  --arg issueTitle "${issue_title}" \
  --arg issueState "${issue_state}" \
  --arg labels "${labels}" \
  --arg issueUpdated "$(jq -r '.updated_at' <<<"${issue_json}")" \
  --arg bodyHash "${body_hash}" \
  --argjson approvalFound "${approval_found}" \
  --arg workflowHumanGate "${workflow_human_gate}" \
  --argjson workerState "${worker_state}" \
  --arg issue14State "$(jq -r '.state' <<<"${issue14_json}")" \
  --arg issue14Labels "$(jq -r '[.labels[].name] | join(", ")' <<<"${issue14_json}")" \
  --arg pr15Merged "$(jq -r '.merged' <<<"${pr15_json}")" \
  --arg pr15MergeCommit "$(jq -r '.merge_commit_sha // empty' <<<"${pr15_json}")" \
  '{
    checkedAt:$checkedAt,
    gatewayService:$serviceState,
    repository:{path:$repoPath, branch:$branch, head:$head, originHead:$originHead, upstream:$upstream, aheadBehind:$aheadBehind, clean:true, synchronized:true},
    issue:{number:16, state:$issueState, title:$issueTitle, labels:$labels, updatedAt:$issueUpdated, bodySha256:$bodyHash, humanApproval:$approvalFound},
    acceptedInputs:{issue14:{state:$issue14State, labels:$issue14Labels}, pr15:{merged:($pr15Merged=="true"), mergeCommit:$pr15MergeCommit}, composeBaselineDirectoryPresent:true},
    runtime:{workerState:$workerState, sequential:true, humanReview:true, workflowHumanGate:$workflowHumanGate, requestedStopGate:"Human Baseline Approval", heartbeatDisabled:true, autoMergeDisabled:true, autonomousSkillWorkshopDisabled:true, approvalPolicy:"pending"},
    skills:{composeToAspireReadable:true}
  }' | tee "${out_file}"
