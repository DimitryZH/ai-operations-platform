#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

EXPECTED_PACKAGE="@laurentenhoor/devclaw"
EXPECTED_VERSION="1.6.10"
EXPECTED_INTEGRITY="sha512-XSzsSi52hFZjj+y+Iww9P5s28NmCNQBvGOZzQRBUvbOzEJM+R4S+EcpdqxPzbFmS66X6KjMEqf3wSR/WeMFkdg=="
EXPECTED_PLUGIN_ID="devclaw"
EXPECTED_TOOL_COUNT="23"
EXPECTED_JSON_RESULT_IMPORT_COUNT="23"
COMPAT_REVISION="${DEVCLAW_COMPAT_REVISION:-aiops-1}"

fail() {
  printf '[build-devclaw-compat-package] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[build-devclaw-compat-package] %s\n' "$*"
}

usage() {
  cat <<'USAGE'
Usage:
  build-devclaw-compat-package.sh --output-dir DIR [--upstream-tarball FILE] [--overlay FILE]

Builds a local npm-pack tarball for @laurentenhoor/devclaw@1.6.10 with the
reviewed OpenClaw 2026.7.1 manifest compatibility overlay.
USAGE
}

OUTPUT_DIR=""
UPSTREAM_TARBALL=""
OVERLAY_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/devclaw-manifest-overlay.json"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --upstream-tarball)
      UPSTREAM_TARBALL="${2:-}"
      shift 2
      ;;
    --overlay)
      OVERLAY_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$OUTPUT_DIR" ]] || fail "--output-dir is required."
[[ -f "$OVERLAY_FILE" ]] || fail "Missing overlay file: $OVERLAY_FILE"

command -v npm >/dev/null 2>&1 || fail "Missing npm."
command -v node >/dev/null 2>&1 || fail "Missing node."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
command -v tar >/dev/null 2>&1 || fail "Missing tar."
command -v sha256sum >/dev/null 2>&1 || fail "Missing sha256sum."

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
case "$OUTPUT_DIR" in
  *"/gcp/agent-devbox"*) fail "Output directory must be ignored and outside tracked source." ;;
esac

WORK_DIR="$(mktemp -d "$OUTPUT_DIR/devclaw-compat-build.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

NPM_VIEW="$OUTPUT_DIR/upstream-npm-view.json"
log "Verifying upstream npm metadata"
npm view "${EXPECTED_PACKAGE}@${EXPECTED_VERSION}" \
  name version dist.integrity dist.shasum dist.tarball peerDependencies engines \
  --json > "$NPM_VIEW"

node - "$NPM_VIEW" "$EXPECTED_PACKAGE" "$EXPECTED_VERSION" "$EXPECTED_INTEGRITY" <<'NODE'
const fs = require("fs");
const [file, expectedName, expectedVersion, expectedIntegrity] = process.argv.slice(2);
const metadata = JSON.parse(fs.readFileSync(file, "utf8"));
function value(key) {
  return metadata[key] ?? key.split(".").reduce((current, part) => current && current[part], metadata);
}
if (metadata.name !== expectedName) throw new Error(`name mismatch: ${metadata.name}`);
if (metadata.version !== expectedVersion) throw new Error(`version mismatch: ${metadata.version}`);
if (value("dist.integrity") !== expectedIntegrity) throw new Error(`integrity mismatch: ${value("dist.integrity")}`);
if (!String(value("dist.tarball") || "").startsWith("https://registry.npmjs.org/")) {
  throw new Error(`unexpected tarball URL: ${value("dist.tarball")}`);
}
NODE

if [[ -n "$UPSTREAM_TARBALL" ]]; then
  [[ -f "$UPSTREAM_TARBALL" ]] || fail "Missing upstream tarball: $UPSTREAM_TARBALL"
  cp "$UPSTREAM_TARBALL" "$WORK_DIR/upstream.tgz"
else
  log "Fetching exact upstream npm artifact"
  npm pack "${EXPECTED_PACKAGE}@${EXPECTED_VERSION}" --pack-destination "$WORK_DIR" > "$WORK_DIR/npm-pack.out"
  PACKED_NAME="$(tail -n1 "$WORK_DIR/npm-pack.out")"
  [[ -n "$PACKED_NAME" ]] || fail "npm pack did not report a tarball name."
  mv "$WORK_DIR/$PACKED_NAME" "$WORK_DIR/upstream.tgz"
fi

UPSTREAM_SHA256="$(sha256sum "$WORK_DIR/upstream.tgz" | awk '{print $1}')"
log "Upstream tarball SHA-256: $UPSTREAM_SHA256"

mkdir "$WORK_DIR/original" "$WORK_DIR/patched"
tar -xzf "$WORK_DIR/upstream.tgz" -C "$WORK_DIR/original"
cp -a "$WORK_DIR/original/package" "$WORK_DIR/patched/package"

PACKAGE_JSON="$WORK_DIR/patched/package/package.json"
PLUGIN_JSON="$WORK_DIR/patched/package/openclaw.plugin.json"
ORIGINAL_PLUGIN_JSON="$WORK_DIR/original/package/openclaw.plugin.json"

[[ "$(jq -r '.name' "$PACKAGE_JSON")" == "$EXPECTED_PACKAGE" ]] ||
  fail "package name changed."
[[ "$(jq -r '.version' "$PACKAGE_JSON")" == "$EXPECTED_VERSION" ]] ||
  fail "package version changed."
[[ "$(jq -r '.id' "$ORIGINAL_PLUGIN_JSON")" == "$EXPECTED_PLUGIN_ID" ]] ||
  fail "unexpected original plugin id."
[[ "$(jq -r 'has("contracts")' "$ORIGINAL_PLUGIN_JSON")" == "false" ]] ||
  fail "upstream manifest unexpectedly already contains contracts."
[[ "$(jq -r 'has("activation")' "$ORIGINAL_PLUGIN_JSON")" == "false" ]] ||
  fail "upstream manifest unexpectedly already contains activation."

log "Applying reviewed manifest overlay"
jq -s '.[0] * .[1]' "$ORIGINAL_PLUGIN_JSON" "$OVERLAY_FILE" > "$PLUGIN_JSON.tmp"
mv "$PLUGIN_JSON.tmp" "$PLUGIN_JSON"

log "Applying OpenClaw 2026.7.1 tool-result compatibility shim"
node - "$WORK_DIR/patched/package/dist/index.js" "$EXPECTED_JSON_RESULT_IMPORT_COUNT" <<'NODE'
const fs = require("fs");
const [indexFile, expectedImportCount] = process.argv.slice(2);
let source = fs.readFileSync(indexFile, "utf8");
const importPattern = /^import\s+\{\s*jsonResult(?:\s+as\s+(jsonResult\d+))?\s*\}\s+from\s+["']openclaw\/plugin-sdk["'];\r?\n?/gm;
const aliases = [];
source = source.replace(importPattern, (_match, alias) => {
  const name = alias || "jsonResult";
  aliases.push(name);
  return `const ${name} = __devclawAiopsJsonResult;\n`;
});
if (aliases.length !== Number(expectedImportCount)) {
  throw new Error(`expected ${expectedImportCount} jsonResult imports, found ${aliases.length}`);
}
if (new Set(aliases).size !== aliases.length) {
  throw new Error("duplicate jsonResult compatibility aliases found");
}
if (/import\s+\{\s*jsonResult(?:\s+as\s+jsonResult\d+)?\s*\}\s+from\s+["']openclaw\/plugin-sdk["'];/.test(source)) {
  throw new Error("unpatched jsonResult import remains");
}
const helper = `\n// aiops-1 compatibility shim: OpenClaw 2026.7.1 does not export jsonResult from openclaw/plugin-sdk.\nfunction __devclawAiopsJsonResult(payload) {\n  return {\n    content: [{ type: "text", text: JSON.stringify(payload, null, 2) }],\n    details: payload\n  };\n}\n\n`;
const firstAlias = `const ${aliases[0]} = __devclawAiopsJsonResult;\n`;
source = source.replace(firstAlias, `${helper}${firstAlias}`);
for (const alias of aliases) {
  const aliasPattern = new RegExp(`\\b${alias}\\s*\\(`);
  if (!aliasPattern.test(source)) {
    throw new Error(`jsonResult alias is not used after compatibility patch: ${alias}`);
  }
}
fs.writeFileSync(indexFile, source);
console.log(JSON.stringify({ jsonResultImportCount: aliases.length, aliases }));
NODE

log "Applying workflow-aware research_task queue-label compatibility patch"
node - "$WORK_DIR/patched/package/dist/index.js" <<'NODE'
const fs = require("fs");
const [indexFile] = process.argv.slice(2);
let source = fs.readFileSync(indexFile, "utf8");

function replaceOnce(search, replacement, description) {
  const count = source.split(search).length - 1;
  if (count !== 1) {
    throw new Error(`${description}: expected one match, found ${count}`);
  }
  source = source.replace(search, replacement);
}

replaceOnce(
  'var TO_RESEARCH_LABEL = "To Research";\nfunction createResearchTaskTool(ctx) {',
  `function __devclawAiopsTransitionTargetKey(transition) {\n  return typeof transition === "string" ? transition : transition?.target;\n}\nfunction __devclawAiopsResolveArchitectQueue(workflow, role) {\n  const activeEntry = Object.entries(workflow.states).find(\n    ([, state]) => state.type === StateType.ACTIVE && state.role === role\n  );\n  if (!activeEntry) {\n    throw new Error(\`No active state for role "\${role}".\`);\n  }\n  const [activeStateKey, activeState] = activeEntry;\n  const queueEntry = Object.entries(workflow.states).find(([, state]) => {\n    if (state.type !== StateType.QUEUE || state.role !== role) return false;\n    return __devclawAiopsTransitionTargetKey(state.on?.[WorkflowEvent.PICKUP]) === activeStateKey;\n  });\n  if (!queueEntry) {\n    throw new Error(\`No queue state for role "\${role}" has a PICKUP transition to active state "\${activeStateKey}".\`);\n  }\n  const [queueStateKey, queueState] = queueEntry;\n  return {\n    queueStateKey,\n    queueLabel: queueState.label,\n    activeStateKey,\n    activeLabel: activeState.label\n  };\n}\nfunction createResearchTaskTool(ctx) {`,
  "research_task queue helper insertion"
);
replaceOnce(
  'description: `Spawn an architect to research a design/architecture problem. Creates a "To Research" issue and dispatches an architect worker.',
  'description: `Spawn an architect to research a design/architecture problem. Creates an issue in the configured architect queue state and dispatches an architect worker.',
  "research_task tool description queue label"
);
replaceOnce(
  "3. Create implementation tasks via task_create (land in Planning for operator review)",
  "3. Post development-ready findings and follow project-specific role instructions for any follow-up task boundaries",
  "research_task tool description task_create boundary"
);
replaceOnce(
  '      const resolvedRole = resolvedConfig.roles[role];\n      const model = resolveModel(role, level, resolvedRole);\n      if (dryRun) {',
  '      const resolvedRole = resolvedConfig.roles[role];\n      const model = resolveModel(role, level, resolvedRole);\n      const researchQueue = __devclawAiopsResolveArchitectQueue(resolvedConfig.workflow, role);\n      const queueLabel = researchQueue.queueLabel;\n      const activeLabel = getActiveLabel(resolvedConfig.workflow, role);\n      if (activeLabel !== researchQueue.activeLabel) {\n        throw new Error(`Architect active label mismatch: query resolved "${activeLabel}", queue resolver resolved "${researchQueue.activeLabel}".`);\n      }\n      if (dryRun) {',
  "research_task queue resolution before dry-run"
);
replaceOnce(
  '          issue: { title, label: TO_RESEARCH_LABEL },\n          research: { level, model, status: "dry_run" },\n          announcement: `\\u{1F4D0} [DRY RUN] Would create research ticket and dispatch ${role} (${level}) for: ${title}`',
  '          issue: { title, label: queueLabel },\n          research: {\n            level,\n            model,\n            status: "dry_run",\n            queueLabel,\n            activeLabel,\n            queueState: researchQueue.queueStateKey,\n            activeState: researchQueue.activeStateKey\n          },\n          announcement: `\\u{1F4D0} [DRY RUN] Would create research ticket in ${queueLabel} and dispatch ${role} (${level}) to ${activeLabel} for: ${title}`',
  "research_task dry-run queue metadata"
);
replaceOnce(
  "      const issue2 = await provider.createIssue(title, issueBody, TO_RESEARCH_LABEL);",
  "      const issue2 = await provider.createIssue(title, issueBody, queueLabel);",
  "research_task live issue queue label"
);
replaceOnce(
  "          issue: { id: issue2.iid, title: issue2.title, url: issue2.web_url, label: TO_RESEARCH_LABEL },",
  "          issue: { id: issue2.iid, title: issue2.title, url: issue2.web_url, label: queueLabel },",
  "research_task queued response queue label"
);
replaceOnce(
  "            level,\n            status: \"queued\",",
  "            level,\n            model,\n            queueLabel,\n            activeLabel,\n            queueState: researchQueue.queueStateKey,\n            activeState: researchQueue.activeStateKey,\n            status: \"queued\",",
  "research_task busy queue metadata"
);
replaceOnce(
  "      const toLabel = getActiveLabel(resolvedConfig.workflow, role);",
  "      const toLabel = activeLabel;",
  "research_task active label reuse"
);
replaceOnce(
  "        fromLabel: TO_RESEARCH_LABEL,",
  "        fromLabel: queueLabel,",
  "research_task dispatch from label"
);

if (/\bTO_RESEARCH_LABEL\b/.test(source)) {
  throw new Error("legacy TO_RESEARCH_LABEL runtime path remains");
}
if (/provider\.createIssue\(title,\s*issueBody,\s*["']To Research["']\)/.test(source)) {
  throw new Error("legacy hard-coded To Research issue creation remains");
}
if (/fromLabel:\s*["']To Research["']/.test(source)) {
  throw new Error("legacy hard-coded To Research dispatch fromLabel remains");
}
if (source.includes('Architecture Research')) {
  throw new Error("research_task patch must not hard-code the project-specific Architecture Research label");
}
fs.writeFileSync(indexFile, source);
NODE

log "Applying research_task existing-issue dispatch compatibility patch"
node - "$WORK_DIR/patched/package/dist/index.js" <<'NODE'
const fs = require("fs");
const [indexFile] = process.argv.slice(2);
let source = fs.readFileSync(indexFile, "utf8");

function replaceOnce(search, replacement, description) {
  const count = source.split(search).length - 1;
  if (count !== 1) {
    throw new Error(`${description}: expected one match, found ${count}`);
  }
  source = source.replace(search, replacement);
}

replaceOnce(
  "function createResearchTaskTool(ctx) {",
  `function __devclawAiopsNormalizeExistingIssueId(value) {
  if (value == null || value === "") return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error("existingIssueId must be a positive integer when provided.");
  }
  return parsed;
}
function __devclawAiopsIssueLabels(issue) {
  return (issue.labels ?? []).map((label) => typeof label === "string" ? label : label?.name).filter(Boolean);
}
function __devclawAiopsIssueAuthor(issue) {
  return issue.author?.username ?? issue.author?.login ?? issue.user?.username ?? issue.user?.login ?? "";
}
function __devclawAiopsIssueAssignees(issue) {
  return (issue.assignees ?? []).map((assignee) => assignee?.username ?? assignee?.login ?? assignee?.name).filter(Boolean);
}
function __devclawAiopsProjectRepoSlug(project) {
  const source = project.repoRemote ?? project.remote ?? project.repository ?? "";
  const match = String(source).match(/github\\.com[:/]([^/]+\\/[^/.]+)(?:\\.git)?$/i);
  return match?.[1] ?? null;
}
function __devclawAiopsValidateExistingResearchIssue({ issue, issueId, project, workflow, queueLabel, activeLabel }) {
  const actualIssueId = issue.iid ?? issue.number ?? issue.id;
  if (String(actualIssueId) !== String(issueId)) {
    throw new Error(\`Existing issue lookup returned #\${actualIssueId}, expected #\${issueId}.\`);
  }
  const state = String(issue.state ?? issue.status ?? "").toLowerCase();
  if (state && state !== "opened" && state !== "open") {
    throw new Error(\`Existing issue #\${issueId} is not open; state is "\${state}".\`);
  }
  const repoSlug = __devclawAiopsProjectRepoSlug(project);
  const issueUrl = issue.web_url ?? issue.html_url ?? issue.url ?? "";
  if (repoSlug && issueUrl && !String(issueUrl).includes(\`/\${repoSlug}/issues/\${issueId}\`)) {
    throw new Error(\`Existing issue #\${issueId} does not belong to repository \${repoSlug}.\`);
  }
  const labels = __devclawAiopsIssueLabels(issue);
  const stateLabels = getStateLabels(workflow);
  const currentStateLabels = labels.filter((label) => stateLabels.includes(label));
  if (currentStateLabels.length > 1) {
    throw new Error(\`Existing issue #\${issueId} has conflicting workflow state labels: \${currentStateLabels.join(", ")}.\`);
  }
  if (currentStateLabels.length === 1 && currentStateLabels[0] !== queueLabel) {
    if (currentStateLabels[0] === activeLabel) {
      throw new Error(\`Existing issue #\${issueId} is already active in \${activeLabel}.\`);
    }
    throw new Error(\`Existing issue #\${issueId} is in workflow state "\${currentStateLabels[0]}", expected no state label or "\${queueLabel}".\`);
  }
  return {
    labels,
    stateLabels: currentStateLabels,
    author: __devclawAiopsIssueAuthor(issue),
    assignees: __devclawAiopsIssueAssignees(issue)
  };
}
function __devclawAiopsDescriptionForExistingIssue(issue, issueBody) {
  const existingBody = issue.description ?? issue.body ?? "";
  return [existingBody, "## Additional Architect Instructions", issueBody].filter(Boolean).join("\\n\\n");
}
function createResearchTaskTool(ctx) {`,
  "research_task existing issue helper insertion"
);
replaceOnce(
  '        dryRun: {\n          type: "boolean",\n          description: "Preview without executing. Defaults to false."\n        }',
  '        dryRun: {\n          type: "boolean",\n          description: "Preview without executing. Defaults to false."\n        },\n        existingIssueId: {\n          type: "number",\n          description: "Optional existing issue number to validate and dispatch without creating a duplicate issue."\n        }',
  "research_task existingIssueId parameter"
);
replaceOnce(
  "      const dryRun = params.dryRun ?? false;",
  "      const dryRun = params.dryRun ?? false;\n      const existingIssueId = __devclawAiopsNormalizeExistingIssueId(params.existingIssueId);",
  "research_task existingIssueId param read"
);
replaceOnce(
  '      if (activeLabel !== researchQueue.activeLabel) {\n        throw new Error(`Architect active label mismatch: query resolved "${activeLabel}", queue resolver resolved "${researchQueue.activeLabel}".`);\n      }\n      if (dryRun) {',
  '      if (activeLabel !== researchQueue.activeLabel) {\n        throw new Error(`Architect active label mismatch: query resolved "${activeLabel}", queue resolver resolved "${researchQueue.activeLabel}".`);\n      }\n      let existingIssue = null;\n      let existingIssueValidation = null;\n      if (existingIssueId != null) {\n        existingIssue = await provider.getIssue(existingIssueId);\n        existingIssueValidation = __devclawAiopsValidateExistingResearchIssue({\n          issue: existingIssue,\n          issueId: existingIssueId,\n          project,\n          workflow: resolvedConfig.workflow,\n          queueLabel,\n          activeLabel\n        });\n        const activeRoleWorker = getRoleWorker(project, role);\n        const activeSlotCount = countActiveSlots(activeRoleWorker);\n        if (activeSlotCount > 0) {\n          throw new Error(`Cannot dispatch existing issue #${existingIssueId}; ${role} has ${activeSlotCount} active worker slot(s).`);\n        }\n      }\n      if (dryRun && existingIssue) {\n        return jsonResult9({\n          success: true,\n          dryRun: true,\n          issue: {\n            id: existingIssue.iid ?? existingIssue.number ?? existingIssueId,\n            title: existingIssue.title,\n            url: existingIssue.web_url ?? existingIssue.html_url,\n            label: queueLabel,\n            existing: true,\n            author: existingIssueValidation.author,\n            assignees: existingIssueValidation.assignees\n          },\n          research: {\n            level,\n            model,\n            status: "dry_run",\n            queueLabel,\n            activeLabel,\n            queueState: researchQueue.queueStateKey,\n            activeState: researchQueue.activeStateKey,\n            noIssueCreation: true\n          },\n          announcement: `[DRY RUN] Would dispatch existing issue #${existingIssueId} from ${queueLabel} to ${activeLabel} as ${role} (${level}) without creating a new issue.`\n        });\n      }\n      if (dryRun) {',
  "research_task existing issue validation and dry-run"
);
replaceOnce(
  '      const issue2 = await provider.createIssue(title, issueBody, queueLabel);\n      provider.reactToIssue(issue2.iid, "eyes").catch(() => {\n      });\n      applyNotifyLabel(provider, issue2.iid, project, channelId, issue2.labels);\n      autoAssignOwnerLabel(workspaceDir, provider, issue2.iid, project).catch(() => {\n      });',
  '      const issue2 = existingIssue ?? await provider.createIssue(title, issueBody, queueLabel);\n      if (!existingIssue) {\n        provider.reactToIssue(issue2.iid, "eyes").catch(() => {\n        });\n        applyNotifyLabel(provider, issue2.iid, project, channelId, issue2.labels);\n        autoAssignOwnerLabel(workspaceDir, provider, issue2.iid, project).catch(() => {\n        });\n      }',
  "research_task conditional issue creation"
);
replaceOnce(
  "        issueDescription: issueBody,",
  "        issueDescription: existingIssue ? __devclawAiopsDescriptionForExistingIssue(existingIssue, issueBody) : issueBody,",
  "research_task existing issue description preservation"
);

if (!/existingIssueId:\s*\{\s*type:\s*"number"/.test(source)) {
  throw new Error("research_task existingIssueId parameter proof missing");
}
if (!/function __devclawAiopsValidateExistingResearchIssue\(\{ issue, issueId, project, workflow, queueLabel, activeLabel \}\)/.test(source)) {
  throw new Error("research_task existing issue validator helper missing");
}
if (!/noIssueCreation:\s*true/.test(source)) {
  throw new Error("research_task existing issue dry-run noIssueCreation proof missing");
}
if (!/const issue2 = existingIssue \?\? await provider\.createIssue\(title,\s*issueBody,\s*queueLabel\);/.test(source)) {
  throw new Error("research_task conditional issue creation proof missing");
}
if (!/countActiveSlots\(activeRoleWorker\)/.test(source)) {
  throw new Error("research_task active worker refusal proof missing");
}
fs.writeFileSync(indexFile, source);
NODE

log "Applying OpenClaw 2026.7.1 subagent parameter compatibility patch"
node - "$WORK_DIR/patched/package/dist/index.js" <<'NODE'
const fs = require("fs");
const [indexFile] = process.argv.slice(2);
let source = fs.readFileSync(indexFile, "utf8");
const before = '    deliver: false,\n    lane: "subagent",\n    ...opts.orchestratorSessionKey ? { spawnedBy: opts.orchestratorSessionKey } : {},\n    ...opts.extraSystemPrompt ? { extraSystemPrompt: opts.extraSystemPrompt } : {}\n';
const after = '    deliver: false,\n    lane: "subagent",\n    ...opts.extraSystemPrompt ? { extraSystemPrompt: opts.extraSystemPrompt } : {}\n';
if (!source.includes(before)) {
  throw new Error("expected unsupported spawnedBy subagent parameter path was not found");
}
source = source.replace(before, after);
if (/\bspawnedBy\b/.test(source)) {
  throw new Error("unsupported spawnedBy subagent parameter remains");
}
fs.writeFileSync(indexFile, source);
NODE

node - "$PLUGIN_JSON" "$OVERLAY_FILE" "$EXPECTED_PLUGIN_ID" "$EXPECTED_TOOL_COUNT" <<'NODE'
const fs = require("fs");
const [manifestFile, overlayFile, expectedId, expectedCount] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
const overlay = JSON.parse(fs.readFileSync(overlayFile, "utf8"));
if (manifest.id !== expectedId) throw new Error(`manifest id mismatch: ${manifest.id}`);
if (manifest.activation?.onStartup !== true) throw new Error("activation.onStartup must be true");
const tools = manifest.contracts?.tools;
if (!Array.isArray(tools)) throw new Error("contracts.tools must be an array");
const unique = new Set(tools);
if (tools.length !== Number(expectedCount)) throw new Error(`expected ${expectedCount} tools, found ${tools.length}`);
if (unique.size !== tools.length) throw new Error("contracts.tools contains duplicate names");
if (JSON.stringify(tools) !== JSON.stringify(overlay.contracts.tools)) {
  throw new Error("contracts.tools does not match reviewed overlay order/content");
}
NODE

log "Verifying only reviewed compatibility files changed"
(
  cd "$WORK_DIR/original/package"
  find . -type f -print | sort
) > "$WORK_DIR/original-files.txt"
(
  cd "$WORK_DIR/patched/package"
  find . -type f -print | sort
) > "$WORK_DIR/patched-files.txt"
diff -u "$WORK_DIR/original-files.txt" "$WORK_DIR/patched-files.txt" >/dev/null ||
  fail "patched package file list differs from upstream."

while IFS= read -r relative_path; do
  relative_path="${relative_path#./}"
  if [[ "$relative_path" == "openclaw.plugin.json" || "$relative_path" == "dist/index.js" ]]; then
    continue
  fi
  original_hash="$(sha256sum "$WORK_DIR/original/package/$relative_path" | awk '{print $1}')"
  patched_hash="$(sha256sum "$WORK_DIR/patched/package/$relative_path" | awk '{print $1}')"
  [[ "$original_hash" == "$patched_hash" ]] ||
    fail "unexpected source/package modification: $relative_path"
done < "$WORK_DIR/original-files.txt"

node - "$WORK_DIR/patched/package/dist/index.js" "$EXPECTED_JSON_RESULT_IMPORT_COUNT" <<'NODE'
const fs = require("fs");
const [indexFile, expectedImportCount] = process.argv.slice(2);
const source = fs.readFileSync(indexFile, "utf8");
if (!source.includes("function __devclawAiopsJsonResult(payload)")) {
  throw new Error("missing aiops-1 jsonResult compatibility shim");
}
if (/import\s+\{\s*jsonResult(?:\s+as\s+jsonResult\d+)?\s*\}\s+from\s+["']openclaw\/plugin-sdk["'];/.test(source)) {
  throw new Error("unavailable openclaw/plugin-sdk jsonResult import remains");
}
const aliases = Array.from(source.matchAll(/\bconst\s+(jsonResult\d*)\s*=\s*__devclawAiopsJsonResult;/g), (match) => match[1]);
if (aliases.length !== Number(expectedImportCount)) {
  throw new Error(`expected ${expectedImportCount} jsonResult aliases, found ${aliases.length}`);
}
if (new Set(aliases).size !== aliases.length) {
  throw new Error("duplicate jsonResult compatibility aliases found");
}
NODE

node - "$WORK_DIR/patched/package/dist/index.js" <<'NODE'
const fs = require("fs");
const [indexFile] = process.argv.slice(2);
const source = fs.readFileSync(indexFile, "utf8");
if (/\bspawnedBy\b/.test(source)) {
  throw new Error("unsupported spawnedBy subagent parameter remains");
}
if (!/lane:\s*"subagent",\n\s*\.\.\.opts\.extraSystemPrompt \? \{ extraSystemPrompt: opts\.extraSystemPrompt \} : \{\}/.test(source)) {
  throw new Error("subagent params compatibility patch proof missing");
}
NODE

node - "$WORK_DIR/patched/package/dist/index.js" <<'NODE'
const fs = require("fs");
const [indexFile] = process.argv.slice(2);
const source = fs.readFileSync(indexFile, "utf8");
function requireMatch(pattern, description) {
  if (!pattern.test(source)) throw new Error(`missing research_task compatibility proof: ${description}`);
}
if (/\bTO_RESEARCH_LABEL\b/.test(source)) {
  throw new Error("legacy TO_RESEARCH_LABEL runtime path remains");
}
requireMatch(/function __devclawAiopsResolveArchitectQueue\(workflow,\s*role\)/, "queue resolver helper");
requireMatch(/state\.type !== StateType\.QUEUE \|\| state\.role !== role/, "queue resolver filters architect queue states");
requireMatch(/state\.on\?\.\[WorkflowEvent\.PICKUP\]\) === activeStateKey/, "queue resolver follows PICKUP to active state");
requireMatch(/const queueLabel = researchQueue\.queueLabel;/, "single queue label binding");
requireMatch(/issue:\s*\{\s*title,\s*label:\s*queueLabel\s*\}/, "dry-run issue uses workflow queue label");
requireMatch(/provider\.createIssue\(title,\s*issueBody,\s*queueLabel\)/, "live issue creation uses workflow queue label");
requireMatch(/fromLabel:\s*queueLabel/, "dispatch fromLabel uses workflow queue label");
requireMatch(/const toLabel = activeLabel;/, "dispatch active label uses resolved active label");
requireMatch(/existingIssueId:\s*\{\s*type:\s*"number"/, "existing issue parameter");
requireMatch(/function __devclawAiopsValidateExistingResearchIssue\(\{ issue, issueId, project, workflow, queueLabel, activeLabel \}\)/, "existing issue validator");
requireMatch(/noIssueCreation:\s*true/, "existing issue dry-run no issue creation marker");
requireMatch(/const issue2 = existingIssue \?\? await provider\.createIssue\(title,\s*issueBody,\s*queueLabel\);/, "conditional issue creation");
requireMatch(/countActiveSlots\(activeRoleWorker\)/, "active worker refusal");
if (/provider\.createIssue\(title,\s*issueBody,\s*["']To Research["']\)/.test(source) || /fromLabel:\s*["']To Research["']/.test(source)) {
  throw new Error("legacy hard-coded To Research dispatch path remains");
}
if (source.includes("Architecture Research")) {
  throw new Error("research_task patch must not hard-code the project-specific Architecture Research label");
}
NODE

BUILD_CHECK_STATUS="not_available"
BUILD_CHECK_OUTPUT="$OUTPUT_DIR/openclaw-plugins-build-check.txt"
if command -v openclaw >/dev/null 2>&1; then
  set +e
  openclaw plugins build --root "$WORK_DIR/patched/package" --entry ./dist/index.js --check >"$BUILD_CHECK_OUTPUT" 2>&1
  build_check_rc=$?
  set -e
  if [[ "$build_check_rc" -eq 0 ]]; then
    BUILD_CHECK_STATUS="passed"
  elif grep -q 'does not expose defineToolPlugin metadata' "$BUILD_CHECK_OUTPUT"; then
    BUILD_CHECK_STATUS="legacy_dynamic_plugin_shape"
  else
    cat "$BUILD_CHECK_OUTPUT" >&2
    fail "OpenClaw plugin build check failed unexpectedly."
  fi
fi

log "Packing patched package"
PACK_DIR="$OUTPUT_DIR/pack"
rm -rf "$PACK_DIR"
mkdir -p "$PACK_DIR"
npm pack "$WORK_DIR/patched/package" --pack-destination "$PACK_DIR" > "$WORK_DIR/patched-pack.out"
PATCHED_NAME="$(tail -n1 "$WORK_DIR/patched-pack.out")"
[[ -f "$PACK_DIR/$PATCHED_NAME" ]] || fail "patched npm pack did not create expected tarball."
PATCHED_TARBALL="$OUTPUT_DIR/${PATCHED_NAME%.tgz}-${COMPAT_REVISION}.tgz"
mv "$PACK_DIR/$PATCHED_NAME" "$PATCHED_TARBALL"
rmdir "$PACK_DIR"
PATCHED_SHA256="$(sha256sum "$PATCHED_TARBALL" | awk '{print $1}')"

BUILD_MANIFEST="$OUTPUT_DIR/devclaw-compat-build-manifest.json"
jq -n \
  --arg packageName "$EXPECTED_PACKAGE" \
  --arg packageVersion "$EXPECTED_VERSION" \
  --arg compatRevision "$COMPAT_REVISION" \
  --arg npmIntegrity "$EXPECTED_INTEGRITY" \
  --arg upstreamSha256 "$UPSTREAM_SHA256" \
  --arg patchedTarball "$PATCHED_TARBALL" \
  --arg patchedSha256 "$PATCHED_SHA256" \
  --arg buildCheckStatus "$BUILD_CHECK_STATUS" \
  --argjson toolCount "$EXPECTED_TOOL_COUNT" \
  --argjson jsonResultImportCount "$EXPECTED_JSON_RESULT_IMPORT_COUNT" \
  --arg researchTaskQueuePatch "workflow-aware-architect-queue" \
  --arg researchTaskExistingIssuePatch "existing-issue-dispatch" \
  --arg subagentParamsPatch "omit-unsupported-spawnedBy" \
  '{
    packageName: $packageName,
    packageVersion: $packageVersion,
    compatRevision: $compatRevision,
    npmIntegrity: $npmIntegrity,
    upstreamTarballSha256: $upstreamSha256,
    patchedTarball: $patchedTarball,
    patchedTarballSha256: $patchedSha256,
    toolCount: $toolCount,
    jsonResultImportCount: $jsonResultImportCount,
    researchTaskQueuePatch: $researchTaskQueuePatch,
    researchTaskExistingIssuePatch: $researchTaskExistingIssuePatch,
    subagentParamsPatch: $subagentParamsPatch,
    openclawPluginsBuildCheck: $buildCheckStatus
  }' > "$BUILD_MANIFEST"

log "Patched tarball: $PATCHED_TARBALL"
log "Patched tarball SHA-256: $PATCHED_SHA256"
log "Build manifest: $BUILD_MANIFEST"
