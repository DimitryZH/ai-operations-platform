#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="16"
repo="/workspace/repos/application-modernization-lab"
base_branch="main"
implementation_branch="experiment-08/aks-store-aspire-migration"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
projects_file="${state_dir}/workspace/devclaw/projects.json"
workflow_file="${state_dir}/workspace/devclaw/projects/${project}/workflow.yaml"
boundary_file="${state_dir}/workspace/devclaw/stage6-boundary.json"
developer_prompt="${state_dir}/workspace/devclaw/projects/${project}/prompts/developer.md"
compose_skill="${state_dir}/workspace/skills/compose-to-aspire-migration/SKILL.md"
out_file="${1:-$(dirname "$0")/../results/developer-preflight-result.json}"

fail() {
  printf '[preflight-issue-16-developer] ERROR: %s\n' "$*" >&2
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
[[ -r "${developer_prompt}" ]] || fail "developer prompt is not readable: ${developer_prompt}"
[[ -r "${compose_skill}" ]] || fail "active Compose-to-Aspire skill is not readable: ${compose_skill}"
[[ -S /run/devclaw/github-token-broker.sock ]] || fail "missing GitHub token broker socket"

set -a
source "${gateway_env}"
set +a

[[ "$(systemctl is-active openclaw-gateway.service)" == "active" ]] ||
  fail "openclaw-gateway.service is not active"
[[ "$(systemctl is-active devclaw-github-token-broker.service)" == "active" ]] ||
  fail "devclaw-github-token-broker.service is not active"

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

issue_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}")"
comments_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments?per_page=100")"
prs_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls?state=open&per_page=100")"

issue_state="$(jq -r '.state' <<<"${issue_json}")"
issue_title="$(jq -r '.title' <<<"${issue_json}")"
labels="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"
body_hash="$(jq -r '.body // ""' <<<"${issue_json}" | sha256sum | awk '{print $1}')"
[[ "${issue_state}" == "open" ]] || fail "issue #${issue_id} must be open; found ${issue_state}"
if ! jq -e 'any(.labels[].name; . == "Human Architecture Approval" or . == "Implementation")' <<<"${issue_json}" >/dev/null; then
  fail "issue #${issue_id} must be at Human Architecture Approval or Implementation gate; labels: ${labels}"
fi
if jq -e 'any(.labels[].name; . == "Implementing" or . == "Validating" or . == "Human Review" or . == "Done" or . == "Rejected" or . == "To Improve" or . == "Refining")' <<<"${issue_json}" >/dev/null; then
  fail "issue #${issue_id} already appears active, blocked, or terminal: ${labels}"
fi

architecture_report_index="$(
  jq -r '
    map((.body // "") | test("Stage 1 Aspire Architecture Research Report|Aspire Architecture Research Report"; "i")) |
    to_entries | map(select(.value == true).key) | max // -1
  ' <<<"${comments_json}"
)"
architecture_approval_index="$(
  jq -r '
    map((((.user.login // "") | test("devclaw-agent|openclaw"; "i") | not) and
      ((.body // "") | test("^## Human Aspire Architecture Approval"; "im")))) |
    to_entries | map(select(.value == true).key) | max // -1
  ' <<<"${comments_json}"
)"
implementation_approval_index="$(
  jq -r '
    map((((.user.login // "") | test("devclaw-agent|openclaw"; "i") | not) and
      ((.body // "") | test("^## Human Implementation Approval"; "im")))) |
    to_entries | map(select(.value == true).key) | max // -1
  ' <<<"${comments_json}"
)"
[[ "${architecture_report_index}" -ge 0 ]] || fail "architect report comment was not found"
[[ "${architecture_approval_index}" -gt "${architecture_report_index}" ]] ||
  fail "Human Aspire Architecture Approval must exist after the architect report"
[[ "${implementation_approval_index}" -gt "${architecture_approval_index}" ]] ||
  fail "Human Implementation Approval must exist after Human Aspire Architecture Approval"

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
  --arg repoPath "${repo}" \
  --arg branch "${branch}" \
  --arg head "${head}" \
  --arg originHead "${origin_head}" \
  --arg upstream "${upstream}" \
  --arg aheadBehind "${ahead_behind}" \
  --arg implementationBranch "${implementation_branch}" \
  --arg issueTitle "${issue_title}" \
  --arg issueState "${issue_state}" \
  --arg labels "${labels}" \
  --arg issueUpdated "$(jq -r '.updated_at' <<<"${issue_json}")" \
  --arg bodyHash "${body_hash}" \
  --arg architectureReportIndex "${architecture_report_index}" \
  --arg architectureApprovalIndex "${architecture_approval_index}" \
  --arg implementationApprovalIndex "${implementation_approval_index}" \
  --argjson workerState "${worker_state}" \
  '{
    checkedAt:$checkedAt,
    repository:{path:$repoPath, branch:$branch, head:$head, originHead:$originHead, upstream:$upstream, aheadBehind:$aheadBehind, clean:true, synchronized:true, implementationBranch:$implementationBranch, implementationBranchAvailable:true},
    issue:{number:16, state:$issueState, title:$issueTitle, labels:$labels, updatedAt:$issueUpdated, bodySha256:$bodyHash, architectureReportIndex:($architectureReportIndex|tonumber), architectureApprovalIndex:($architectureApprovalIndex|tonumber), implementationApprovalIndex:($implementationApprovalIndex|tonumber)},
    runtime:{workerState:$workerState, sequential:true, humanReview:true, heartbeatDisabled:true, autoMergeDisabled:true, autonomousSkillWorkshopDisabled:true, approvalPolicy:"pending"},
    github:{tokenBroker:true, noConflictingOpenPr:true},
    skills:{composeToAspireReadable:true}
  }' | tee "${out_file}"
