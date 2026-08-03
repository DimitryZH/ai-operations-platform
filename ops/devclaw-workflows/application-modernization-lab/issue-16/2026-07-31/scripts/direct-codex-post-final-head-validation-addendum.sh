#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
issue_id="16"
final_head="bdad00156bd9d6035dc400d56b9a5d39fd39d0e7"

token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r '.token // empty'
)"
[[ -n "${token}" ]] || { echo "missing GitHub token" >&2; exit 1; }

body="$(cat <<EOF_BODY
## Final Head Validation Addendum

After publishing final PR head \`${final_head}\`, Codex reran the complete direct validation contract on the clean committed branch head.

Result: PASS.

Validated on final head:

- clean positive validation;
- RabbitMQ negative validation and fresh-order recovery;
- cleanup isolation;
- adversarial ownership guardrails;
- intentional failure recovery and cleanup;
- second fresh clean positive validation;
- Experiment 08A integrity;
- Git hygiene, executable modes, and secret scan;
- ports \`8080\`, \`8081\`, and \`18888\` released after cleanup checkpoints;
- no remaining Experiment 08B DCP-labeled containers.

No OpenClaw/DevClaw worker or subagent was used. PR #17 remains draft. This addendum does not approve merge or close issue #16.
EOF_BODY
)"

payload="$(jq -nc --arg body "${body}" '{body:$body}')"
tmp="$(mktemp)"
printf '%s' "${payload}" > "${tmp}"
curl --silent --show-error --fail-with-body -X POST --data-binary @"${tmp}" -K - <<EOF_CURL
url = "https://api.github.com/repos/${repo_full}/issues/${issue_id}/comments"
header = "Authorization: Bearer ${token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF_CURL
rm -f "${tmp}"
