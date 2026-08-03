#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
project="application-modernization-lab"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
projects_file="${state_dir}/workspace/devclaw/projects.json"
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
session_key="agent:main:subagent:application-modernization-lab-architect-senior-zandra"
out_file="${1:-$(dirname "$0")/../results/recovery-clear-stale-issue-14-architect-worker.json}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

fail() {
  printf '[recovery-clear-stale-issue-14-architect-worker] ERROR: %s\n' "$*" >&2
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
command -v jq >/dev/null 2>&1 || fail "missing jq"
command -v curl >/dev/null 2>&1 || fail "missing curl"
[[ -f "${gateway_env}" ]] || fail "missing gateway env: ${gateway_env}"
[[ -f "${projects_file}" ]] || fail "missing projects.json: ${projects_file}"

set -a
source "${gateway_env}"
set +a

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

issue14_json="$(api_get "https://api.github.com/repos/${repo_full}/issues/14")"
pr15_json="$(api_get "https://api.github.com/repos/${repo_full}/pulls/15")"
issue14_state="$(jq -r '.state' <<<"${issue14_json}")"
issue14_labels="$(jq -r '[.labels[].name] | join(", ")' <<<"${issue14_json}")"
pr15_merged="$(jq -r '.merged' <<<"${pr15_json}")"
[[ "${issue14_state}" == "closed" ]] || fail "issue #14 must be closed before clearing stale worker; found ${issue14_state}"
grep -Eq '(^|, )Done(, |$)' <<<"${issue14_labels}" || fail "issue #14 must have Done label; found ${issue14_labels}"
[[ "${pr15_merged}" == "true" ]] || fail "PR #15 must be merged before clearing stale worker"

before_worker="$(
  jq -c --arg project "${project}" '
    .projects[] | select(.name==$project).workers.architect.levels.senior[0]
  ' "${projects_file}"
)"
before_issue="$(jq -r '.issueId // empty' <<<"${before_worker}")"
before_active="$(jq -r '.active // false' <<<"${before_worker}")"
[[ "${before_active}" == "true" && "${before_issue}" == "14" ]] ||
  fail "architect worker is not the expected stale issue #14 worker: ${before_worker}"

session_before="$(
  if [[ -f "${sessions_file}" ]]; then
    jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
)"

run_as_devclaw /usr/local/bin/openclaw gateway call sessions.delete \
  --params "$(jq -nc --arg key "${session_key}" '{key:$key}')" \
  --timeout 10000 \
  --json >/dev/null 2>&1 || true

projects_tmp="$(mktemp)"
jq --arg project "${project}" --arg now "${started_at}" '
  (.projects[] | select(.name==$project).workers.architect.levels.senior[0].active) = false |
  (.projects[] | select(.name==$project).workers.architect.levels.senior[0].recoveredAt) = $now |
  (.projects[] | select(.name==$project).workers.architect.levels.senior[0].recoveryReason) = "stale issue #14 architect worker cleared after issue closure and PR merge"
' "${projects_file}" > "${projects_tmp}"
mv "${projects_tmp}" "${projects_file}"
chown devclaw-svc:devclaw-svc "${projects_file}"

after_worker="$(
  jq -c --arg project "${project}" '
    .projects[] | select(.name==$project).workers.architect.levels.senior[0]
  ' "${projects_file}"
)"

mkdir -p "$(dirname "${out_file}")"
jq -nc \
  --arg startedAt "${started_at}" \
  --arg finishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg issue14State "${issue14_state}" \
  --arg issue14Labels "${issue14_labels}" \
  --arg pr15Merged "${pr15_merged}" \
  --arg pr15MergeCommit "$(jq -r '.merge_commit_sha // empty' <<<"${pr15_json}")" \
  --argjson beforeWorker "${before_worker}" \
  --argjson afterWorker "${after_worker}" \
  --argjson sessionBefore "${session_before}" \
  '{
    startedAt:$startedAt,
    finishedAt:$finishedAt,
    verified:{issue14:{state:$issue14State, labels:$issue14Labels}, pr15:{merged:($pr15Merged=="true"), mergeCommit:$pr15MergeCommit}},
    recovery:"cleared stale issue #14 senior architect worker and deleted stale architect session key if present",
    beforeWorker:$beforeWorker,
    afterWorker:$afterWorker,
    sessionBefore:$sessionBefore
  }' | tee "${out_file}"
