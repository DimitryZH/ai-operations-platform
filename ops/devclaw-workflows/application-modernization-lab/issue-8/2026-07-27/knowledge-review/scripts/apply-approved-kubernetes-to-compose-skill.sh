#!/usr/bin/env bash
set -euo pipefail

proposal_id="${1:-kubernetes-to-compose-migration-20260727-ddcee90daa}"
state_dir="${OPENCLAW_HOME:-/home/devclaw-svc/.openclaw}"
workflow_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_file="${2:-${workflow_dir}/evidence/apply-approved-result.json}"

mkdir -p "$(dirname "$out_file")"

node - "$state_dir" "$proposal_id" "$out_file" <<'NODE'
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const stateDir = process.argv[2];
const proposalId = process.argv[3];
const outFile = process.argv[4];

const now = new Date().toISOString();
const proposalDir = path.join(stateDir, "skill-workshop", "proposals", proposalId);
const proposalFile = path.join(proposalDir, "proposal.json");
const manifestFile = path.join(stateDir, "skill-workshop", "proposals.json");

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function writeJson(file, value) {
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function sha256(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

function materializeSkillMarkdown(markdown, proposal) {
  const body = markdown.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, "");
  const name = proposal.target?.skillName ?? proposal.name;
  const description = proposal.description ?? "";
  return `---\nname: ${JSON.stringify(name)}\ndescription: ${JSON.stringify(description)}\n---\n\n${body.replace(/^\s+/, "")}`;
}

const proposal = readJson(proposalFile);
if (proposal.id !== proposalId) throw new Error(`proposal id mismatch: ${proposal.id}`);
if (proposal.kind !== "create") throw new Error(`unsupported proposal kind: ${proposal.kind}`);
if (proposal.status !== "pending") throw new Error(`proposal status is ${proposal.status}, expected pending`);
if (proposal.scan?.state !== "clean") throw new Error(`scanner state is ${proposal.scan?.state}, expected clean`);
if (proposal.scan?.critical !== 0) throw new Error(`scanner critical findings: ${proposal.scan?.critical}`);

const draftFile = path.join(proposalDir, proposal.draftFile ?? "PROPOSAL.md");
if (!fs.existsSync(draftFile)) throw new Error(`missing draft file: ${draftFile}`);
const draftHash = sha256(draftFile);
if (proposal.draftHash && proposal.draftHash !== draftHash) {
  throw new Error(`draft hash mismatch: ${draftHash}`);
}

for (const support of proposal.supportFiles ?? []) {
  const supportFile = path.join(proposalDir, support.path);
  if (!fs.existsSync(supportFile)) throw new Error(`missing support file: ${support.path}`);
  const supportHash = sha256(supportFile);
  if (support.hash && support.hash !== supportHash) {
    throw new Error(`support hash mismatch for ${support.path}: ${supportHash}`);
  }
}

const target = proposal.target ?? {};
const skillDir = target.skillDir;
const skillFile = target.skillFile;
if (!skillDir || !skillFile) throw new Error("proposal target skillDir/skillFile is missing");
if (fs.existsSync(skillDir)) throw new Error(`target skill directory already exists: ${skillDir}`);

const tmpDir = `${skillDir}.tmp-${Date.now()}`;
fs.mkdirSync(tmpDir, { recursive: true });

const sourceMarkdown = fs.readFileSync(draftFile, "utf8");
fs.writeFileSync(path.join(tmpDir, "SKILL.md"), materializeSkillMarkdown(sourceMarkdown, proposal), "utf8");

for (const support of proposal.supportFiles ?? []) {
  const src = path.join(proposalDir, support.path);
  const dest = path.join(tmpDir, support.path);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

fs.renameSync(tmpDir, skillDir);

proposal.status = "applied";
proposal.appliedAt = now;
proposal.updatedAt = now;
writeJson(proposalFile, proposal);

const rollbackFile = path.join(proposalDir, "rollback.json");
if (!fs.existsSync(rollbackFile)) writeJson(rollbackFile, {});

const manifest = readJson(manifestFile);
manifest.updatedAt = now;
for (const item of manifest.proposals ?? []) {
  if (item.id === proposalId) {
    item.status = "applied";
    item.updatedAt = now;
    item.scanState = proposal.scan?.state ?? item.scanState;
  }
}
writeJson(manifestFile, manifest);

const writtenFiles = [];
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else writtenFiles.push(path.relative(skillDir, full).replaceAll(path.sep, "/"));
  }
}
walk(skillDir);
writtenFiles.sort();

const result = {
  appliedAt: now,
  proposalId,
  proposalStatus: proposal.status,
  proposedVersion: proposal.proposedVersion,
  scannerState: proposal.scan?.state,
  target: {
    skillName: target.skillName,
    skillDir,
    skillFile,
  },
  writtenFiles,
  activeSkillHash: sha256(skillFile),
  supportFiles: proposal.supportFiles ?? [],
};

writeJson(outFile, result);
console.log(JSON.stringify(result, null, 2));
NODE
