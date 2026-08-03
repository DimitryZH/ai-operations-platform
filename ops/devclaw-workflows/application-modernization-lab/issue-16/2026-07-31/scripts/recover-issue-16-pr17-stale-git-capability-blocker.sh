#!/usr/bin/env bash
set -euo pipefail

repo="/workspace/repos/application-modernization-lab"
implementation_branch="experiment-08/aks-store-aspire-migration"
expected_head="6722ff491c2a9053a9f76b4bb9223b64f3ec6b3b"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
projects_file="${state_dir}/workspace/devclaw/projects.json"
root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/correction-recovery"
out_dir="${1:-${root}/stale-git-recovery-$(date -u +%Y%m%dT%H%M%SZ)}"

fail() {
  printf '[recover-issue-16-pr17-stale-git-capability-blocker] ERROR: %s\n' "$*" >&2
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
[[ -d "${repo}/.git" ]] || fail "missing repository checkout: ${repo}"
[[ -f "${gateway_env}" ]] || fail "missing gateway env"
[[ -f "${projects_file}" ]] || fail "missing projects.json"

set -a
# shellcheck disable=SC1090
source "${gateway_env}"
set +a

mkdir -p "${out_dir}"

gateway_status="$(run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000)"
active_tasks="$(jq -r '.tasks.active // -1' <<<"${gateway_status}")"
[[ "${active_tasks}" == "0" ]] || fail "Gateway still has active tasks: ${active_tasks}"

worker="$(
  jq -c '.projects[] | select(.name=="application-modernization-lab").workers.developer.levels.senior[0]' \
    "${projects_file}"
)"
worker_active="$(jq -r '.active // false' <<<"${worker}")"
[[ "${worker_active}" == "false" ]] || fail "developer worker is still active"

branch="$(run_as_devclaw git -C "${repo}" branch --show-current)"
head="$(run_as_devclaw git -C "${repo}" rev-parse HEAD)"
[[ "${branch}" == "${implementation_branch}" ]] || fail "repo branch must be ${implementation_branch}; found ${branch}"
[[ "${head}" == "${expected_head}" ]] || fail "repo HEAD must remain ${expected_head}; found ${head}"

run_as_devclaw git -C "${repo}" status --short --branch > "${out_dir}/git-status-before.txt"
ps -u "$(id -u devclaw-svc)" -o pid,ppid,stat,comm,args ww > "${out_dir}/devclaw-svc-processes-before.txt"
ps -u "$(id -u devclaw-svc)" -o pid=,comm=,args= |
  awk '$2 ~ /^git(-.*)?$/ { print }' > "${out_dir}/real-git-processes-before.txt"

lock_removed=false
lock_path="${repo}/.git/index.lock"
if [[ -e "${lock_path}" ]]; then
  if [[ -s "${out_dir}/real-git-processes-before.txt" ]]; then
    fail "index.lock exists but real git processes are active; refusing cleanup"
  fi
  cp -a "${lock_path}" "${out_dir}/index.lock.backup"
  rm -f "${lock_path}"
  lock_removed=true
fi

run_as_devclaw git -C "${repo}" status --short --branch > "${out_dir}/git-status-after.txt"
ps -u "$(id -u devclaw-svc)" -o pid,ppid,stat,comm,args ww > "${out_dir}/devclaw-svc-processes-after.txt"
ps -u "$(id -u devclaw-svc)" -o pid=,comm=,args= |
  awk '$2 ~ /^git(-.*)?$/ { print }' > "${out_dir}/real-git-processes-after.txt"

jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg outDir "${out_dir}" \
  --arg branch "${branch}" \
  --arg head "${head}" \
  --argjson gatewayTasks "$(jq '.tasks' <<<"${gateway_status}")" \
  --argjson worker "${worker}" \
  --argjson lockRemoved "${lock_removed}" \
  --arg realGitBefore "$(cat "${out_dir}/real-git-processes-before.txt")" \
  --arg realGitAfter "$(cat "${out_dir}/real-git-processes-after.txt")" \
  '{
    checkedAt:$checkedAt,
    outDir:$outDir,
    repository:{branch:$branch, head:$head},
    gatewayTasks:$gatewayTasks,
    developerWorker:$worker,
    cleanup:{indexLockRemoved:$lockRemoved},
    evidence:{
      realGitProcessesBefore:$realGitBefore,
      realGitProcessesAfter:$realGitAfter,
      statusBefore:"git-status-before.txt",
      statusAfter:"git-status-after.txt",
      processListBefore:"devclaw-svc-processes-before.txt",
      processListAfter:"devclaw-svc-processes-after.txt"
    }
  }' | tee "${out_dir}/stale-git-recovery-summary.json"

printf '%s\n' "${out_dir}" | tee "${root}/latest-stale-git-recovery-dir.txt" >/dev/null
