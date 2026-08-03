#!/usr/bin/env bash
set -euo pipefail

repo="/workspace/repos/application-modernization-lab"
cd "${repo}"

git add \
  experiments/08-aks-store-demo/02-compose-to-aspire/README.md \
  experiments/08-aks-store-demo/02-compose-to-aspire/docs/developer-validation.md \
  experiments/08-aks-store-demo/02-compose-to-aspire/docs/validation-plan.md \
  experiments/08-aks-store-demo/02-compose-to-aspire/scripts/validate-ownership-guardrails.sh

git diff --cached --stat
git commit -m "test(08b): add Aspire ownership guardrails"
git rev-parse HEAD
