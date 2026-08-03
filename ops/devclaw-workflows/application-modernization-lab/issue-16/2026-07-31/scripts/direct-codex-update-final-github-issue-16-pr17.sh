#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
issue_id="16"
pr_id="17"
final_head="bdad00156bd9d6035dc400d56b9a5d39fd39d0e7"

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
  local url="$1" payload="$2" file
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
  local url="$1" payload="$2" file
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
[[ "${head_sha}" == "${final_head}" ]] || { echo "unexpected PR head ${head_sha}" >&2; exit 1; }
[[ "${draft}" == "true" ]] || { echo "PR must remain draft" >&2; exit 1; }

body="$(jq -r '.body // ""' <<<"${pr_json}")"
body="${body//Closes #16/Relates to #16}"
final_section="$(cat <<'EOF_SECTION'

## Final Direct Codex Validation - 2026-08-02

Final PR head: `bdad00156bd9d6035dc400d56b9a5d39fd39d0e7`

Codex performed the final combined validation and correction stage directly. No OpenClaw or DevClaw worker, subagent, developer session, tester session, worker dispatch, or worker capability probe was used.

Executed final validation:

- PASS: exact PR head and branch preflight.
- PASS: .NET SDK `10.0.110`, Aspire AppHost SDK `13.4.6`, and AppHost build.
- PASS: Experiment 08A upstream source integrity.
- PASS: clean positive validation.
- PASS: all nine required Aspire/DCP resources.
- PASS: loopback-only `store-front`/`store-admin` exposure.
- PASS: internal-only backend services.
- PASS: product workflow and fresh unique order workflow.
- PASS: RabbitMQ queue/publication evidence.
- PASS: makeline consumption and DocumentDB-backed visibility.
- PASS: makeline restart persistence.
- PASS: RabbitMQ negative validation and fresh-order functional recovery.
- PASS: cleanup isolation with unrelated DCP-labeled resource present.
- PASS: adversarial ownership guardrails for missing, incomplete, stale, and partial unrelated DCP identities.
- PASS: intentional validation failure recovery and cleanup.
- PASS: second fresh clean positive validation after full cleanup.
- PASS: ports `8080`, `8081`, and `18888` released after cleanup checkpoints.
- PASS: Git hygiene, executable mode verification, and secret scan.

Known limitations remain unchanged: DocumentDB is container-local and no durability across DocumentDB container recreation or full reset is claimed; optional `ai-service` remains outside default runtime and PASS criteria.

PR #17 remains draft and `Relates to #16`. This update does not approve merge, mark the PR ready, or close the issue.
EOF_SECTION
)"
if [[ "${body}" != *"## Final Direct Codex Validation - 2026-08-02"* ]]; then
  body="${body}${final_section}"
fi

api_patch "https://api.github.com/repos/${repo_full}/pulls/${pr_id}" \
  "$(jq -nc --arg body "${body}" '{body:$body}')" >/dev/null

issue_report="$(cat <<'EOF_REPORT'
## Final Direct Codex Validation and Correction Report

- Execution model: direct Codex execution only. No OpenClaw or DevClaw worker, subagent, developer session, tester session, worker dispatch, or worker capability probe was used.
- Final PR head: `bdad00156bd9d6035dc400d56b9a5d39fd39d0e7`.
- Correction performed in this final stage: added committed adversarial ownership guardrail validation for missing, incomplete, stale, and partial unrelated DCP identity states; updated README, validation plan, and developer validation evidence.
- Positive validation: PASS.
- Negative and recovery validation: PASS.
- Cleanup isolation: PASS.
- Adversarial ownership guardrails: PASS.
- Intentional failure recovery and cleanup: PASS.
- Fresh repeatability: PASS via a second fresh clean positive validation after full cleanup.
- Runtime cleanup: PASS; ports `8080`, `8081`, and `18888` were released after cleanup checkpoints and no Experiment 08B containers remained.
- Repository hygiene: PASS for Experiment 08A integrity, `git diff --check`, executable modes, no tracked `.local` runtime evidence, and secret scan.
- Known limitations: DocumentDB remains container-local; no durability across DocumentDB container recreation or full reset is claimed. Optional `ai-service` remains outside default runtime and PASS criteria.
- Readiness: ready for human PR approval and project closeout review.

This report does not approve merge, mark PR #17 ready, merge the PR, or close issue #16.
EOF_REPORT
)"

comment_json="$(api_post "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments" \
  "$(jq -nc --arg body "${issue_report}" '{body:$body}')")"

jq -n \
  --arg prHead "${final_head}" \
  --arg prUrl "$(jq -r '.html_url' <<<"${pr_json}")" \
  --arg commentUrl "$(jq -r '.html_url' <<<"${comment_json}")" \
  '{prHead:$prHead, prUrl:$prUrl, issueCommentUrl:$commentUrl, prRemainedDraft:true}'
