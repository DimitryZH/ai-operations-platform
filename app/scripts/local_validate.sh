#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-ai-agent-runtime:local}"
CONTAINER_NAME="${CONTAINER_NAME:-ai-agent-runtime-local}"
HOST_PORT="${HOST_PORT:-8080}"
CONTAINER_PORT="${CONTAINER_PORT:-8080}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cleanup() {
  if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
  echo "[FAIL] docker is not installed or not in PATH."
  exit 1
fi

http_get() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS "${url}"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO- "${url}"
    return 0
  fi

  echo "[FAIL] neither curl nor wget is available for health checks."
  return 1
}

echo "[INFO] Building local runtime image: ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" "${RUNTIME_DIR}"

echo "[INFO] Starting container: ${CONTAINER_NAME}"
docker run -d \
  --name "${CONTAINER_NAME}" \
  -e PORT="${CONTAINER_PORT}" \
  -p "${HOST_PORT}:${CONTAINER_PORT}" \
  "${IMAGE_TAG}" >/dev/null

health_url="http://127.0.0.1:${HOST_PORT}/health"
echo "[INFO] Waiting for health endpoint: ${health_url}"

for attempt in $(seq 1 20); do
  if health_response="$(http_get "${health_url}" 2>/dev/null)"; then
    echo "[PASS] Health check succeeded on attempt ${attempt}."
    echo "${health_response}"
    echo
    exit 0
  fi
  sleep 1
done

echo "[FAIL] Health check did not succeed within timeout."
echo "[INFO] Container logs:"
docker logs "${CONTAINER_NAME}" || true
exit 1
