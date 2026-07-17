#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

fail() {
  printf '[validate-compose-to-aspire-project] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[validate-compose-to-aspire-project] %s\n' "$*"
}

run_as_devclaw() {
  runuser -u devclaw-svc -- env \
    HOME=/home/devclaw-svc \
    XDG_CONFIG_HOME=/home/devclaw-svc/.config \
    XDG_CACHE_HOME=/home/devclaw-svc/.cache \
    XDG_DATA_HOME=/home/devclaw-svc/.local/share \
    OPENCLAW_STATE_DIR=/home/devclaw-svc/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/devclaw-svc/.openclaw/openclaw.json \
    OPENCLAW_NO_COLOR=1 \
    "$@"
}

require_value() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  [[ "$actual" == "$expected" ]] || fail "$name must be ${expected}; found ${actual}."
}

config_get() {
  run_as_devclaw openclaw config get "$1" |
    sed -E 's/^\s+|\s+$//g; s/^"//; s/"$//' |
    tail -n1
}

[[ "$EUID" -eq 0 ]] || fail "Stage 6 validator must run as root."
command -v git >/dev/null 2>&1 || fail "Missing git."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
command -v node >/dev/null 2>&1 || fail "Missing node."

MARKER=/var/lib/devclaw/stage6-compose-to-aspire-project-registered
WORKSPACE_DIR=/home/devclaw-svc/.openclaw/workspace
DEVCLAW_DIR="${WORKSPACE_DIR}/devclaw"
PROJECT_NAME=application-modernization-lab
PROJECT_SLUG=application-modernization-lab
REPO_PATH=/workspace/repos/application-modernization-lab
REPO_URL=https://github.com/DimitryZH/application-modernization-lab.git
BASE_BRANCH=main

[[ -f "$MARKER" ]] || fail "Missing Stage 6 marker."
require_value "Stage 6 marker owner" "$(stat -c '%U:%G' "$MARKER")" "devclaw-svc:devclaw-svc"
require_value "Stage 6 marker mode" "$(stat -c '%a' "$MARKER")" "640"
grep -q '^stage6_project_registered=true$' "$MARKER" || fail "Stage 6 marker is incomplete."
grep -q '^repository=DimitryZH/application-modernization-lab$' "$MARKER" || fail "Unexpected Stage 6 repository marker."
grep -q '^automatic_merge=false$' "$MARKER" || fail "Stage 6 marker must record automatic_merge=false."
grep -q '^skill_workshop_approval_policy=pending$' "$MARKER" || fail "Stage 6 marker must record pending Skill Workshop policy."

[[ -d "$REPO_PATH/.git" ]] || fail "Approved repository clone is absent."
require_value "Repository owner" "$(stat -c '%U:%G' "$REPO_PATH")" "devclaw-svc:devclaw-svc"
require_value "Repository remote" "$(run_as_devclaw git -C "$REPO_PATH" remote get-url origin)" "$REPO_URL"
run_as_devclaw git -C "$REPO_PATH" rev-parse --verify "origin/${BASE_BRANCH}" >/dev/null
require_value "Repository branch" "$(run_as_devclaw git -C "$REPO_PATH" branch --show-current)" "$BASE_BRANCH"
if run_as_devclaw git -C "$REPO_PATH" status --porcelain | grep -q .; then
  fail "Repository worktree is not clean after Stage 6 preparation."
fi

projects_json="${DEVCLAW_DIR}/projects.json"
workflow_yaml="${DEVCLAW_DIR}/workflow.yaml"
project_workflow="${DEVCLAW_DIR}/projects/${PROJECT_NAME}/workflow.yaml"
boundary_json="${DEVCLAW_DIR}/stage6-boundary.json"
[[ -f "$projects_json" ]] || fail "Missing DevClaw projects.json."
[[ -f "$workflow_yaml" ]] || fail "Missing DevClaw workspace workflow.yaml."
[[ -f "$project_workflow" ]] || fail "Missing DevClaw project workflow.yaml."
[[ -f "$boundary_json" ]] || fail "Missing Stage 6 boundary JSON."

jq -e --arg slug "$PROJECT_SLUG" --arg repo "$REPO_PATH" --arg remote "$REPO_URL" --arg branch "$BASE_BRANCH" '
  .projects[$slug].repo == $repo and
  .projects[$slug].repoRemote == $remote and
  .projects[$slug].baseBranch == $branch and
  .projects[$slug].deployBranch == $branch and
  .projects[$slug].provider == "github" and
  (.projects[$slug].channels | length) == 1 and
  .projects[$slug].workers.architect.levels.senior[0].active == false and
  .projects[$slug].workers.developer.levels.senior[0].active == false and
  .projects[$slug].workers.tester.levels.medior[0].active == false and
  (.projects[$slug].workers.reviewer.levels | length) == 0
' "$projects_json" >/dev/null || fail "projects.json does not match the Stage 6 registration boundary."

jq -e '
  .repository == "DimitryZH/application-modernization-lab" and
  .model == "openai/gpt-5.5" and
  .heartbeatEnabled == false and
  .automaticMergeEnabled == false and
  .skillWorkshop.autonomousEnabled == false and
  .skillWorkshop.approvalPolicy == "pending" and
  .skillWorkshop.proposalCreated == false
' "$boundary_json" >/dev/null || fail "Stage 6 boundary JSON mismatch."

if grep -R -nE '\bmergePr\b|\bgitPull\b|\bcloseIssue\b' "$workflow_yaml" "$project_workflow"; then
  fail "Stage 6 workflow must not contain automatic merge, pull, or issue-close actions."
fi
grep -q 'roleExecution: sequential' "$workflow_yaml" || fail "Workflow must set roleExecution: sequential."
grep -q 'reviewer: false' "$workflow_yaml" || fail "Workflow must disable the reviewer role for human review."
grep -q 'Human Architecture Approval' "$workflow_yaml" || fail "Workflow must include Human Architecture Approval."
grep -q 'Knowledge Review' "$workflow_yaml" || fail "Workflow must include Knowledge Review."
grep -q 'openai/gpt-5.5' "$workflow_yaml" || fail "Workflow must map roles to openai/gpt-5.5."

require_value "DevClaw projectExecution" "$(config_get plugins.entries.devclaw.config.projectExecution)" "sequential"
require_value "DevClaw heartbeat" "$(config_get plugins.entries.devclaw.config.work_heartbeat.enabled)" "false"
require_value "Skill Workshop autonomous" "$(config_get skills.workshop.autonomous.enabled)" "false"
require_value "Skill Workshop approvalPolicy" "$(config_get skills.workshop.approvalPolicy)" "pending"

if find /var/lib/devclaw/sessions -mindepth 1 -print -quit | grep -q .; then
  fail "No DevClaw worker sessions may exist after Stage 6."
fi
if find "$DEVCLAW_DIR" -type f \( -iname '*compose-to-aspire*' -o -iname '*migration-skill*' \) -print -quit | grep -q .; then
  fail "No migration skill or Compose-to-Aspire skill file may be created during Stage 6."
fi
if [[ -f /home/devclaw-svc/.openclaw/skill-workshop/proposals.json ]]; then
  jq -e '(.proposals // []) | length == 0' /home/devclaw-svc/.openclaw/skill-workshop/proposals.json >/dev/null ||
    fail "Skill Workshop contains pending proposals after Stage 6."
fi
if find /home/devclaw-svc/.openclaw/skill-workshop/proposals -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
  fail "Skill Workshop proposal files exist after Stage 6."
fi

if [[ -x /opt/devclaw/bin/validate-github-app-broker.sh ]]; then
  /opt/devclaw/bin/validate-github-app-broker.sh --offline
fi

/opt/devclaw/bin/validate-openclaw-gateway.sh

log "Stage 6 registered project, workflow, boundaries, and empty worker state validated."
