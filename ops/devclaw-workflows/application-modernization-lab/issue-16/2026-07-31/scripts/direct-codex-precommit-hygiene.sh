#!/usr/bin/env bash
set -euo pipefail

repo="/workspace/repos/application-modernization-lab"
cd "${repo}"

echo "---status---"
git status --short
echo "---diffstat---"
git diff --stat
echo "---diffcheck---"
git diff --check
echo "---tracked-local---"
git ls-files experiments/08-aks-store-demo/02-compose-to-aspire/.local || true
echo "---modes---"
find experiments/08-aks-store-demo/02-compose-to-aspire/scripts -maxdepth 1 -type f -printf '%M %m %p\n' | sort
