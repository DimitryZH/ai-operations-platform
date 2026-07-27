#!/usr/bin/env bash
set -euo pipefail

project="application-modernization-lab"
session_key="agent:main:subagent:application-modernization-lab-tester-senior-sukey"
projects_file="/home/devclaw-svc/.openclaw/workspace/devclaw/projects.json"
sessions_file="/home/devclaw-svc/.openclaw/agents/main/sessions/sessions.json"

echo "== worker-state =="
jq --arg project "${project}" '
  .projects[] | select(.name==$project) |
  {
    tester_senior: .workers.tester.levels.senior[0],
    developer_senior: .workers.developer.levels.senior[0],
    architect_senior: .workers.architect.levels.senior[0]
  }' "${projects_file}"

echo "== session-registry =="
if [[ -f "${sessions_file}" ]]; then
  jq --arg key "${session_key}" '.[$key] // null' "${sessions_file}"
else
  echo "sessions.json missing"
fi

echo "== session-file-tail =="
session_file="$(jq -r --arg key "${session_key}" '.[$key].sessionFile // empty' "${sessions_file}" 2>/dev/null || true)"
if [[ -n "${session_file}" && -f "${session_file}" ]]; then
  stat -c 'path=%n size=%s modified=%y' "${session_file}"
  tail -n 80 "${session_file}" |
    grep -E '"work_finish"|"finalAssistantVisibleText"|"finalAssistantRawText"|"result":"pass"|"result":"fail"|"result":"blocked"|"result":"refine"|"labelTransition"|TESTER|VALIDATION|Validation|blocked|failed|pass|PASS' |
    tail -n 40 || true
else
  echo "session file missing"
fi

echo "== audit-recent =="
find /home/devclaw-svc/.openclaw/workspace/devclaw -path '*audit*' -type f -maxdepth 6 2>/dev/null |
  sort |
  xargs -r grep -H '"issue":8\|"issue":"8"\|"issueId":8\|"issueId":"8"' 2>/dev/null |
  tail -n 40 || true
