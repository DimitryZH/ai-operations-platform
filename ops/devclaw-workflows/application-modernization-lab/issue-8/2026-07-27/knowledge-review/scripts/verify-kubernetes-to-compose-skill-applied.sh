#!/usr/bin/env bash
set -euo pipefail

proposal_id="kubernetes-to-compose-migration-20260727-ddcee90daa"
skill_name="kubernetes-to-compose-migration"
state_dir="/home/devclaw-svc/.openclaw"
proposal_dir="${state_dir}/skill-workshop/proposals/${proposal_id}"
skill_dir="${state_dir}/workspace/skills/${skill_name}"
out_file="${1:-./evidence/applied-verification-result.json}"

mkdir -p "$(dirname "${out_file}")"

proposal_json="${proposal_dir}/proposal.json"
skill_file="${skill_dir}/SKILL.md"

if [[ ! -f "${proposal_json}" ]]; then
  echo "missing proposal metadata: ${proposal_json}" >&2
  exit 1
fi

if [[ ! -f "${skill_file}" ]]; then
  echo "missing active skill file: ${skill_file}" >&2
  exit 1
fi

proposal_status="$(jq -r '.status' "${proposal_json}")"
scan_state="$(jq -r '.scan.state' "${proposal_json}")"
applied_version="$(jq -r '.appliedVersion // .proposedVersion // empty' "${proposal_json}")"
updated_at="$(jq -r '.updatedAt' "${proposal_json}")"

[[ "${proposal_status}" == "applied" ]] || {
  echo "proposal status is ${proposal_status}, expected applied" >&2
  exit 1
}

[[ "${scan_state}" == "clean" ]] || {
  echo "proposal scan state is ${scan_state}, expected clean" >&2
  exit 1
}

generated_files="$(
  find "${skill_dir}" -maxdepth 2 -type f -printf '%P\n' | sort | jq -R . | jq -s .
)"

jq -nc \
  --arg verifiedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg proposalId "${proposal_id}" \
  --arg proposalStatus "${proposal_status}" \
  --arg skillName "${skill_name}" \
  --arg skillFile "${skill_file}" \
  --arg appliedVersion "${applied_version}" \
  --arg updatedAt "${updated_at}" \
  --arg scanState "${scan_state}" \
  --argjson proposal "$(jq -c '.' "${proposal_json}")" \
  --argjson generatedFiles "${generated_files}" \
  '{
    verifiedAt:$verifiedAt,
    proposalId:$proposalId,
    proposalStatus:$proposalStatus,
    skillName:$skillName,
    skillFile:$skillFile,
    appliedVersion:$appliedVersion,
    updatedAt:$updatedAt,
    scannerResult:{state:$scanState},
    activeSkillExists:true,
    generatedFiles:$generatedFiles,
    proposal:$proposal
  }' | tee "${out_file}"
