#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
issue_id="16"
accepted_baseline_issue_id="14"
accepted_baseline_pr_id="15"
workflow_root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31"
context_dir="${workflow_root}/context"
result_file="${1:-${workflow_root}/results/issue-16-developer-context-packet.json}"

fail() {
  printf '[prepare-issue-16-developer-context-packet] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v curl >/dev/null 2>&1 || fail "missing curl"
command -v jq >/dev/null 2>&1 || fail "missing jq"
command -v sha256sum >/dev/null 2>&1 || fail "missing sha256sum"
[[ -S /run/devclaw/github-token-broker.sock ]] || fail "missing GitHub token broker socket"

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

mkdir -p "${context_dir}" "$(dirname "${result_file}")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
issue16_file="${tmp_dir}/issue16.json"
issue16_comments_file="${tmp_dir}/issue16-comments.json"
issue14_file="${tmp_dir}/issue14.json"
issue14_comments_file="${tmp_dir}/issue14-comments.json"
pr15_file="${tmp_dir}/pr15.json"
pr15_files_file="${tmp_dir}/pr15-files.json"
pr15_commits_file="${tmp_dir}/pr15-commits.json"

api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}" > "${issue16_file}"
api_get "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments?per_page=100" > "${issue16_comments_file}"
api_get "https://api.github.com/repos/${repo_full}/issues/${accepted_baseline_issue_id}" > "${issue14_file}"
api_get "https://api.github.com/repos/${repo_full}/issues/${accepted_baseline_issue_id}/comments?per_page=100" > "${issue14_comments_file}"
api_get "https://api.github.com/repos/${repo_full}/pulls/${accepted_baseline_pr_id}" > "${pr15_file}"
api_get "https://api.github.com/repos/${repo_full}/pulls/${accepted_baseline_pr_id}/files?per_page=100" > "${pr15_files_file}"
api_get "https://api.github.com/repos/${repo_full}/pulls/${accepted_baseline_pr_id}/commits?per_page=100" > "${pr15_commits_file}"

issue16_state="$(jq -r '.state' "${issue16_file}")"
issue16_labels="$(jq -r '[.labels[].name] | join(", ")' "${issue16_file}")"
issue14_state="$(jq -r '.state' "${issue14_file}")"
pr15_merged="$(jq -r '.merged' "${pr15_file}")"
[[ "${issue16_state}" == "open" ]] || fail "issue #${issue_id} must be open; found ${issue16_state}"
[[ "${issue14_state}" == "closed" ]] || fail "accepted baseline issue #${accepted_baseline_issue_id} must be closed; found ${issue14_state}"
[[ "${pr15_merged}" == "true" ]] || fail "accepted baseline PR #${accepted_baseline_pr_id} must be merged; found merged=${pr15_merged}"

architecture_report_index="$(jq -r 'map((.body // "") | test("Stage 1 Aspire Architecture Research Report|Aspire Architecture Research Report"; "i")) | to_entries | map(select(.value == true).key) | max // -1' "${issue16_comments_file}")"
architecture_approval_index="$(jq -r 'map((((.user.login // "") | test("devclaw-agent|openclaw"; "i") | not) and ((.body // "") | test("^## Human Aspire Architecture Approval"; "im")))) | to_entries | map(select(.value == true).key) | max // -1' "${issue16_comments_file}")"
implementation_approval_index="$(jq -r 'map((((.user.login // "") | test("devclaw-agent|openclaw"; "i") | not) and ((.body // "") | test("^## Human Implementation Approval"; "im")))) | to_entries | map(select(.value == true).key) | max // -1' "${issue16_comments_file}")"
[[ "${architecture_report_index}" -ge 0 ]] || fail "architect report comment was not found"
[[ "${architecture_approval_index}" -gt "${architecture_report_index}" ]] || fail "Human Aspire Architecture Approval must exist after the architect report"
[[ "${implementation_approval_index}" -gt "${architecture_approval_index}" ]] || fail "Human Implementation Approval must exist after Human Aspire Architecture Approval"

context_json="${context_dir}/issue-16-authoritative-context.json"
context_md="${context_dir}/issue-16-authoritative-context.md"

jq -n \
  --arg checkedAt "${checked_at}" \
  --arg repoFull "${repo_full}" \
  --slurpfile issue16 "${issue16_file}" \
  --slurpfile issue16Comments "${issue16_comments_file}" \
  --slurpfile issue14 "${issue14_file}" \
  --slurpfile issue14Comments "${issue14_comments_file}" \
  --slurpfile pr15 "${pr15_file}" \
  --slurpfile pr15Files "${pr15_files_file}" \
  --slurpfile pr15Commits "${pr15_commits_file}" \
  --arg architectureReportIndex "${architecture_report_index}" \
  --arg architectureApprovalIndex "${architecture_approval_index}" \
  --arg implementationApprovalIndex "${implementation_approval_index}" \
  '{
    generatedAt:$checkedAt,
    source:"GitHub API via DevClaw GitHub token broker",
    repository:$repoFull,
    currentIssue:$issue16[0],
    currentIssueComments:$issue16Comments[0],
    acceptedBaseline:{issue:$issue14[0], comments:$issue14Comments[0], pullRequest:$pr15[0], files:$pr15Files[0], commits:$pr15Commits[0]},
    gates:{
      architectureReportCommentIndex:($architectureReportIndex|tonumber),
      humanAspireArchitectureApprovalCommentIndex:($architectureApprovalIndex|tonumber),
      humanImplementationApprovalCommentIndex:($implementationApprovalIndex|tonumber)
    }
  }' > "${context_json}"

{
  printf '# Issue 16 Authoritative Developer Context\n\n'
  printf 'Generated: %s\n\n' "${checked_at}"
  printf 'Source: GitHub API via DevClaw GitHub token broker.\n\n'
  printf '## Current Issue #16\n\n'
  jq -r '"Title: " + .title + "\nState: " + .state + "\nLabels: " + ([.labels[].name] | join(", ")) + "\nURL: " + .html_url + "\n\n### Body\n\n" + (.body // "")' "${issue16_file}"
  printf '\n\n## Current Issue #16 Comments\n\n'
  jq -r '.[] | "### Comment by " + .user.login + " at " + .created_at + "\n\n" + (.body // "") + "\n"' "${issue16_comments_file}"
  printf '\n\n## Accepted Baseline Issue #14\n\n'
  jq -r '"Title: " + .title + "\nState: " + .state + "\nLabels: " + ([.labels[].name] | join(", ")) + "\nURL: " + .html_url + "\n\n### Body\n\n" + (.body // "")' "${issue14_file}"
  printf '\n\n## Accepted Baseline Issue #14 Comments\n\n'
  jq -r '.[] | "### Comment by " + .user.login + " at " + .created_at + "\n\n" + (.body // "") + "\n"' "${issue14_comments_file}"
  printf '\n\n## Accepted Baseline PR #15\n\n'
  jq -r '"Title: " + .title + "\nMerged: " + (.merged|tostring) + "\nMerge commit: " + (.merge_commit_sha // "") + "\nHead SHA: " + .head.sha + "\nURL: " + .html_url + "\n\n### Body\n\n" + (.body // "")' "${pr15_file}"
  printf '\n\n### PR #15 Files\n\n'
  jq -r '.[] | "- " + .filename + " (" + .status + ", +" + (.additions|tostring) + "/-" + (.deletions|tostring) + ")"' "${pr15_files_file}"
  printf '\n\n### PR #15 Commits\n\n'
  jq -r '.[] | "- " + .sha + " " + (.commit.message | split("\n")[0])' "${pr15_commits_file}"
} > "${context_md}"

chown -R devclaw-svc:devclaw-svc "${context_dir}" "$(dirname "${result_file}")"
chmod 0640 "${context_json}" "${context_md}"

jq -n \
  --arg generatedAt "${checked_at}" \
  --arg contextJson "${context_json}" \
  --arg contextMarkdown "${context_md}" \
  --arg issue16Labels "${issue16_labels}" \
  --arg architectureReportIndex "${architecture_report_index}" \
  --arg architectureApprovalIndex "${architecture_approval_index}" \
  --arg implementationApprovalIndex "${implementation_approval_index}" \
  --arg contextJsonSha256 "$(sha256sum "${context_json}" | awk '{print $1}')" \
  --arg contextMarkdownSha256 "$(sha256sum "${context_md}" | awk '{print $1}')" \
  '{
    generatedAt:$generatedAt,
    contextJson:$contextJson,
    contextMarkdown:$contextMarkdown,
    contextJsonSha256:$contextJsonSha256,
    contextMarkdownSha256:$contextMarkdownSha256,
    issue:{number:16, labels:$issue16Labels},
    acceptedBaseline:{issue:14, pullRequest:15, issueClosed:true, pullRequestMerged:true},
    gates:{
      architectureReportCommentIndex:($architectureReportIndex|tonumber),
      humanAspireArchitectureApprovalCommentIndex:($architectureApprovalIndex|tonumber),
      humanImplementationApprovalCommentIndex:($implementationApprovalIndex|tonumber)
    }
  }' | tee "${result_file}"
