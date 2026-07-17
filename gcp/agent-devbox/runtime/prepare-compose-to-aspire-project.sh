#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

fail() {
  printf '[prepare-compose-to-aspire-project] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[prepare-compose-to-aspire-project] %s\n' "$*"
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

[[ "$EUID" -eq 0 ]] || fail "Stage 6 preparation must run as root."
command -v git >/dev/null 2>&1 || fail "Missing git."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
command -v node >/dev/null 2>&1 || fail "Missing node."
command -v curl >/dev/null 2>&1 || fail "Missing curl."

OWNER="${DEVCLAW_STAGE6_GITHUB_OWNER:?Missing DEVCLAW_STAGE6_GITHUB_OWNER.}"
REPO="${DEVCLAW_STAGE6_GITHUB_REPO:?Missing DEVCLAW_STAGE6_GITHUB_REPO.}"
BASE_BRANCH="${DEVCLAW_STAGE6_BASE_BRANCH:-main}"
PROJECT_NAME="${DEVCLAW_STAGE6_PROJECT_NAME:-application-modernization-lab}"
PROJECT_SLUG="${DEVCLAW_STAGE6_PROJECT_SLUG:-application-modernization-lab}"
CHANNEL_ID="${DEVCLAW_STAGE6_CHANNEL_ID:-openclaw-control-ui-main}"
CHANNEL_NAME="${DEVCLAW_STAGE6_CHANNEL_NAME:-OpenClaw Control UI}"
APPROVED_FULL_NAME="DimitryZH/application-modernization-lab"
FULL_NAME="${OWNER}/${REPO}"

[[ "$FULL_NAME" == "$APPROVED_FULL_NAME" ]] ||
  fail "Stage 6 may only prepare ${APPROVED_FULL_NAME}; requested ${FULL_NAME}."
[[ "$PROJECT_SLUG" == "application-modernization-lab" ]] ||
  fail "Unexpected project slug: ${PROJECT_SLUG}."

WORKSPACE_DIR=/home/devclaw-svc/.openclaw/workspace
DEVCLAW_DIR="${WORKSPACE_DIR}/devclaw"
PROJECT_DIR="${DEVCLAW_DIR}/projects/${PROJECT_NAME}"
REPO_ROOT=/workspace/repos
REPO_PATH="${REPO_ROOT}/${REPO}"
REPO_URL="https://github.com/${FULL_NAME}.git"
BROKER_SOCKET=/run/devclaw/github-token-broker.sock
HELPER=/opt/devclaw/bin/github-app-git-credential-helper.sh
MARKER=/var/lib/devclaw/stage6-compose-to-aspire-project-registered

[[ -S "$BROKER_SOCKET" ]] || fail "GitHub token broker socket is absent: ${BROKER_SOCKET}"
[[ -x "$HELPER" ]] || fail "Git credential helper is absent or not executable: ${HELPER}"

install -d -o devclaw-svc -g devclaw-svc -m 0750 "$REPO_ROOT" "$WORKSPACE_DIR" "$DEVCLAW_DIR" "$PROJECT_DIR" \
  "$PROJECT_DIR/prompts" "$DEVCLAW_DIR/prompts"

if [[ -d "$REPO_PATH/.git" ]]; then
  actual_remote="$(run_as_devclaw git -C "$REPO_PATH" remote get-url origin)"
  [[ "$actual_remote" == "$REPO_URL" || "$actual_remote" == "https://github.com/${FULL_NAME}" ]] ||
    fail "Existing repository remote is not approved: ${actual_remote}"
  log "Approved repository already cloned."
else
  if [[ -e "$REPO_PATH" ]]; then
    fail "Repository path exists but is not a git repository: ${REPO_PATH}"
  fi
  log "Cloning approved repository ${FULL_NAME}."
  run_as_devclaw git \
    -c "credential.helper=${HELPER}" \
    clone "$REPO_URL" "$REPO_PATH"
fi

run_as_devclaw git -C "$REPO_PATH" config credential.helper "$HELPER"
run_as_devclaw git -C "$REPO_PATH" config --unset-all credential.helper || true
run_as_devclaw git -C "$REPO_PATH" config --add credential.helper "$HELPER"
run_as_devclaw git -C "$REPO_PATH" remote set-url origin "$REPO_URL"
run_as_devclaw git -C "$REPO_PATH" fetch --prune origin "$BASE_BRANCH"
run_as_devclaw git -C "$REPO_PATH" rev-parse --verify "origin/${BASE_BRANCH}" >/dev/null
if run_as_devclaw git -C "$REPO_PATH" status --porcelain | grep -q .; then
  fail "Repository worktree is dirty before Stage 6 preparation; refusing to overwrite local changes."
fi
current_branch="$(run_as_devclaw git -C "$REPO_PATH" branch --show-current)"
if [[ "$current_branch" != "$BASE_BRANCH" ]]; then
  run_as_devclaw git -C "$REPO_PATH" checkout "$BASE_BRANCH"
fi
run_as_devclaw git -C "$REPO_PATH" merge --ff-only "origin/${BASE_BRANCH}"

cat > "${DEVCLAW_DIR}/workflow.yaml" <<'YAML'
roles:
  architect:
    maxWorkers: 1
    levels: [junior, senior]
    defaultLevel: senior
    models:
      junior: openai/gpt-5.5
      senior: openai/gpt-5.5
    completionResults: [done, blocked]
  developer:
    maxWorkers: 1
    levels: [junior, medior, senior]
    defaultLevel: senior
    models:
      junior: openai/gpt-5.5
      medior: openai/gpt-5.5
      senior: openai/gpt-5.5
    completionResults: [done, blocked]
  tester:
    maxWorkers: 1
    levels: [junior, medior, senior]
    defaultLevel: medior
    models:
      junior: openai/gpt-5.5
      medior: openai/gpt-5.5
      senior: openai/gpt-5.5
    completionResults: [pass, fail, refine, blocked]
  reviewer: false

workflow:
  initial: planning
  reviewPolicy: human
  testPolicy: agent
  roleExecution: sequential
  maxWorkersPerLevel: 1
  states:
    planning:
      type: hold
      label: Planning
      color: "#95a5a6"
      description: Operator reviews task scope before architecture research.
      on:
        APPROVE: toResearch
    toResearch:
      type: queue
      role: architect
      label: Architecture Research
      color: "#0075ca"
      priority: 1
      on:
        PICKUP: researching
    researching:
      type: active
      role: architect
      label: Researching
      color: "#4a90e2"
      on:
        COMPLETE: architectureApproval
        BLOCKED: refining
    architectureApproval:
      type: hold
      label: Human Architecture Approval
      color: "#d4c5f9"
      description: Operator must approve architecture before implementation.
      on:
        APPROVE: todo
        REJECT: refining
    todo:
      type: queue
      role: developer
      label: Implementation
      color: "#0366d6"
      priority: 2
      on:
        PICKUP: doing
    doing:
      type: active
      role: developer
      label: Implementing
      color: "#f0ad4e"
      on:
        COMPLETE:
          target: toTest
          actions:
            - detectPr
        BLOCKED: refining
    toTest:
      type: queue
      role: tester
      label: Validation
      color: "#5bc0de"
      priority: 3
      on:
        PICKUP: testing
    testing:
      type: active
      role: tester
      label: Validating
      color: "#9b59b6"
      on:
        PASS: toReview
        FAIL: toImprove
        REFINE: refining
        BLOCKED: refining
    toReview:
      type: hold
      label: Human Review
      color: "#7057ff"
      description: Operator reviews final migration result. No automatic merge action is configured.
      on:
        APPROVE: knowledgeReview
        REJECT: toImprove
    reviewing:
      type: terminal
      label: Agent Review Disabled
      color: "#c5def5"
      description: Reviewer workers are disabled for this controlled experiment.
    knowledgeReview:
      type: hold
      label: Knowledge Review
      color: "#0e8a16"
      description: Operator decides whether reusable migration knowledge exists.
      on:
        APPROVE: done
        REJECT: done
    done:
      type: terminal
      label: Done
      color: "#5cb85c"
    rejected:
      type: terminal
      label: Rejected
      color: "#e11d48"
    toImprove:
      type: hold
      label: To Improve
      color: "#d9534f"
      on:
        APPROVE: todo
    refining:
      type: hold
      label: Refining
      color: "#f39c12"
      on:
        APPROVE: toResearch
YAML

cp "${DEVCLAW_DIR}/workflow.yaml" "${PROJECT_DIR}/workflow.yaml"

cat > "${DEVCLAW_DIR}/prompts/architect.md" <<'EOF_PROMPT'
Perform architecture research only. Produce findings, options, risks, and a recommended Compose-to-Aspire migration approach. Do not implement code.
EOF_PROMPT

cat > "${DEVCLAW_DIR}/prompts/developer.md" <<'EOF_PROMPT'
Implement only after the operator-approved architecture gate. Keep changes focused, reviewable, and aligned with the registered workflow.
EOF_PROMPT

cat > "${DEVCLAW_DIR}/prompts/tester.md" <<'EOF_PROMPT'
Validate the migration with deterministic commands and report evidence. Do not merge or approve pull requests.
EOF_PROMPT

cp "${DEVCLAW_DIR}/prompts/architect.md" "${PROJECT_DIR}/prompts/architect.md"
cp "${DEVCLAW_DIR}/prompts/developer.md" "${PROJECT_DIR}/prompts/developer.md"
cp "${DEVCLAW_DIR}/prompts/tester.md" "${PROJECT_DIR}/prompts/tester.md"

cat > "${DEVCLAW_DIR}/projects.json" <<EOF_JSON
{
  "projects": {
    "${PROJECT_SLUG}": {
      "slug": "${PROJECT_SLUG}",
      "name": "${PROJECT_NAME}",
      "repo": "${REPO_PATH}",
      "repoRemote": "${REPO_URL}",
      "groupName": "OpenClaw Control UI",
      "deployUrl": "",
      "baseBranch": "${BASE_BRANCH}",
      "deployBranch": "${BASE_BRANCH}",
      "channels": [
        {
          "channelId": "${CHANNEL_ID}",
          "channel": "openclaw",
          "name": "primary",
          "events": [
            "*"
          ]
        }
      ],
      "provider": "github",
      "workers": {
        "architect": {
          "levels": {
            "junior": [
              { "active": false, "issueId": null, "sessionKey": null, "startTime": null }
            ],
            "senior": [
              { "active": false, "issueId": null, "sessionKey": null, "startTime": null }
            ]
          }
        },
        "developer": {
          "levels": {
            "junior": [
              { "active": false, "issueId": null, "sessionKey": null, "startTime": null }
            ],
            "medior": [
              { "active": false, "issueId": null, "sessionKey": null, "startTime": null }
            ],
            "senior": [
              { "active": false, "issueId": null, "sessionKey": null, "startTime": null }
            ]
          }
        },
        "tester": {
          "levels": {
            "junior": [
              { "active": false, "issueId": null, "sessionKey": null, "startTime": null }
            ],
            "medior": [
              { "active": false, "issueId": null, "sessionKey": null, "startTime": null }
            ],
            "senior": [
              { "active": false, "issueId": null, "sessionKey": null, "startTime": null }
            ]
          }
        },
        "reviewer": {
          "levels": {}
        }
      }
    }
  }
}
EOF_JSON

cat > "${DEVCLAW_DIR}/stage6-boundary.json" <<EOF_JSON
{
  "stage": 6,
  "repository": "${FULL_NAME}",
  "repoPath": "${REPO_PATH}",
  "project": "${PROJECT_NAME}",
  "projectSlug": "${PROJECT_SLUG}",
  "baseBranch": "${BASE_BRANCH}",
  "channelId": "${CHANNEL_ID}",
  "model": "openai/gpt-5.5",
  "heartbeatEnabled": false,
  "automaticMergeEnabled": false,
  "skillWorkshop": {
    "autonomousEnabled": false,
    "approvalPolicy": "pending",
    "proposalCreated": false
  }
}
EOF_JSON

chown -R devclaw-svc:devclaw-svc "$DEVCLAW_DIR"
find "$DEVCLAW_DIR" -type d -exec chmod 0750 {} +
find "$DEVCLAW_DIR" -type f -exec chmod 0640 {} +

run_as_devclaw openclaw config set skills.workshop.autonomous.enabled false
run_as_devclaw openclaw config set skills.workshop.approvalPolicy pending
run_as_devclaw openclaw config set plugins.entries.devclaw.config.projectExecution sequential
run_as_devclaw openclaw config set plugins.entries.devclaw.config.work_heartbeat.enabled false

ensure_label() {
  local name="$1"
  local color="$2"
  local description="$3"
  local token_json token status
  token_json="$(curl --silent --show-error --fail --unix-socket "$BROKER_SOCKET" http://localhost/token)"
  token="$(printf '%s\n' "$token_json" | jq -r '.token')"
  [[ -n "$token" && "$token" != "null" ]] || fail "Broker did not return a GitHub token."

  status="$(
    curl --silent --show-error --output /tmp/devclaw-label-response.json --write-out '%{http_code}' \
      -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${FULL_NAME}/labels/$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$name")"
  )"
  if [[ "$status" == "200" ]]; then
    return 0
  fi
  [[ "$status" == "404" ]] || fail "Unexpected GitHub label lookup status ${status} for ${name}."

  status="$(
    jq -n --arg name "$name" --arg color "$color" --arg description "$description" \
      '{name:$name,color:$color,description:$description}' |
    curl --silent --show-error --output /tmp/devclaw-label-response.json --write-out '%{http_code}' \
      -X POST \
      -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${FULL_NAME}/labels" \
      --data @-
  )"
  [[ "$status" == "201" || "$status" == "422" ]] ||
    fail "Unexpected GitHub label create status ${status} for ${name}."
}

ensure_label "Planning" "95a5a6" "DevClaw workflow state: Planning"
ensure_label "Architecture Research" "0075ca" "DevClaw workflow state: Architecture Research"
ensure_label "Researching" "4a90e2" "DevClaw workflow state: Researching"
ensure_label "Human Architecture Approval" "d4c5f9" "DevClaw workflow state: Human Architecture Approval"
ensure_label "Implementation" "0366d6" "DevClaw workflow state: Implementation"
ensure_label "Implementing" "f0ad4e" "DevClaw workflow state: Implementing"
ensure_label "Validation" "5bc0de" "DevClaw workflow state: Validation"
ensure_label "Validating" "9b59b6" "DevClaw workflow state: Validating"
ensure_label "Human Review" "7057ff" "DevClaw workflow state: Human Review"
ensure_label "Knowledge Review" "0e8a16" "DevClaw workflow state: Knowledge Review"
ensure_label "Done" "5cb85c" "DevClaw workflow state: Done"
ensure_label "Rejected" "e11d48" "DevClaw workflow state: Rejected"
ensure_label "To Improve" "d9534f" "DevClaw workflow state: To Improve"
ensure_label "Refining" "f39c12" "DevClaw workflow state: Refining"
ensure_label "Agent Review Disabled" "c5def5" "DevClaw workflow state: Agent Review Disabled"
ensure_label "architect:junior" "0075ca" "DevClaw role level: architect junior"
ensure_label "architect:senior" "0075ca" "DevClaw role level: architect senior"
ensure_label "developer:junior" "0366d6" "DevClaw role level: developer junior"
ensure_label "developer:medior" "0366d6" "DevClaw role level: developer medior"
ensure_label "developer:senior" "0366d6" "DevClaw role level: developer senior"
ensure_label "tester:junior" "5bc0de" "DevClaw role level: tester junior"
ensure_label "tester:medior" "5bc0de" "DevClaw role level: tester medior"
ensure_label "tester:senior" "5bc0de" "DevClaw role level: tester senior"
ensure_label "review:human" "7057ff" "DevClaw routing label: human review"
ensure_label "review:agent" "7057ff" "DevClaw routing label: agent review"
ensure_label "review:skip" "7057ff" "DevClaw routing label: skip review"
ensure_label "test:skip" "5bc0de" "DevClaw routing label: skip test"

rm -f /tmp/devclaw-label-response.json

marker_tmp="$(mktemp /var/lib/devclaw/.stage6-compose.XXXXXX)"
cat > "$marker_tmp" <<EOF_MARKER
stage6_project_registered=true
repository=${FULL_NAME}
repo_path=${REPO_PATH}
project=${PROJECT_NAME}
project_slug=${PROJECT_SLUG}
base_branch=${BASE_BRANCH}
channel_id=${CHANNEL_ID}
workflow=compose-to-aspire-controlled
model_default=openai/gpt-5.5
heartbeat=false
automatic_merge=false
skill_workshop_autonomous=false
skill_workshop_approval_policy=pending
skill_proposal_created=false
EOF_MARKER
chown devclaw-svc:devclaw-svc "$marker_tmp"
chmod 0640 "$marker_tmp"
mv -f "$marker_tmp" "$MARKER"

log "Stage 6 project registration and workflow preparation completed."
