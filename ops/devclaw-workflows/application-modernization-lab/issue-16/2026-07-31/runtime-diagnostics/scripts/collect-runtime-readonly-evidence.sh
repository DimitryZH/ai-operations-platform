#!/usr/bin/env bash
set -euo pipefail

root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics"
out_dir="${1:-${root}/results/runtime-evidence-$(date -u +%Y%m%dT%H%M%SZ)}"
repo_full="DimitryZH/application-modernization-lab"
repo="/workspace/repos/application-modernization-lab"
issue_id="16"
implementation_branch="experiment-08/aks-store-aspire-migration"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
projects_file="${state_dir}/workspace/devclaw/projects.json"
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
failed_key="${FAILED_SESSION_KEY:-agent:main:subagent:application-modernization-lab-developer-senior-ara-issue-16-20260731t194406z}"

fail() {
  printf '[collect-runtime-readonly-evidence] ERROR: %s\n' "$*" >&2
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

write_cmd() {
  local title="$1"
  shift
  {
    printf '\n=== %s ===\n' "${title}"
    "$@" 2>&1 || printf '[exit=%s]\n' "$?"
  }
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on DevClaw VM"
command -v jq >/dev/null 2>&1 || fail "missing jq"
mkdir -p "${out_dir}"

checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  printf 'checkedAt=%s\n' "${checked_at}"
  write_cmd hostname hostname
  write_cmd whoami whoami
  write_cmd id-root id
  write_cmd id-devclaw-svc id devclaw-svc
  write_cmd groups-devclaw-svc groups devclaw-svc
  write_cmd uname uname -a
  write_cmd os-release cat /etc/os-release
  write_cmd lsb-release lsb_release -a
  write_cmd bubblewrap-version bwrap --version
  write_cmd unshare-version unshare --version
  write_cmd sysctl-userns sysctl kernel.unprivileged_userns_clone user.max_user_namespaces user.max_net_namespaces kernel.apparmor_restrict_unprivileged_userns
  write_cmd proc-userns cat /proc/sys/kernel/unprivileged_userns_clone
  write_cmd proc-user-max-user-ns cat /proc/sys/user/max_user_namespaces
  write_cmd proc-user-max-net-ns cat /proc/sys/user/max_net_namespaces
  write_cmd devclaw-unshare-user timeout 10 runuser -u devclaw-svc -- unshare -Ur true
  write_cmd devclaw-unshare-user-net timeout 10 runuser -u devclaw-svc -- unshare -Urn true
  write_cmd apparmor-status aa-status
  write_cmd apparmor-profiles sh -c 'ls -1 /etc/apparmor.d 2>/dev/null | grep -Ei "codex|openclaw|bwrap|bubble|devclaw|namespace|userns" || true'
  write_cmd seccomp-self sh -c 'grep -E "Seccomp|Cap|NoNewPrivs|Uid|Gid" /proc/self/status'
  write_cmd devclaw-svc-limits runuser -u devclaw-svc -- sh -c 'ulimit -a'
} > "${out_dir}/system-namespace-apparmor.txt"

{
  printf 'checkedAt=%s\n' "${checked_at}"
  write_cmd openclaw-gateway-status systemctl status openclaw-gateway.service --no-pager
  write_cmd github-token-broker-status systemctl status devclaw-github-token-broker.service --no-pager
  write_cmd openclaw-config sh -c 'jq "{codex:{appServer:.plugins.entries.codex.config.appServer, model:.plugins.entries.codex.config.model, approvalPolicy:.plugins.entries.codex.config.approvalPolicy, policyMode:.plugins.entries.codex.config.policyMode, approvalsReviewer:.plugins.entries.codex.config.approvalsReviewer}, devclaw:{workHeartbeat:.plugins.entries.devclaw.config.work_heartbeat, projectExecution:.plugins.entries.devclaw.config.projectExecution}, tools:{exec:.tools.exec}, skills:{workshop:.skills.workshop}}" /home/devclaw-svc/.openclaw/openclaw.json'
  write_cmd codex-config cat /home/devclaw-svc/.openclaw/agents/main/agent/codex-home/config.toml
  write_cmd gateway-status run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000
  write_cmd gateway-health run_as_devclaw /usr/local/bin/openclaw gateway call health --json --timeout 10000
} > "${out_dir}/gateway-devclaw-config-status.txt"

if [[ -d "${repo}/.git" ]]; then
  {
    printf 'checkedAt=%s\n' "${checked_at}"
    write_cmd git-branch run_as_devclaw git -C "${repo}" branch --show-current
    write_cmd git-head run_as_devclaw git -C "${repo}" rev-parse HEAD
    write_cmd git-status run_as_devclaw git -C "${repo}" status --short --branch
    write_cmd git-untracked-08b run_as_devclaw git -C "${repo}" status --short -- experiments/08-aks-store-demo/02-compose-to-aspire
    write_cmd local-implementation-branch run_as_devclaw git -C "${repo}" show-ref --verify "refs/heads/${implementation_branch}"
    write_cmd remote-implementation-branch run_as_devclaw git -C "${repo}" ls-remote --heads origin "${implementation_branch}"
    write_cmd recent-local-commits run_as_devclaw git -C "${repo}" log --oneline --decorate -n 8 --all
  } > "${out_dir}/target-repo-state.txt"
else
  printf 'missing repo: %s\n' "${repo}" > "${out_dir}/target-repo-state.txt"
fi

github_token=""
if [[ -f "${gateway_env}" && -S /run/devclaw/github-token-broker.sock ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${gateway_env}"
  set +a
  github_token="$(
    curl --silent --show-error --fail \
      --unix-socket /run/devclaw/github-token-broker.sock \
      http://localhost/token 2>/dev/null |
      jq -r '.token // empty' || true
  )"
fi
if [[ -n "${github_token}" ]]; then
  curl --silent --show-error --fail-with-body -K - > "${out_dir}/github-open-prs.json" <<EOF_CURL || true
url = "https://api.github.com/repos/${repo_full}/pulls?state=open&per_page=100"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
  curl --silent --show-error --fail-with-body -K - > "${out_dir}/github-issue-16.json" <<EOF_CURL || true
url = "https://api.github.com/repos/${repo_full}/issues/${issue_id}"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
else
  printf '{"error":"github token unavailable"}\n' > "${out_dir}/github-open-prs.json"
  printf '{"error":"github token unavailable"}\n' > "${out_dir}/github-issue-16.json"
fi

if [[ -f "${projects_file}" ]]; then
  jq \
    --arg checkedAt "${checked_at}" \
    --arg project "application-modernization-lab" \
    '{
      checkedAt:$checkedAt,
      activeWorkers: [
        .projects[] | select(.name==$project).workers
        | to_entries[] as $role
        | $role.value.levels
        | to_entries[] as $level
        | $level.value[]
        | select(.active == true)
        | {role:$role.key, level:$level.key, worker:.}
      ],
      allWorkers: (
        .projects[] | select(.name==$project).workers
      )
    }' "${projects_file}" > "${out_dir}/devclaw-workers.json"
fi

session_for_key() {
  local key="$1"
  if [[ -f "${sessions_file}" ]]; then
    jq -c --arg key "${key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
}

failed_session="$(session_for_key "${failed_key}")"
failed_id="$(jq -r '.sessionId // .id // empty' <<<"${failed_session}")"
failed_file=""
if [[ -n "${failed_id}" && -f "${state_dir}/agents/main/sessions/${failed_id}.jsonl" ]]; then
  failed_file="${state_dir}/agents/main/sessions/${failed_id}.jsonl"
fi

architect_key="$(
  if [[ -f "${sessions_file}" ]]; then
    jq -r '
      (.sessions // .) | to_entries[]
      | select(.key | test("application-modernization-lab-architect.*issue-16|issue-16.*architect"; "i"))
      | .key
    ' "${sessions_file}" | tail -n 1
  fi
)"
architect_session="$(session_for_key "${architect_key}")"
architect_id="$(jq -r '.sessionId // .id // empty' <<<"${architect_session}")"
architect_file=""
if [[ -n "${architect_id}" && -f "${state_dir}/agents/main/sessions/${architect_id}.jsonl" ]]; then
  architect_file="${state_dir}/agents/main/sessions/${architect_id}.jsonl"
fi

jq -n \
  --arg checkedAt "${checked_at}" \
  --arg failedKey "${failed_key}" \
  --arg failedFile "${failed_file}" \
  --arg architectKey "${architect_key}" \
  --arg architectFile "${architect_file}" \
  --argjson failedSession "${failed_session}" \
  --argjson architectSession "${architect_session}" \
  '{
    checkedAt:$checkedAt,
    failedDeveloper:{key:$failedKey, session:$failedSession, transcriptFile:$failedFile},
    architect:{key:$architectKey, session:$architectSession, transcriptFile:$architectFile}
  }' > "${out_dir}/session-compare-summary.json"

for label in failed architect; do
  if [[ "${label}" == "failed" ]]; then
    file="${failed_file}"
  else
    file="${architect_file}"
  fi
  if [[ -n "${file}" && -f "${file}" ]]; then
    {
      printf 'file=%s\n' "${file}"
      printf '\n=== head ===\n'
      sed -n '1,80p' "${file}"
      printf '\n=== bwrap/namespace/sandbox/errors ===\n'
      grep -n -Ei 'bwrap|bubblewrap|RTM_NEWADDR|loopback|namespace|sandbox|declined|Operation not permitted|permission denied|apparmor|seccomp|failed|toolResult|toolCall' "${file}" | tail -n 240 || true
      printf '\n=== tail ===\n'
      tail -n 160 "${file}"
    } > "${out_dir}/session-${label}-transcript-extract.txt"
  else
    printf 'missing transcript file for %s\n' "${label}" > "${out_dir}/session-${label}-transcript-extract.txt"
  fi
done

{
  printf 'checkedAt=%s\n' "${checked_at}"
  write_cmd gateway-journal-recent journalctl -u openclaw-gateway.service --since '2026-07-31 18:00:00 UTC' --no-pager -n 1200
} > "${out_dir}/journal-openclaw-gateway.txt"

{
  printf 'checkedAt=%s\n' "${checked_at}"
  write_cmd kernel-apparmor-seccomp journalctl -k --since '2026-07-31 18:00:00 UTC' --no-pager
  printf '\n=== filtered ===\n'
  journalctl -k --since '2026-07-31 18:00:00 UTC' --no-pager 2>/dev/null |
    grep -Ei 'apparmor|audit|denied|seccomp|bwrap|bubblewrap|namespace|RTM_NEWADDR|operation not permitted' || true
} > "${out_dir}/journal-kernel-apparmor-seccomp.txt"

tar -C "${out_dir}/.." -czf "${out_dir}.tar.gz" "$(basename "${out_dir}")"
printf '%s\n' "${out_dir}" | tee "${root}/results/latest-runtime-evidence-dir.txt"
