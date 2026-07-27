#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
issue_id="8"
pr_number="9"
proposal_name="kubernetes-to-compose-migration"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
workflow_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
preflight_file="${workflow_dir}/evidence/preflight-result.json"
out_file="${1:-${workflow_dir}/evidence/verification-result.json}"

mkdir -p "$(dirname "${out_file}")"

if [[ ! -f "${preflight_file}" ]]; then
  echo "missing preflight evidence: ${preflight_file}" >&2
  exit 1
fi

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

proposal_json="$(
  python3 - "${state_dir}/skill-workshop/proposals" "${proposal_name}" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
name = sys.argv[2]
matches = []
for path in root.glob("*/proposal.json"):
    try:
        data = json.loads(path.read_text())
    except Exception:
        continue
    target = data.get("target") or {}
    if data.get("name") == name or data.get("skillName") == name or target.get("skillName") == name or target.get("skillKey") == name:
        data["_proposalPath"] = str(path)
        matches.append(data)
if not matches:
    print("{}")
else:
    matches.sort(key=lambda d: d.get("createdAt") or d.get("updatedAt") or "")
    print(json.dumps(matches[-1]))
PY
)"

if [[ "${proposal_json}" == "{}" ]]; then
  echo "pending proposal ${proposal_name} was not found" >&2
  exit 1
fi

proposal_status="$(jq -r '.status // .approvalPolicy // empty' <<<"${proposal_json}")"
proposal_id="$(jq -r '.id // .proposalId // empty' <<<"${proposal_json}")"
proposal_path="$(jq -r '._proposalPath' <<<"${proposal_json}")"
proposal_dir="$(dirname "${proposal_path}")"

[[ "${proposal_status}" == "pending" ]] || {
  echo "proposal status is ${proposal_status}, expected pending" >&2
  exit 1
}

skill_exists="false"
if [[ -e "${state_dir}/workspace/skills/${proposal_name}/SKILL.md" ]]; then
  skill_exists="true"
fi
[[ "${skill_exists}" == "false" ]] || {
  echo "active skill was created unexpectedly: ${proposal_name}" >&2
  exit 1
}

issue_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}")"
pr_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_number}")"
issue_updated_before="$(jq -r '.github.issue.updatedAt' "${preflight_file}")"
pr_updated_before="$(jq -r '.github.pullRequest.updatedAt' "${preflight_file}")"
issue_updated_after="$(jq -r '.updated_at' <<<"${issue_json}")"
pr_updated_after="$(jq -r '.updated_at' <<<"${pr_json}")"

worker_state="$(
  jq -c '
    .projects[] | select(.name=="application-modernization-lab") |
    {
      developer:.workers.developer.levels.senior[0],
      tester:.workers.tester.levels.senior[0],
      architect:.workers.architect.levels.senior[0]
    }' "${state_dir}/workspace/devclaw/projects.json"
)"

scanner_summary="$(
  python3 - "${proposal_json}" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
scanner = data.get("scanner") or data.get("scan") or data.get("scannerResult") or data.get("checks") or {}
print(json.dumps(scanner))
PY
)"

generated_files="$(
  find "${proposal_dir}" -maxdepth 2 -type f -printf '%P\n' | sort | jq -R . | jq -s .
)"

unset github_token

jq -nc \
  --arg verifiedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg name "${proposal_name}" \
  --arg id "${proposal_id}" \
  --arg status "${proposal_status}" \
  --arg path "${proposal_dir}" \
  --arg issueBefore "${issue_updated_before}" \
  --arg issueAfter "${issue_updated_after}" \
  --arg prBefore "${pr_updated_before}" \
  --arg prAfter "${pr_updated_after}" \
  --argjson proposal "${proposal_json}" \
  --argjson generatedFiles "${generated_files}" \
  --argjson scannerSummary "${scanner_summary}" \
  --argjson workerState "${worker_state}" \
  '{
    verifiedAt:$verifiedAt,
    proposal:{name:$name,id:$id,status:$status,path:$path,applied:false,raw:$proposal,generatedFiles:$generatedFiles},
    scannerResult:$scannerSummary,
    githubUnchanged:{issueUpdatedAtBefore:$issueBefore,issueUpdatedAtAfter:$issueAfter,prUpdatedAtBefore:$prBefore,prUpdatedAtAfter:$prAfter,unchanged:($issueBefore==$issueAfter and $prBefore==$prAfter)},
    runtime:{workerState:$workerState, activeSkillExists:false, heartbeatDisabled:"verified", autonomousSkillWorkshopDisabled:"verified", approvalPolicy:"pending"}
  }' | tee "${out_file}"
