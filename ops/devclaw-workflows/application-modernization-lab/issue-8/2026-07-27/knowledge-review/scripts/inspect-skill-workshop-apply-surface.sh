#!/usr/bin/env bash
set -euo pipefail

BASE="${OPENCLAW_HOME:-/home/devclaw-svc/.openclaw}"
PROPOSAL_ID="${1:-kubernetes-to-compose-migration-20260727-ddcee90daa}"

echo "proposal=$PROPOSAL_ID"
echo "workshop_root=$BASE/skill-workshop"

echo "== proposal metadata =="
if [[ -f "$BASE/skill-workshop/proposals/$PROPOSAL_ID/proposal.json" ]]; then
  node -e '
    const fs = require("fs");
    const p = process.argv[1];
    const data = JSON.parse(fs.readFileSync(p, "utf8"));
    console.log(JSON.stringify({
      id: data.id,
      name: data.name,
      status: data.status,
      proposedVersion: data.proposedVersion,
      updatedAt: data.updatedAt,
      scan: data.scan
    }, null, 2));
  ' "$BASE/skill-workshop/proposals/$PROPOSAL_ID/proposal.json"
else
  echo "missing proposal.json"
fi

echo "== candidate commands =="
find "$BASE" -maxdepth 8 -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" -o -name "*.json" \) \
  2>/dev/null \
  | while read -r file; do
      if grep -Iq . "$file" && grep -Eq "applyProposal|apply proposal|skill_workshop|skill-workshop|Skill Workshop" "$file"; then
        echo "$file"
      fi
    done \
  | sort -u \
  | sed -n '1,80p'

echo "== active skill =="
if [[ -f "$BASE/workspace/skills/kubernetes-to-compose-migration/SKILL.md" ]]; then
  ls -la "$BASE/workspace/skills/kubernetes-to-compose-migration"
else
  echo "active skill not present"
fi
