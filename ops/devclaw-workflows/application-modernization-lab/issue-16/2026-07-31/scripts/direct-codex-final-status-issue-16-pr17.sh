#!/usr/bin/env bash
set -euo pipefail

repo="/workspace/repos/application-modernization-lab"
cd "${repo}"

echo "---branch---"
git branch --show-current
echo "---head---"
git rev-parse HEAD
echo "---status---"
git status --short
echo "---containers---"
docker ps -a --format '{{.ID}} {{.Names}} {{.Status}}'
echo "---tracked-local---"
git ls-files experiments/08-aks-store-demo/02-compose-to-aspire/.local || true
echo "---validation-summary---"
cat experiments/08-aks-store-demo/02-compose-to-aspire/.local/validation/direct-codex-validation-summary.md
