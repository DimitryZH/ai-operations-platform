#!/usr/bin/env bash
set -euo pipefail

root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics"
out_dir="${1:-${root}/results/narrow-userns-apparmor-validation-$(date -u +%Y%m%dT%H%M%SZ)}"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
session_suffix="$(date -u +%Y%m%dt%H%M%Sz)"
session_key="agent:main:subagent:issue-16-userns-apparmor-fix-smoke-${session_suffix}"
model="openai/gpt-5.5"

fail() {
  printf '[validate-narrow-userns-apparmor-fix] ERROR: %s\n' "$*" >&2
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

capture_cmd() {
  local name="$1"
  shift
  local stdout_file="${out_dir}/${name}.stdout"
  local stderr_file="${out_dir}/${name}.stderr"
  local rc_file="${out_dir}/${name}.rc"
  local rc=0
  "$@" >"${stdout_file}" 2>"${stderr_file}" || rc="$?"
  printf '%s\n' "${rc}" > "${rc_file}"
}

[[ "${EUID}" -eq 0 ]] || fail "must run as root on DevClaw VM"
command -v jq >/dev/null 2>&1 || fail "missing jq"
[[ -f "${gateway_env}" ]] || fail "missing gateway env"
mkdir -p "${out_dir}"

set -a
# shellcheck disable=SC1090
source "${gateway_env}"
set +a

systemctl is-active --quiet openclaw-gateway.service || fail "openclaw-gateway.service is not active"

mapfile -t bwrap_paths < <(find /home/devclaw-svc/.openclaw/npm/projects -path '*/codex-resources/bwrap' -type f 2>/dev/null | sort)
[[ "${#bwrap_paths[@]}" -gt 0 ]] || fail "no OpenClaw-bundled Codex bwrap executable found"
bwrap_path="${bwrap_paths[0]}"

capture_cmd unshare-Ur run_as_devclaw unshare -Ur true
capture_cmd unshare-Urn run_as_devclaw unshare -Urn true
capture_cmd direct-bwrap run_as_devclaw "${bwrap_path}" --ro-bind / / --dev /dev --proc /proc --unshare-all --die-with-parent -- sh -c 'true && pwd && id'

patch_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg model "${model}" \
  --arg label "Issue 16 userns AppArmor fix smoke ${session_suffix}" \
  '{key:$key, model:$model, label:$label}')"

patch_result=""
patch_rc=0
patch_result="$(run_as_devclaw /usr/local/bin/openclaw gateway call sessions.patch --params "${patch_params}" --timeout 30000 --json 2>&1)" || patch_rc="$?"

task_message='Runtime recovery smoke only. Do not inspect or modify repositories, issues, labels, branches, PRs, skills, workflow config, services, VM settings, or cloud resources. Use the bash tool exactly once to execute this read-only command: true && pwd && id. Then answer with SMOKE_OK and the observed pwd/id output if the command executed successfully, or SMOKE_FAILED plus the exact error if it failed.'

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "issue-16-userns-apparmor-fix-smoke-${session_suffix}" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent"}')"

agent_result=""
agent_rc=0
if [[ "${patch_rc}" -eq 0 ]]; then
  agent_result="$(run_as_devclaw /usr/local/bin/openclaw gateway call agent --params "${agent_params}" --timeout 120000 --json 2>&1)" || agent_rc="$?"
else
  agent_rc=99
  agent_result='{"skipped":"sessions.patch failed"}'
fi

sleep 25
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
session="$(
  if [[ -f "${sessions_file}" ]]; then
    jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
)"
session_id="$(jq -r '.sessionId // .id // empty' <<<"${session}")"
tail_text="$(
  if [[ -n "${session_id}" && -f "${state_dir}/agents/main/sessions/${session_id}.jsonl" ]]; then
    tail -n 220 "${state_dir}/agents/main/sessions/${session_id}.jsonl"
  else
    printf ''
  fi
)"

journalctl -b -k --no-pager | grep -Ei 'bwrap|userns|apparmor|DENIED|net_admin|setpcap|RTM_NEWADDR' \
  > "${out_dir}/current-boot-userns-apparmor-lines.log" 2>/dev/null || true

jq -n \
  --arg validatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg outDir "${out_dir}" \
  --arg bwrapPath "${bwrap_path}" \
  --arg sessionKey "${session_key}" \
  --arg sessionId "${session_id}" \
  --argjson session "${session}" \
  --arg patchResult "${patch_result}" \
  --argjson patchRc "${patch_rc}" \
  --arg agentResult "${agent_result}" \
  --argjson agentRc "${agent_rc}" \
  --rawfile unshareUrStdout "${out_dir}/unshare-Ur.stdout" \
  --rawfile unshareUrStderr "${out_dir}/unshare-Ur.stderr" \
  --rawfile unshareUrRc "${out_dir}/unshare-Ur.rc" \
  --rawfile unshareUrnStdout "${out_dir}/unshare-Urn.stdout" \
  --rawfile unshareUrnStderr "${out_dir}/unshare-Urn.stderr" \
  --rawfile unshareUrnRc "${out_dir}/unshare-Urn.rc" \
  --rawfile directBwrapStdout "${out_dir}/direct-bwrap.stdout" \
  --rawfile directBwrapStderr "${out_dir}/direct-bwrap.stderr" \
  --rawfile directBwrapRc "${out_dir}/direct-bwrap.rc" \
  --arg transcriptTail "${tail_text}" \
  '{
    validatedAt:$validatedAt,
    outDir:$outDir,
    bwrapPath:$bwrapPath,
    localSmoke:{
      unshareUr:{rc:($unshareUrRc | tonumber), stdout:$unshareUrStdout, stderr:$unshareUrStderr},
      unshareUrn:{rc:($unshareUrnRc | tonumber), stdout:$unshareUrnStdout, stderr:$unshareUrnStderr},
      directBwrap:{rc:($directBwrapRc | tonumber), stdout:$directBwrapStdout, stderr:$directBwrapStderr}
    },
    subagentSmoke:{
      sessionKey:$sessionKey,
      sessionId:$sessionId,
      patch:{rc:$patchRc, result:$patchResult},
      agent:{rc:$agentRc, result:$agentResult},
      session:$session,
      transcriptTail:$transcriptTail
    }
  }' | tee "${out_dir}/validation-summary.json"

printf '%s\n' "${out_dir}" | tee "${root}/results/latest-narrow-userns-apparmor-validation-dir.txt"
