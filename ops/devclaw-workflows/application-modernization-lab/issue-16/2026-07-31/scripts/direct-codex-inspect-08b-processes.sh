#!/usr/bin/env bash
set -euo pipefail

exp_dir="/workspace/repos/application-modernization-lab/experiments/08-aks-store-demo/02-compose-to-aspire"
pid_file="${exp_dir}/.local/run/apphost.pid"

echo "---pid-file---"
if [[ -f "${pid_file}" ]]; then
  pid="$(cat "${pid_file}")"
  echo "${pid}"
  echo "---pid-alive---"
  kill -0 "${pid}" >/dev/null 2>&1 && echo "alive" || echo "not-alive"
  echo "---process-tree---"
  ps -f --forest -p "${pid}" --ppid "${pid}" || true
else
  echo "missing"
fi

echo "---matching-processes---"
pgrep -a -u "$(id -u)" -f 'dcp|AksStore|dotnet|aspire' || true

echo "---docker-version---"
docker version || true

echo "---docker-containers---"
docker ps -a || true

echo "---aspire-temp---"
find /tmp -maxdepth 2 -type f \( -path '/tmp/aspire-*/*' -o -path '/tmp/*dcp*/*' \) -print 2>/dev/null | head -200 || true
