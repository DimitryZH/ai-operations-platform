#!/usr/bin/env bash
set -euo pipefail

BASE="${OPENCLAW_HOME:-/home/devclaw-svc/.openclaw}"
APPLIED_ID="${1:-compose-to-aspire-migration-20260721-25daeaebee}"

node - "$BASE" "$APPLIED_ID" <<'NODE'
const fs = require("fs");
const path = require("path");
const base = process.argv[2];
const id = process.argv[3];
const dir = path.join(base, "skill-workshop", "proposals", id);
for (const name of ["proposal.json", "rollback.json"]) {
  const file = path.join(dir, name);
  console.log(`== ${name} ==`);
  if (!fs.existsSync(file)) {
    console.log("missing");
    continue;
  }
  const data = JSON.parse(fs.readFileSync(file, "utf8"));
  const summary = {
    id: data.id,
    name: data.name,
    status: data.status,
    proposedVersion: data.proposedVersion,
    createdAt: data.createdAt,
    updatedAt: data.updatedAt,
    appliedAt: data.appliedAt,
    appliedVersion: data.appliedVersion,
    target: data.target,
    files: data.files,
    previousFiles: data.previousFiles,
    scan: data.scan,
  };
  console.log(JSON.stringify(summary, null, 2));
}
NODE
