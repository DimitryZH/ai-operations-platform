#!/usr/bin/env bash
set -u

root="/tmp/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31"
script="${root}/scripts/dispatch-agent-param-cwd-codex-smoke-test.sh"
log="${root}/results/agent-param-cwd-codex-smoke-debug-wrapper.log"
dispatch="${root}/results/agent-param-cwd-codex-smoke-dispatch-debug-wrapper.json"
status="${root}/results/agent-param-cwd-codex-smoke-status-debug-wrapper.json"

mkdir -p "$(dirname "${log}")"
bash -x "${script}" "${dispatch}" "${status}" >"${log}" 2>&1
rc="$?"
printf 'rc=%s\n' "${rc}"
sed -n '1,180p' "${log}" || true
exit "${rc}"
