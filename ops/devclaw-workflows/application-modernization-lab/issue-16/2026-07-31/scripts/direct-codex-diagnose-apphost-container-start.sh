#!/usr/bin/env bash
set -euo pipefail

exp_dir="/workspace/repos/application-modernization-lab/experiments/08-aks-store-demo/02-compose-to-aspire"
apphost_dll="${exp_dir}/src/AppHost/bin/Debug/net10.0/AksStore.AppHost.dll"
out_dir="${exp_dir}/.local/validation/apphost-container-diagnosis-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "${out_dir}"

cd "${exp_dir}"
dotnet build src/AppHost/AksStore.AppHost.csproj >"${out_dir}/build.out" 2>&1

ASPNETCORE_URLS="http://127.0.0.1:18888" \
ASPIRE_ALLOW_UNSECURED_TRANSPORT="true" \
DOTNET_ENVIRONMENT="Development" \
dotnet "${apphost_dll}" >"${out_dir}/apphost.log" 2>"${out_dir}/apphost.err.log" </dev/null &
pid=$!
echo "${pid}" > "${out_dir}/apphost.pid"

cleanup() {
  kill "${pid}" >/dev/null 2>&1 || true
  sleep 3
  kill -9 "${pid}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for s in 5 15 30 60 120; do
  sleep "${s}"
  {
    echo "--- after ${s}s ---"
    kill -0 "${pid}" >/dev/null 2>&1 && echo "apphost alive" || echo "apphost not alive"
    docker ps -a --format '{{.ID}} {{.Names}} {{.Status}}'
    for id in $(docker ps -aq); do
      name="$(docker inspect -f '{{ index .Config.Labels "com.microsoft.developer.usvc-dev.name" }}' "${id}" 2>/dev/null || true)"
      [[ -n "${name}" && "${name}" != "<no value>" ]] || continue
      pid_label="$(docker inspect -f '{{ index .Config.Labels "com.microsoft.developer.usvc-dev.creatorProcessId" }}' "${id}" 2>/dev/null || true)"
      start_label="$(docker inspect -f '{{ index .Config.Labels "com.microsoft.developer.usvc-dev.creatorProcessStartTime" }}' "${id}" 2>/dev/null || true)"
      group="$(docker inspect -f '{{ index .Config.Labels "com.microsoft.developer.usvc-dev.group-version" }}' "${id}" 2>/dev/null || true)"
      printf 'ID=%s NAME=%s PID=%s START=%s GROUP=%s\n' "${id}" "${name}" "${pid_label}" "${start_label}" "${group}"
    done
  } >> "${out_dir}/docker-samples.out"
done

echo "${out_dir}"
