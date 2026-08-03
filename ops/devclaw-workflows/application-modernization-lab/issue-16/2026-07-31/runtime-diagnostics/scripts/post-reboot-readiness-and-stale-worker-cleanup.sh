#!/usr/bin/env bash
set -euo pipefail

root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics"
out_file="${1:-${root}/results/post-reboot-readiness-and-cleanup.json}"
state_dir="/home/devclaw-svc/.openclaw"
projects_file="${state_dir}/workspace/devclaw/projects.json"
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
backup_dir="${root}/backups"

fail() {
  printf '[post-reboot-readiness-and-stale-worker-cleanup] ERROR: %s\n' "$*" >&2
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
[[ -f "${gateway_env}" ]] || fail "missing gateway env"
[[ -f "${projects_file}" ]] || fail "missing projects file"
[[ -f "${sessions_file}" ]] || fail "missing sessions file"

set -a
# shellcheck disable=SC1090
source "${gateway_env}"
set +a

mkdir -p "$(dirname "${out_file}")" "${backup_dir}"

gateway_active="$(systemctl is-active openclaw-gateway.service || true)"
broker_active="$(systemctl is-active devclaw-github-token-broker.service || true)"
gateway_status="$(run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000 2>&1 || true)"
gateway_health="$(run_as_devclaw /usr/local/bin/openclaw gateway call health --json --timeout 10000 2>&1 || true)"

active_before="$(
  jq --arg project "application-modernization-lab" --slurpfile sessionStore "${sessions_file}" '
    [
      .projects[] | select(.name==$project).workers
      | to_entries[] as $role
      | $role.value.levels
      | to_entries[] as $level
      | $level.value[]
      | select(.active == true)
      | {
          role:$role.key,
          level:$level.key,
          issueId:(.issueId // null),
          sessionKey:(.sessionKey // null),
          session:(
            if (.sessionKey // null) then
              ($sessionStore[0].sessions[.sessionKey] // $sessionStore[0][.sessionKey] // null)
            else null end
          ),
          worker:.
        }
    ]' "${projects_file}"
)"

cleanup_needed="$(
  jq -r '
    [
      .[] |
      select(.role == "developer" and .level == "senior" and .issueId == "16") |
      select((.session.status // "") == "done" or (.session.status // "") == "failed")
    ] | length
  ' <<<"${active_before}"
)"

backup_file=""
cleanup_applied=false
if [[ "${cleanup_needed}" != "0" ]]; then
  backup_file="${backup_dir}/projects.json.pre-stale-worker-cleanup.$(date -u +%Y%m%dT%H%M%SZ).bak"
  cp -a "${projects_file}" "${backup_file}"
  tmp_file="$(mktemp)"
  jq --arg project "application-modernization-lab" '
    (.projects[] | select(.name==$project).workers.developer.levels.senior[0]) |= (
      if (.active == true and .issueId == "16") then
        . + {
          active:false,
          issueId:null,
          startTime:null,
          previousLabel:null,
          staleRuntimeClearedAt:(now | todateiso8601),
          staleRuntimeClearReason:"post-reboot diagnostic: linked developer session was terminal"
        }
      else . end
    )' "${projects_file}" > "${tmp_file}"
  mv "${tmp_file}" "${projects_file}"
  chown devclaw-svc:devclaw-svc "${projects_file}"
  cleanup_applied=true
fi

active_after="$(
  jq --arg project "application-modernization-lab" '
    [
      .projects[] | select(.name==$project).workers
      | to_entries[] as $role
      | $role.value.levels
      | to_entries[] as $level
      | $level.value[]
      | select(.active == true)
      | {role:$role.key, level:$level.key, issueId:(.issueId // null), sessionKey:(.sessionKey // null), worker:.}
    ]' "${projects_file}"
)"

jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg gatewayService "${gateway_active}" \
  --arg brokerService "${broker_active}" \
  --argjson gatewayStatus "${gateway_status}" \
  --argjson gatewayHealth "${gateway_health}" \
  --argjson activeBefore "${active_before}" \
  --argjson activeAfter "${active_after}" \
  --argjson cleanupApplied "${cleanup_applied}" \
  --arg backupFile "${backup_file}" \
  '{
    checkedAt:$checkedAt,
    services:{openclawGateway:$gatewayService, githubTokenBroker:$brokerService},
    gateway:{status:$gatewayStatus, health:$gatewayHealth},
    staleWorkerCleanup:{applied:$cleanupApplied, backupFile:$backupFile, activeWorkersBefore:$activeBefore, activeWorkersAfter:$activeAfter}
  }' | tee "${out_file}"
