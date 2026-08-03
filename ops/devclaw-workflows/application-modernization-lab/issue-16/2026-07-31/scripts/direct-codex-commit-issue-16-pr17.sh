#!/usr/bin/env bash
set -euo pipefail

repo="/workspace/repos/application-modernization-lab"
cd "${repo}"

git add \
  experiments/08-aks-store-demo/02-compose-to-aspire/README.md \
  experiments/08-aks-store-demo/02-compose-to-aspire/docs/developer-validation.md \
  experiments/08-aks-store-demo/02-compose-to-aspire/docs/migration-assessment.md \
  experiments/08-aks-store-demo/02-compose-to-aspire/docs/validation-plan.md \
  experiments/08-aks-store-demo/02-compose-to-aspire/scripts/aspire-run-state.sh \
  experiments/08-aks-store-demo/02-compose-to-aspire/scripts/cleanup-aspire.sh \
  experiments/08-aks-store-demo/02-compose-to-aspire/scripts/start-aspire.sh \
  experiments/08-aks-store-demo/02-compose-to-aspire/scripts/validate-aspire.sh \
  experiments/08-aks-store-demo/02-compose-to-aspire/scripts/validate-cleanup-isolation.sh \
  experiments/08-aks-store-demo/02-compose-to-aspire/scripts/validate-failure-cleanup.sh \
  experiments/08-aks-store-demo/02-compose-to-aspire/scripts/validate-negative.sh

git diff --cached --stat
git commit -m "fix(08b): bind Aspire cleanup to owned AppHost identity"
git rev-parse HEAD
