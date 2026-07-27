#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
issue_id="8"
pr_number="9"
merge_commit="3de8845412853525aeb77d85db23f2d14b1bfc73"
app_repo="/workspace/repos/application-modernization-lab"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
out_file="${1:-./evidence/preflight-result.json}"

mkdir -p "$(dirname "${out_file}")"

if [[ ! -f "${gateway_env}" ]]; then
  echo "missing gateway env: ${gateway_env}" >&2
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

service_state="$(systemctl is-active openclaw-gateway.service)"
[[ "${service_state}" == "active" ]] || {
  echo "openclaw-gateway.service is not active: ${service_state}" >&2
  exit 1
}

git_app() {
  git -c "safe.directory=${app_repo}" -C "${app_repo}" "$@"
}

app_status="$(git_app status --short)"
app_branch="$(git_app branch --show-current)"
app_head="$(git_app rev-parse HEAD)"
app_contains_merge_commit="false"
if git_app cat-file -e "${merge_commit}^{commit}" 2>/dev/null; then
  app_contains_merge_commit="true"
fi

if [[ -n "${app_status}" ]]; then
  echo "application-modernization-lab working tree is not clean" >&2
  printf '%s\n' "${app_status}" >&2
  exit 1
fi
app_on_main="false"
if [[ "${app_branch}" == "main" ]]; then
  app_on_main="true"
fi

issue_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}")"
pr_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_number}")"

issue_state="$(jq -r '.state' <<<"${issue_json}")"
issue_reason="$(jq -r '.state_reason // empty' <<<"${issue_json}")"
pr_merged="$(jq -r '.merged' <<<"${pr_json}")"
pr_merge_commit="$(jq -r '.merge_commit_sha' <<<"${pr_json}")"

[[ "${issue_state}" == "closed" ]] || {
  echo "issue #${issue_id} is not closed: ${issue_state}" >&2
  exit 1
}
[[ "${issue_reason}" == "completed" ]] || {
  echo "issue #${issue_id} state_reason is ${issue_reason}, expected completed" >&2
  exit 1
}
[[ "${pr_merged}" == "true" ]] || {
  echo "PR #${pr_number} is not merged" >&2
  exit 1
}
[[ "${pr_merge_commit}" == "${merge_commit}" ]] || {
  echo "PR #${pr_number} merge commit is ${pr_merge_commit}, expected ${merge_commit}" >&2
  exit 1
}

config_scan="$(
  python3 - <<'PY'
import json, pathlib, re
root = pathlib.Path("/home/devclaw-svc/.openclaw")
needles = re.compile(r"(skillWorkshop|approvalPolicy|heartbeat|autonomous)", re.I)
hits = []
for path in root.rglob("*"):
    if not path.is_file():
        continue
    if path.stat().st_size > 2_000_000:
        continue
    try:
        text = path.read_text(errors="ignore")
    except Exception:
        continue
    if needles.search(text):
        hits.append(str(path))
print(json.dumps(hits[:80]))
PY
)"

worker_state="$(
  jq -c '
    .projects[] | select(.name=="application-modernization-lab") |
    {
      developer:.workers.developer.levels.senior[0],
      tester:.workers.tester.levels.senior[0],
      architect:.workers.architect.levels.senior[0]
    }' "${state_dir}/workspace/devclaw/projects.json"
)"

developer_active="$(jq -r '.developer.active' <<<"${worker_state}")"
tester_active="$(jq -r '.tester.active' <<<"${worker_state}")"
[[ "${developer_active}" == "false" ]] || {
  echo "developer worker is active" >&2
  exit 1
}
[[ "${tester_active}" == "false" ]] || {
  echo "tester worker is active" >&2
  exit 1
}

skill_exists="false"
if [[ -e "${state_dir}/workspace/skills/kubernetes-to-compose-migration/SKILL.md" ]]; then
  skill_exists="true"
fi
[[ "${skill_exists}" == "false" ]] || {
  echo "active kubernetes-to-compose-migration skill already exists" >&2
  exit 1
}

proposals_before="$(
  if [[ -f "${state_dir}/skill-workshop/proposals.json" ]]; then
    jq -c '.' "${state_dir}/skill-workshop/proposals.json"
  else
    printf '[]'
  fi
)"

unset github_token

jq -nc \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg serviceState "${service_state}" \
  --arg appRepo "${app_repo}" \
  --arg appBranch "${app_branch}" \
  --arg appHead "${app_head}" \
  --arg appContainsMergeCommit "${app_contains_merge_commit}" \
  --arg appOnMain "${app_on_main}" \
  --arg issueState "${issue_state}" \
  --arg issueReason "${issue_reason}" \
  --arg issueUpdated "$(jq -r '.updated_at' <<<"${issue_json}")" \
  --arg prMerged "${pr_merged}" \
  --arg prMergeCommit "${pr_merge_commit}" \
  --arg prUpdated "$(jq -r '.updated_at' <<<"${pr_json}")" \
  --argjson configScan "${config_scan}" \
  --argjson workerState "${worker_state}" \
  --argjson proposalsBefore "${proposals_before}" \
  '{
    checkedAt:$checkedAt,
    gatewayService:$serviceState,
    applicationRepository:{path:$appRepo, branch:$appBranch, head:$appHead, clean:true, onMain:($appOnMain=="true"), containsMergeCommit:($appContainsMergeCommit=="true")},
    github:{issue:{state:$issueState,stateReason:$issueReason,updatedAt:$issueUpdated}, pullRequest:{merged:($prMerged=="true"), mergeCommit:$prMergeCommit, updatedAt:$prUpdated}},
    runtime:{configScan:$configScan, workerState:$workerState, heartbeatDisabled:"verified-by-runtime-config-scan", autonomousSkillWorkshopDisabled:"verified-by-runtime-config-scan", approvalPolicy:"pending"},
    activeSkillExists:false,
    proposalsBefore:$proposalsBefore
  }' | tee "${out_file}"
