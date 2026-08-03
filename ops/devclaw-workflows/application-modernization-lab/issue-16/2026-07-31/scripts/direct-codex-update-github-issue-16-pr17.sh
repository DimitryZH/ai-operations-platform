#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
issue_id="16"
pr_id="17"
new_head="406860ff73d7a6387911eff3110d24f2601fda5a"

token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r '.token // empty'
)"
[[ -n "${token}" ]] || { echo "missing GitHub token" >&2; exit 1; }

api_get() {
  curl --silent --show-error --fail-with-body -K - <<EOF_CURL
url = "$1"
header = "Authorization: Bearer ${token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
}

api_patch() {
  local url="$1" payload="$2"
  local file
  file="$(mktemp)"
  printf '%s' "${payload}" > "${file}"
  curl --silent --show-error --fail-with-body -X PATCH --data-binary @"${file}" -K - <<EOF_CURL
url = "${url}"
header = "Authorization: Bearer ${token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
  rm -f "${file}"
}

api_post() {
  local url="$1" payload="$2"
  local file
  file="$(mktemp)"
  printf '%s' "${payload}" > "${file}"
  curl --silent --show-error --fail-with-body -X POST --data-binary @"${file}" -K - <<EOF_CURL
url = "${url}"
header = "Authorization: Bearer ${token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
  rm -f "${file}"
}

pr_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/${pr_id}")"
head_sha="$(jq -r '.head.sha' <<<"${pr_json}")"
draft="$(jq -r '.draft' <<<"${pr_json}")"
[[ "${head_sha}" == "${new_head}" ]] || { echo "unexpected PR head ${head_sha}" >&2; exit 1; }
[[ "${draft}" == "true" ]] || { echo "PR must remain draft" >&2; exit 1; }

body="$(jq -r '.body // ""' <<<"${pr_json}")"
body="${body//Closes #16/Relates to #16}"
body="${body//closes #16/Relates to #16}"
validation_section="$(cat <<'EOF_VALIDATION'

## Direct Codex Correction Validation - 2026-08-02

Codex completed the correction directly after the DevClaw worker orchestration experiment was considered sufficient. No DevClaw worker, subagent, developer session, tester session, or worker capability probe was used for this completion pass.

Final PR head: `406860ff73d7a6387911eff3110d24f2601fda5a`

Executed validation:

- PASS: repository and branch preflight on `experiment-08/aks-store-aspire-migration`.
- PASS: Experiment 08A upstream source integrity.
- PASS: .NET SDK `10.0.110`, Aspire AppHost SDK `13.4.6`, and AppHost build.
- PASS: clean positive validation, including all nine required resources, loopback-only UI endpoints, internal-only backend services, product workflow, fresh unique order workflow, RabbitMQ queue/publication evidence, makeline consumption, DocumentDB-backed visibility, and makeline restart persistence.
- PASS: RabbitMQ negative validation and fresh-order functional recovery.
- PASS: cleanup isolation with an unrelated DCP-labeled container present.
- PASS: intentional validation failure recovery and cleanup with diagnostic evidence preserved.
- PASS: second fresh clean positive validation after full cleanup.
- PASS: ports `8080`, `8081`, and `18888` released after cleanup checkpoints.
- PASS: Git hygiene, executable mode verification, and secret scan.

This PR remains draft and `Relates to #16`; this update does not approve merge or close the issue.
EOF_VALIDATION
)"
if [[ "${body}" != *"## Direct Codex Correction Validation - 2026-08-02"* ]]; then
  body="${body}${validation_section}"
fi

api_patch "https://api.github.com/repos/${repo_full}/pulls/${pr_id}" \
  "$(jq -nc --arg body "${body}" '{body:$body}')" >/dev/null

issue_report="$(cat <<'EOF_REPORT'
## Direct Codex Developer Correction Report

- Direct Codex intervention decision: Codex completed the PR #17 correction directly as the operator and implementation agent.
- Reason DevClaw worker orchestration was discontinued: the OpenClaw/DevClaw orchestration evaluation was considered sufficient after repeated worker-runtime, sandbox, filesystem, Docker-access, recovery, and workflow-control failures made continued worker orchestration disproportionate in time and token cost.
- Files and behavior corrected: cleanup and validation scripts now persist AppHost PID/start ticks plus exact DCP creator identity, require the complete owned Experiment 08B resource set, fail safely on missing/stale/ambiguous identity, avoid first-match global Docker selection, start negative validation from a fresh owned AppHost runtime, preserve failure evidence, restore paused workloads/RabbitMQ where applicable, and validate cleanup isolation plus intentional failure cleanup. README, validation plan, migration assessment, and developer validation evidence were updated.
- Exact new PR head: `406860ff73d7a6387911eff3110d24f2601fda5a`.
- Positive validation result: PASS.
- Negative and recovery result: PASS.
- Cleanup isolation result: PASS.
- Intentional failure recovery result: PASS.
- Fresh repeatability result: PASS via a second fresh clean positive validation after full cleanup.
- Repository and secret hygiene: PASS for Experiment 08A integrity, `git diff --check`, executable script modes, no tracked `.local` runtime evidence, and secret scan.
- Remaining limitations: DocumentDB remains container-local; no durability across DocumentDB container recreation or full reset is claimed. Optional `ai-service` remains outside default runtime and PASS criteria.
- Readiness: ready for direct independent Codex validation after human approval.

This report states explicitly that Codex completed the correction directly. No DevClaw worker was used for this completion pass. The change in execution model was a deliberate experiment conclusion, not hidden workflow behavior. This report does not approve merge or close the issue.
EOF_REPORT
)"

comment_json="$(api_post "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments" \
  "$(jq -nc --arg body "${issue_report}" '{body:$body}')")"

jq -n \
  --arg prHead "${new_head}" \
  --arg prUrl "$(jq -r '.html_url' <<<"${pr_json}")" \
  --arg commentUrl "$(jq -r '.html_url' <<<"${comment_json}")" \
  '{prHead:$prHead, prUrl:$prUrl, issueCommentUrl:$commentUrl, prRemainedDraft:true}'
