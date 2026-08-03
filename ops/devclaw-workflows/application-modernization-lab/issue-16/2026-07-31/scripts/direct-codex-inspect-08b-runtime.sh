#!/usr/bin/env bash
set -euo pipefail

exp_dir="/workspace/repos/application-modernization-lab/experiments/08-aks-store-demo/02-compose-to-aspire"
cd "${exp_dir}"

echo "---runfiles---"
find .local -maxdepth 3 -type f -print 2>/dev/null | sort || true
echo "---apphost-log-tail---"
tail -80 .local/run/apphost.log 2>/dev/null || true
echo "---apphost-err-tail---"
tail -80 .local/run/apphost.err.log 2>/dev/null || true
echo "---containers---"
docker ps -a --format '{{.ID}} {{.Names}} {{.Status}}'
echo "---dcp-labels---"
for id in $(docker ps -aq); do
  name="$(docker inspect -f '{{ index .Config.Labels "com.microsoft.developer.usvc-dev.name" }}' "${id}" 2>/dev/null || true)"
  [[ -n "${name}" && "${name}" != "<no value>" ]] || continue
  pid="$(docker inspect -f '{{ index .Config.Labels "com.microsoft.developer.usvc-dev.creatorProcessId" }}' "${id}" 2>/dev/null || true)"
  start="$(docker inspect -f '{{ index .Config.Labels "com.microsoft.developer.usvc-dev.creatorProcessStartTime" }}' "${id}" 2>/dev/null || true)"
  group="$(docker inspect -f '{{ index .Config.Labels "com.microsoft.developer.usvc-dev.group-version" }}' "${id}" 2>/dev/null || true)"
  printf 'ID=%s NAME=%s PID=%s START=%s GROUP=%s\n' "${id}" "${name}" "${pid}" "${start}" "${group}"
done
