#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
issue_id="16"
pr_id="17"
expected_head="6722ff491c2a9053a9f76b4bb9223b64f3ec6b3b"
repo="/workspace/repos/application-modernization-lab"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
projects_file="${state_dir}/workspace/devclaw/projects.json"
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/correction-recovery"
out_dir="${1:-${root}/preserve-worktree-$(date -u +%Y%m%dT%H%M%SZ)}"

fail() {
  printf '[preserve-issue-16-pr17-correction-worktree-before-recovery] ERROR: %s\n' "$*" >&2
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

[[ "${EUID}" -eq 0 ]] || fail "must run as root on Agent DevBox"
command -v git >/dev/null 2>&1 || fail "missing git"
command -v jq >/dev/null 2>&1 || fail "missing jq"
command -v curl >/dev/null 2>&1 || fail "missing curl"
command -v tar >/dev/null 2>&1 || fail "missing tar"
[[ -d "${repo}/.git" ]] || fail "missing repository checkout: ${repo}"
[[ -f "${gateway_env}" ]] || fail "missing gateway env"
[[ -f "${projects_file}" ]] || fail "missing projects.json"
[[ -f "${sessions_file}" ]] || fail "missing sessions.json"
[[ -S /run/devclaw/github-token-broker.sock ]] || fail "missing GitHub token broker socket"

set -a
# shellcheck disable=SC1090
source "${gateway_env}"
set +a

mkdir -p "${out_dir}/untracked-files" "${out_dir}/metadata"
chown -R devclaw-svc:devclaw-svc "${out_dir}"

gateway_status="$(run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000)"
active_tasks="$(jq -r '.tasks.active // -1' <<<"${gateway_status}")"
[[ "${active_tasks}" == "0" ]] || fail "Gateway still has active tasks: ${active_tasks}"

worker="$(
  jq -c --arg project "${project}" \
    '.projects[] | select(.name==$project).workers.developer.levels.senior[0]' \
    "${projects_file}"
)"
session_key="$(jq -r '.sessionKey // empty' <<<"${worker}")"
session="$(
  if [[ -n "${session_key}" ]]; then
    jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
)"
session_status="$(jq -r '.status // "missing"' <<<"${session}")"
case "${session_status}" in
  done|failed|missing|null|"") ;;
  *) fail "previous correction session is still active/non-terminal: ${session_status}" ;;
esac

branch="$(run_as_devclaw git -C "${repo}" branch --show-current)"
head="$(run_as_devclaw git -C "${repo}" rev-parse HEAD)"
head_tree="$(run_as_devclaw git -C "${repo}" rev-parse 'HEAD^{tree}')"

run_as_devclaw git -C "${repo}" status --short > "${out_dir}/git-status-short.txt"
run_as_devclaw git -C "${repo}" status --short --branch > "${out_dir}/git-status-short-branch.txt"
run_as_devclaw git -C "${repo}" diff --no-ext-diff > "${out_dir}/git-diff.patch"
run_as_devclaw git -C "${repo}" diff --no-ext-diff --binary > "${out_dir}/git-diff-binary.patch"
run_as_devclaw git -C "${repo}" diff --no-ext-diff --cached --binary > "${out_dir}/git-diff-cached-binary.patch"
run_as_devclaw git -C "${repo}" diff --no-ext-diff --binary HEAD -- > "${out_dir}/git-diff-head-binary.patch"
run_as_devclaw git -C "${repo}" ls-files --others --exclude-standard > "${out_dir}/untracked-files.txt"
run_as_devclaw git -C "${repo}" status --porcelain=v1 -z > "${out_dir}/git-status-porcelain-v1.z"
run_as_devclaw git -C "${repo}" ls-files --others --exclude-standard -z > "${out_dir}/untracked-files.z"

if [[ -s "${out_dir}/untracked-files.z" ]]; then
  run_as_devclaw tar -C "${repo}" --null -T "${out_dir}/untracked-files.z" -cf "${out_dir}/untracked-files.tar"
  tar -C "${out_dir}/untracked-files" -xf "${out_dir}/untracked-files.tar"
fi

{
  printf 'branch=%s\n' "${branch}"
  printf 'head=%s\n' "${head}"
  printf 'headTree=%s\n' "${head_tree}"
  printf 'capturedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} | tee "${out_dir}/metadata/branch-head.txt" >/dev/null

find "${repo}/experiments/08-aks-store-demo/02-compose-to-aspire" \
  -type f \( -name '*.sh' -o -name '*.ps1' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.cmd' -o -name '*.bat' \) \
  -printf '%M %m %u:%g %p\n' \
  > "${out_dir}/script-file-modes.txt" 2>/dev/null || true

github_token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r '.token // empty'
)"
[[ -n "${github_token}" ]] || fail "GitHub token broker did not return a token"

pr_json="$(
  curl --silent --show-error --fail-with-body -K - <<EOF_CURL
url = "https://api.github.com/repos/${repo_full}/pulls/${pr_id}"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
)"
printf '%s' "${pr_json}" > "${out_dir}/github-pr-17.json"
remote_head="$(jq -r '.head.sha' <<<"${pr_json}")"
remote_ref="$(jq -r '.head.ref' <<<"${pr_json}")"
pr_state="$(jq -r '.state' <<<"${pr_json}")"
pr_draft="$(jq -r '.draft' <<<"${pr_json}")"
[[ "${remote_head}" == "${expected_head}" ]] || fail "remote PR head ${remote_head} does not match expected ${expected_head}"

jq -n \
  --arg capturedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg outDir "${out_dir}" \
  --arg branch "${branch}" \
  --arg head "${head}" \
  --arg expectedRemoteHead "${expected_head}" \
  --arg remoteHead "${remote_head}" \
  --arg remoteRef "${remote_ref}" \
  --arg prState "${pr_state}" \
  --arg prDraft "${pr_draft}" \
  --argjson gatewayTasks "$(jq '.tasks' <<<"${gateway_status}")" \
  --argjson worker "${worker}" \
  --argjson session "${session}" \
  '{
    capturedAt:$capturedAt,
    outDir:$outDir,
    previousCorrectionSessionNoLongerActive:true,
    gatewayTasks:$gatewayTasks,
    developerWorker:$worker,
    developerSession:$session,
    repository:{branch:$branch, head:$head},
    pullRequest:{number:17, state:$prState, draft:($prDraft == "true"), headRef:$remoteRef, headSha:$remoteHead, expectedHead:$expectedRemoteHead},
    artifacts:{
      statusShort:"git-status-short.txt",
      completeDiff:"git-diff.patch",
      binaryPatch:"git-diff-binary.patch",
      headBinaryPatch:"git-diff-head-binary.patch",
      cachedBinaryPatch:"git-diff-cached-binary.patch",
      untrackedList:"untracked-files.txt",
      untrackedArchive:"untracked-files.tar",
      scriptModes:"script-file-modes.txt"
    }
  }' | tee "${out_dir}/preserve-summary.json"

printf '%s\n' "${out_dir}" | tee "${root}/latest-preserve-worktree-dir.txt"
