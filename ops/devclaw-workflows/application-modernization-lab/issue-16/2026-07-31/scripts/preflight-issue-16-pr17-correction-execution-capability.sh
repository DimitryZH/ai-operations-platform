#!/usr/bin/env bash
set -euo pipefail

project="application-modernization-lab"
issue_id="16"
repo="/workspace/repos/application-modernization-lab"
implementation_branch="experiment-08/aks-store-aspire-migration"
expected_head="6722ff491c2a9053a9f76b4bb9223b64f3ec6b3b"
state_dir="/home/devclaw-svc/.openclaw"
gateway_env="/var/lib/devclaw/gateway/openclaw-gateway.env"
prompt_file="${state_dir}/workspace/devclaw/projects/${project}/prompts/developer.md"
root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/correction-recovery"
out_file="${1:-${root}/execution-capability-preflight-$(date -u +%Y%m%dT%H%M%SZ).json}"
session_suffix="$(date -u +%Y%m%dt%H%M%Sz)"
session_key="agent:main:subagent:issue-16-pr17-correction-capability-preflight-${session_suffix}"
session_label="Issue 16 PR17 Correction Capability Preflight ${session_suffix}"
model="openai/gpt-5.5"

fail() {
  printf '[preflight-issue-16-pr17-correction-execution-capability] ERROR: %s\n' "$*" >&2
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
[[ -r "${prompt_file}" ]] || fail "developer prompt is not readable"

set -a
# shellcheck disable=SC1090
source "${gateway_env}"
set +a

mkdir -p "$(dirname "${out_file}")"

branch="$(run_as_devclaw git -C "${repo}" branch --show-current)"
head="$(run_as_devclaw git -C "${repo}" rev-parse HEAD)"
[[ "${branch}" == "${implementation_branch}" ]] || fail "repo branch must be ${implementation_branch}; found ${branch}"
[[ "${head}" == "${expected_head}" ]] || fail "repo HEAD must be expected PR head ${expected_head}; found ${head}"

gateway_status_before="$(run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000)"
[[ "$(jq -r '.tasks.active // -1' <<<"${gateway_status_before}")" == "0" ]] || fail "Gateway has active tasks before capability preflight"

capability_command="$(cat <<'EOF_CMD'
set -euo pipefail
current_step="start"
step() {
  current_step="$1"
  printf 'CAPABILITY_STEP:%s\n' "$current_step"
}
trap 'rc=$?; if [[ "$rc" -ne 0 ]]; then printf "CAPABILITY_FAILED_STEP:%s:exit:%s\n" "$current_step" "$rc"; fi' EXIT
repo=/workspace/repos/application-modernization-lab
branch=experiment-08/aks-store-aspire-migration
target_dir="$repo/experiments/08-aks-store-demo/02-compose-to-aspire"
step cd_repo
cd "$repo"
step branch
test "$(git branch --show-current)" = "$branch"
step target_dir_exists
test -d "$target_dir"
step target_dir_writable
test -w "$target_dir"
step temp_write
tmp="$target_dir/.devclaw-capability-check-$$"
printf 'capability\n' > "$tmp"
test -f "$tmp"
rm -f "$tmp"
step real_git_process_check
if ps -u "$(id -u)" -o pid=,comm=,args= | awk '$2 ~ /^git(-.*)?$/ { print; found=1 } END { exit found ? 0 : 1 }'; then
  echo "CAPABILITY_FAILED: real git process active for current user"
  exit 20
fi
step index_lock_absent
test ! -e "$repo/.git/index.lock"
step index_lock_create_remove
: > "$repo/.git/index.lock"
test -f "$repo/.git/index.lock"
rm -f "$repo/.git/index.lock"
step docker_version
docker version
step docker_ps
docker ps
step executable_modes
find "$target_dir" -type f \( -name '*.sh' -o -name '*.ps1' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.cmd' -o -name '*.bat' \) -printf '%M %m %u:%g %p\n' | sort
step git_push_dry_run
git push --dry-run origin HEAD:experiment-08/aks-store-aspire-migration
step git_status
git status --short
step done
echo CAPABILITY_OK
EOF_CMD
)"

probe_path="${repo}/experiments/08-aks-store-demo/02-compose-to-aspire/.devclaw-capability-probe-${session_suffix}.sh"
printf '%s\n' '#!/usr/bin/env bash' > "${probe_path}"
printf 'export DEVCLAW_CAPABILITY_PROBE_PATH=%q\n' "${probe_path}" >> "${probe_path}"
printf '%s\n' "${capability_command}" >> "${probe_path}"
chown devclaw-svc:devclaw-svc "${probe_path}"
chmod 0755 "${probe_path}"

task_message="$(cat <<EOF_MESSAGE
Execution capability preflight only. Do not inspect issues, edit source, commit, push real changes, create branches, create PRs, dispatch workers, or modify configuration.

Use the bash tool exactly once in cwd ${repo} to execute this exact command:

    bash ${probe_path}

If the command succeeds, answer CAPABILITY_OK with concise evidence. If it fails, answer CAPABILITY_FAILED with the exact failing command/output. Do not retry.
EOF_MESSAGE
)"

run_as_devclaw /usr/local/bin/openclaw gateway call sessions.patch \
  --params "$(jq -nc --arg key "${session_key}" --arg model "${model}" --arg label "${session_label}" '{key:$key, model:$model, label:$label}')" \
  --timeout 30000 \
  --json >/dev/null

agent_params="$(jq -nc \
  --arg key "${session_key}" \
  --arg msg "${task_message}" \
  --arg idk "issue-16-pr17-correction-capability-${session_suffix}" \
  --arg prompt "$(cat "${prompt_file}")" \
  '{idempotencyKey:$idk, agentId:"main", sessionKey:$key, message:$msg, deliver:false, lane:"subagent", extraSystemPrompt:$prompt}')"

agent_result="$(
  run_as_devclaw /usr/local/bin/openclaw gateway call agent \
    --params "${agent_params}" \
    --timeout 120000 \
    --json
)"

sleep 35
sessions_file="${state_dir}/agents/main/sessions/sessions.json"
session="$(
  if [[ -f "${sessions_file}" ]]; then
    jq -c --arg key "${session_key}" '.sessions[$key] // .[$key] // null' "${sessions_file}"
  else
    printf 'null'
  fi
)"
session_id="$(jq -r '.sessionId // .id // empty' <<<"${session}")"
session_status="$(jq -r '.status // empty' <<<"${session}")"
transcript_tail="$(
  if [[ -n "${session_id}" && -f "${state_dir}/agents/main/sessions/${session_id}.jsonl" ]]; then
    tail -n 260 "${state_dir}/agents/main/sessions/${session_id}.jsonl"
  else
    printf ''
  fi
)"
if [[ "${session_status}" != "running" && "${session_status}" != "queued" ]]; then
  rm -f "${probe_path}"
fi
gateway_status_after="$(run_as_devclaw /usr/local/bin/openclaw gateway call status --json --timeout 10000)"
capability_ok=false
assistant_final_text="$(
  if [[ -n "${session_id}" && -f "${state_dir}/agents/main/sessions/${session_id}.jsonl" ]]; then
    jq -rs -r '
      [
        .[]
        | select(.type == "message" and .message.role == "assistant")
        | (.message.content[]? | select(.type == "text") | .text)
      ] | last // ""
    ' "${state_dir}/agents/main/sessions/${session_id}.jsonl"
  else
    printf ''
  fi
)"
if [[ "${assistant_final_text}" == CAPABILITY_OK* ]] \
  && [[ "${assistant_final_text}" != *CAPABILITY_FAILED* ]] \
  && jq -e '.status == "done"' <<<"${session}" >/dev/null; then
  capability_ok=true
fi

jq -n \
  --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sessionKey "${session_key}" \
  --arg sessionId "${session_id}" \
  --arg probePath "${probe_path}" \
  --arg agentResult "${agent_result}" \
  --argjson session "${session}" \
  --arg transcriptTail "${transcript_tail}" \
  --arg assistantFinalText "${assistant_final_text}" \
  --argjson gatewayBefore "${gateway_status_before}" \
  --argjson gatewayAfter "${gateway_status_after}" \
  --argjson capabilityOk "${capability_ok}" \
  '{
    checkedAt:$checkedAt,
    sessionKey:$sessionKey,
    sessionId:$sessionId,
    probePath:$probePath,
    agentResult:$agentResult,
    session:$session,
    transcriptTail:$transcriptTail,
    assistantFinalText:$assistantFinalText,
    gatewayBefore:{tasks:$gatewayBefore.tasks},
    gatewayAfter:{tasks:$gatewayAfter.tasks},
    capabilityOk:$capabilityOk
  }' | tee "${out_file}"

[[ "${capability_ok}" == "true" ]] || fail "execution capability preflight failed; see ${out_file}"
