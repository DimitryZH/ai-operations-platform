#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="16"
pr_id="17"
repo="/workspace/repos/application-modernization-lab"
implementation_branch="experiment-08/aks-store-aspire-migration"
expected_head="6722ff491c2a9053a9f76b4bb9223b64f3ec6b3b"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
projects_file="${state_dir}/workspace/devclaw/projects.json"
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
workflow_file="${state_dir}/workspace/devclaw/projects/${project}/workflow.yaml"
boundary_file="${state_dir}/workspace/devclaw/stage6-boundary.json"
developer_prompt="${state_dir}/workspace/devclaw/projects/${project}/prompts/developer.md"
out_file="${1:-/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/results/developer-correction-pr17-preflight.json}"

fail() {
  printf '[preflight-issue-16-targeted-developer-correction-pr17] ERROR: %s\n' "$*" >&2
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
[[ -f "${projects_file}" ]] || fail "missing projects.json"
[[ -f "${sessions_file}" ]] || fail "missing sessions.json"
[[ -f "${workflow_file}" ]] || fail "missing workflow"
[[ -f "${boundary_file}" ]] || fail "missing stage boundary"
[[ -r "${developer_prompt}" ]] || fail "developer prompt is not readable"
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
[[ -z "${pre_status}" ]] || fail "repository worktree is dirty before sync: ${pre_status}"
run_as_devclaw git -C "${repo}" fetch --prune origin
if run_as_devclaw git -C "${repo}" show-ref --verify --quiet "refs/heads/${implementation_branch}"; then
  run_as_devclaw git -C "${repo}" switch "${implementation_branch}" >/dev/null
else
  run_as_devclaw git -C "${repo}" switch --track -c "${implementation_branch}" "origin/${implementation_branch}" >/dev/null
fi
if ! run_as_devclaw git -C "${repo}" pull --ff-only origin "${implementation_branch}" >/dev/null; then
  local_tree="$(run_as_devclaw git -C "${repo}" rev-parse 'HEAD^{tree}')"
  origin_tree="$(run_as_devclaw git -C "${repo}" rev-parse "origin/${implementation_branch}^{tree}")"
  current_status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"
  if [[ -n "${current_status}" || "${local_tree}" != "${origin_tree}" ]]; then
    fail "branch diverged and cannot be safely aligned: status=${current_status}, local_tree=${local_tree}, origin_tree=${origin_tree}"
  fi
  run_as_devclaw git -C "${repo}" reset --hard "origin/${implementation_branch}" >/dev/null
fi

branch="$(run_as_devclaw git -C "${repo}" branch --show-current)"
head="$(run_as_devclaw git -C "${repo}" rev-parse HEAD)"
origin_head="$(run_as_devclaw git -C "${repo}" rev-parse "origin/${implementation_branch}")"
upstream="$(run_as_devclaw git -C "${repo}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [[ -z "${upstream}" ]]; then
  run_as_devclaw git -C "${repo}" branch --set-upstream-to="origin/${implementation_branch}" "${implementation_branch}" >/dev/null
  upstream="$(run_as_devclaw git -C "${repo}" rev-parse --abbrev-ref --symbolic-full-name '@{u}')"
fi
ahead_behind="$(run_as_devclaw git -C "${repo}" rev-list --left-right --count '@{u}...HEAD')"
post_status="$(run_as_devclaw git -C "${repo}" status --porcelain=v1)"

[[ "${branch}" == "${implementation_branch}" ]] || fail "repo branch must be ${implementation_branch}; found ${branch}"
[[ "${head}" == "${expected_head}" ]] || fail "local branch head ${head} does not match expected ${expected_head}"
[[ "${origin_head}" == "${expected_head}" ]] || fail "origin branch head ${origin_head} does not match expected ${expected_head}"
[[ "${upstream}" == "origin/${implementation_branch}" ]] || fail "upstream must be origin/${implementation_branch}; found ${upstream}"
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

issue_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}")"
issue_comments_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments?per_page=100")"
pr_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_id}")"
pr_issue_comments_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${pr_id}/comments?per_page=100")"
pr_reviews_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_id}/reviews?per_page=100")"
pr_review_comments_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_id}/comments?per_page=100")"

issue_state="$(jq -r '.state' <<<"${issue_json}")"
issue_labels="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue_json}")"
pr_state="$(jq -r '.state' <<<"${pr_json}")"
pr_draft="$(jq -r '.draft' <<<"${pr_json}")"
pr_head_ref="$(jq -r '.head.ref' <<<"${pr_json}")"
pr_head_sha="$(jq -r '.head.sha' <<<"${pr_json}")"
pr_base_ref="$(jq -r '.base.ref' <<<"${pr_json}")"
[[ "${issue_state}" == "open" ]] || fail "issue #${issue_id} must be open; found ${issue_state}"
[[ "${pr_state}" == "open" ]] || fail "PR #${pr_id} must be open; found ${pr_state}"
[[ "${pr_draft}" == "true" ]] || fail "PR #${pr_id} must remain draft"
[[ "${pr_head_ref}" == "${implementation_branch}" ]] || fail "PR #${pr_id} head ref ${pr_head_ref} does not match ${implementation_branch}"
[[ "${pr_head_sha}" == "${expected_head}" ]] || fail "PR #${pr_id} head sha ${pr_head_sha} does not match expected ${expected_head}"
[[ "${pr_base_ref}" == "main" ]] || fail "PR #${pr_id} base must be main; found ${pr_base_ref}"

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

mkdir -p "$(dirname "${out_file}")"
jq -nc \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg branch "${branch}" \
  --arg head "${head}" \
  --arg originHead "${origin_head}" \
  --arg upstream "${upstream}" \
  --arg aheadBehind "${ahead_behind}" \
  --arg issueLabels "${issue_labels}" \
  --arg prHeadRef "${pr_head_ref}" \
  --arg prHeadSha "${pr_head_sha}" \
  --arg prBaseRef "${pr_base_ref}" \
  --arg prDraft "${pr_draft}" \
  --argjson gatewayTasks "$(jq '.tasks' <<<"${gateway_status}")" \
  --argjson humanPrCorrectionCount "${human_pr_correction_count}" \
  --argjson humanIssueApprovalCount "${human_issue_approval_count}" \
  '{
    checkedAt:$checkedAt,
    repository:{branch:$branch, head:$head, originHead:$originHead, upstream:$upstream, aheadBehind:$aheadBehind, clean:true},
    issue:{number:16, state:"open", labels:$issueLabels, humanDeveloperCorrectionApprovalFound:($humanIssueApprovalCount >= 1), humanDeveloperCorrectionApprovalCount:$humanIssueApprovalCount},
    pullRequest:{number:17, state:"open", draft:($prDraft == "true"), headRef:$prHeadRef, headSha:$prHeadSha, baseRef:$prBaseRef, humanDeveloperReviewCorrectionsFound:($humanPrCorrectionCount >= 1), humanDeveloperReviewCorrectionCount:$humanPrCorrectionCount},
    runtime:{gatewayTasks:$gatewayTasks, noActiveWorkers:true, sequential:true, heartbeatDisabled:true, autoMergeDisabled:true, autonomousSkillWorkshopDisabled:true, humanReview:true}
  }' | tee "${out_file}"
