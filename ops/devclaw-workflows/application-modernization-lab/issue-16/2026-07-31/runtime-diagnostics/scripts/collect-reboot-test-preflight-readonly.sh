#!/usr/bin/env bash
set -euo pipefail

root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics"
out_dir="${1:-${root}/results/reboot-test-preflight-$(date -u +%Y%m%dT%H%M%SZ)}"
repo="/workspace/repos/application-modernization-lab"
repo_full="DimitryZH/application-modernization-lab"
issue_id="16"
implementation_branch="experiment-08/aks-store-aspire-migration"
state_dir="/home/devclaw-svc/.openclaw"
projects_file="${state_dir}/workspace/devclaw/projects.json"
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"

fail() {
  printf '[collect-reboot-test-preflight-readonly] ERROR: %s\n' "$*" >&2
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

[[ "${EUID}" -eq 0 ]] || fail "must run as root on DevClaw VM"
command -v jq >/dev/null 2>&1 || fail "missing jq"
mkdir -p "${out_dir}"

checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ -f "${gateway_env}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${gateway_env}"
  set +a
fi

gateway_status="$(run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000 2>&1 || true)"
gateway_health="$(run_as_devclaw /usr/local/bin/openclaw gateway call health --json --timeout 10000 2>&1 || true)"
gateway_status_json="$(
  if jq -e . >/dev/null 2>&1 <<<"${gateway_status}"; then
    printf '%s' "${gateway_status}"
  else
    jq -nc --arg raw "${gateway_status}" '{parseError:true, raw:$raw}'
  fi
)"
gateway_health_json="$(
  if jq -e . >/dev/null 2>&1 <<<"${gateway_health}"; then
    printf '%s' "${gateway_health}"
  else
    jq -nc --arg raw "${gateway_health}" '{parseError:true, raw:$raw}'
  fi
)"

repo_branch=""
repo_head=""
repo_status=""
repo_08b_status=""
local_branch_rc=0
remote_branch_rc=0
if [[ -d "${repo}/.git" ]]; then
  repo_branch="$(run_as_devclaw git -C "${repo}" branch --show-current 2>&1 || true)"
  repo_head="$(run_as_devclaw git -C "${repo}" rev-parse HEAD 2>&1 || true)"
  repo_status="$(run_as_devclaw git -C "${repo}" status --short --branch 2>&1 || true)"
  repo_08b_status="$(run_as_devclaw git -C "${repo}" status --short -- experiments/08-aks-store-demo/02-compose-to-aspire 2>&1 || true)"
  run_as_devclaw git -C "${repo}" show-ref --verify --quiet "refs/heads/${implementation_branch}" || local_branch_rc="$?"
  run_as_devclaw git -C "${repo}" ls-remote --exit-code --heads origin "${implementation_branch}" >/dev/null 2>&1 || remote_branch_rc="$?"
fi

active_workers="[]"
if [[ -f "${projects_file}" ]]; then
  active_workers="$(
    jq --arg project "application-modernization-lab" '
      [
        .projects[] | select(.name==$project).workers
        | to_entries[] as $role
        | $role.value.levels
        | to_entries[] as $level
        | $level.value[]
        | select(.active == true)
        | {role:$role.key, level:$level.key, worker:.}
      ]' "${projects_file}"
  )"
fi

active_workers_with_sessions="$(
  sessions_source="${sessions_file}"
  if [[ ! -f "${sessions_source}" ]]; then
    sessions_source="/dev/null"
  fi
  jq -n \
    --argjson workers "${active_workers}" \
    --slurpfile sessions "${sessions_source}" '
      ($sessions[0].sessions // $sessions[0] // {}) as $sessionMap
      | $workers
      | map(
          . + {
            session: (
              $sessionMap[.worker.sessionKey] // null
              | if . == null then null else {
                  sessionId:(.sessionId // .id // null),
                  status:(.status // .state // null),
                  completedAt:(.completedAt // .finishedAt // null),
                  updatedAt:(.updatedAt // null)
                } end
            )
          }
        )
    ' 2>/dev/null || printf '%s' "${active_workers}"
)"

active_gateway_tasks="$(
  jq -c '
    if type == "object" and (.tasks.active? != null) then .tasks.active
    elif type == "object" and (.tasks.byStatus.running? != null) then .tasks.byStatus.running
    else null end
  ' <<<"${gateway_status_json}" 2>/dev/null || printf 'null'
)"

github_open_prs='[]'
if [[ -f "${gateway_env}" && -S /run/devclaw/github-token-broker.sock ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${gateway_env}"
  set +a
  token="$(
    curl --silent --show-error --fail \
      --unix-socket /run/devclaw/github-token-broker.sock \
      http://localhost/token 2>/dev/null |
      jq -r '.token // empty' || true
  )"
  if [[ -n "${token}" ]]; then
    github_open_prs="$(
      curl --silent --show-error --fail-with-body -K - <<EOF_CURL || printf '[]'
url = "https://api.github.com/repos/${repo_full}/pulls?state=open&per_page=100"
header = "Authorization: Bearer ${token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
    )"
  fi
fi

jq -n \
  --arg checkedAt "${checked_at}" \
  --argjson gatewayStatus "${gateway_status_json}" \
  --argjson gatewayHealth "${gateway_health_json}" \
  --arg repoBranch "${repo_branch}" \
  --arg repoHead "${repo_head}" \
  --arg repoStatus "${repo_status}" \
  --arg repo08bStatus "${repo_08b_status}" \
  --argjson localBranchRc "${local_branch_rc}" \
  --argjson remoteBranchRc "${remote_branch_rc}" \
  --argjson activeWorkers "${active_workers_with_sessions}" \
  --argjson activeGatewayTasks "${active_gateway_tasks}" \
  --argjson openPrs "${github_open_prs}" \
  '{
    checkedAt:$checkedAt,
    gateway:{status:$gatewayStatus, health:$gatewayHealth, activeTasks:$activeGatewayTasks},
    devclaw:{activeWorkers:$activeWorkers},
    repo:{
      path:"/workspace/repos/application-modernization-lab",
      branch:$repoBranch,
      head:$repoHead,
      status:$repoStatus,
      experiment08bStatus:$repo08bStatus,
      clean:($repoStatus == "## main...origin/main\n" or $repoStatus == "## main...origin/main"),
      localImplementationBranchExists:($localBranchRc == 0),
      remoteImplementationBranchExists:($remoteBranchRc == 0),
      openPrs:($openPrs | map({number,title,head:.head.ref,url:.html_url,draft}))
    }
  }' | tee "${out_dir}/preflight-summary.json"

printf '%s\n' "${out_dir}" | tee "${root}/results/latest-reboot-test-preflight-dir.txt"
