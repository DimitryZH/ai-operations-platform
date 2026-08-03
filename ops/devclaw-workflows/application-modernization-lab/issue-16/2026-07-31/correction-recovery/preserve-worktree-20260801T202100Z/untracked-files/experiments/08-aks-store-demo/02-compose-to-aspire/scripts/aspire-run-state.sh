#!/usr/bin/env bash

EXPECTED_SERVICES=(documentdb rabbitmq order-service makeline-service product-service store-front store-admin virtual-customer virtual-worker)
DCP_GROUP_VERSION="usvc-dev.developer.microsoft.com/v1"
RUN_DIR="${RUN_DIR:-${EXP_DIR}/.local/run}"
PID_FILE="${PID_FILE:-${RUN_DIR}/apphost.pid}"
IDENTITY_FILE="${IDENTITY_FILE:-${RUN_DIR}/apphost-identity.env}"

aspire_state_log() { printf '[aspire-run-state] %s\n' "$*"; }
aspire_state_fail() { printf '[aspire-run-state] ERROR: %s\n' "$*" >&2; exit 1; }

expected_resource_regex() {
  printf '^(documentdb|rabbitmq|order-service|makeline-service|product-service|store-front|store-admin|virtual-customer|virtual-worker|ai-service)-[a-z0-9]+$'
}

dcp_label() {
  local id="$1" label="$2"
  docker inspect -f "{{ index .Config.Labels \"${label}\" }}" "${id}" 2>/dev/null || true
}

container_creator_identity() {
  local id="$1" pid_label start_label
  pid_label="$(dcp_label "${id}" "com.microsoft.developer.usvc-dev.creatorProcessId")"
  start_label="$(dcp_label "${id}" "com.microsoft.developer.usvc-dev.creatorProcessStartTime")"
  [[ -n "${pid_label}" && -n "${start_label}" ]] || return 1
  printf '%s|%s\n' "${pid_label}" "${start_label}"
}

is_experiment08b_dcp_container() {
  local id="$1" name group
  name="$(dcp_label "${id}" "com.microsoft.developer.usvc-dev.name")"
  group="$(dcp_label "${id}" "com.microsoft.developer.usvc-dev.group-version")"
  [[ "${group}" == "${DCP_GROUP_VERSION}" ]] || return 1
  [[ "${name}" =~ $(expected_resource_regex) ]] || return 1
  container_creator_identity "${id}" >/dev/null || return 1
}

capture_apphost_identity() {
  local pid="$1" deadline=$((SECONDS + 180)) matches identities identity_count current creator_pid creator_start
  local unique_identities
  [[ -n "${pid}" ]] || aspire_state_fail "cannot capture AppHost identity without an AppHost PID"
  while true; do
    matches=()
    identities=()
    for id in $(docker ps -q); do
      is_experiment08b_dcp_container "${id}" || continue
      current="$(container_creator_identity "${id}")"
      [[ "${current}" == "${pid}|"* ]] || continue
      matches+=("${id}")
      identities+=("${current}")
    done

    if ((${#matches[@]} > 0)); then
      mapfile -t unique_identities < <(printf '%s\n' "${identities[@]}" | sort -u)
      identity_count="${#unique_identities[@]}"
      if ((identity_count == 1)); then
        mkdir -p "${RUN_DIR}"
        IFS='|' read -r creator_pid creator_start <<<"${unique_identities[0]}"
        {
          printf 'APPHOST_PID=%q\n' "${pid}"
          printf 'DCP_CREATOR_PROCESS_ID=%q\n' "${creator_pid}"
          printf 'DCP_CREATOR_PROCESS_START_TIME=%q\n' "${creator_start}"
          printf 'DCP_CREATOR_IDENTITY=%q\n' "${unique_identities[0]}"
          printf 'CAPTURED_AT_UTC=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } >"${IDENTITY_FILE}"
        return 0
      fi
      aspire_state_fail "ambiguous DCP creator identities for AppHost PID ${pid}: ${unique_identities[*]}"
    fi

    ((SECONDS < deadline)) || aspire_state_fail "timed out waiting for DCP containers owned by AppHost PID ${pid}"
    sleep 3
  done
}

load_verified_apphost_identity() {
  local stored_pid matches id current
  [[ -f "${IDENTITY_FILE}" ]] || aspire_state_fail "missing AppHost identity file ${IDENTITY_FILE}; refusing global Aspire cleanup"
  # shellcheck disable=SC1090
  source "${IDENTITY_FILE}"
  [[ -n "${APPHOST_PID:-}" && -n "${DCP_CREATOR_PROCESS_ID:-}" && -n "${DCP_CREATOR_PROCESS_START_TIME:-}" && -n "${DCP_CREATOR_IDENTITY:-}" ]] || aspire_state_fail "AppHost identity file is incomplete"
  [[ "${APPHOST_PID}" == "${DCP_CREATOR_PROCESS_ID}" ]] || aspire_state_fail "stored AppHost PID does not match DCP creator PID"
  [[ -f "${PID_FILE}" ]] || aspire_state_fail "missing AppHost PID file ${PID_FILE}; refusing to use stale creator identity"
  stored_pid="$(cat "${PID_FILE}")"
  [[ "${stored_pid}" == "${APPHOST_PID}" ]] || aspire_state_fail "PID file ${stored_pid} does not match stored AppHost identity ${APPHOST_PID}"

  matches=()
  for id in $(docker ps -aq); do
    is_experiment08b_dcp_container "${id}" || continue
    current="$(container_creator_identity "${id}")"
    [[ "${current}" == "${DCP_CREATOR_IDENTITY}" ]] || continue
    matches+=("${id}")
  done
  ((${#matches[@]} > 0)) || aspire_state_fail "no containers verify stored AppHost identity ${DCP_CREATOR_IDENTITY}; refusing stale cleanup"

  printf '%s\n' "${DCP_CREATOR_IDENTITY}"
}

container_for_identity() {
  local service="$1" creator="$2" include_stopped="${3:-0}" matches=() ids name current
  if [[ "${include_stopped}" == "1" ]]; then
    ids="$(docker ps -aq)"
  else
    ids="$(docker ps -q)"
  fi
  for id in ${ids}; do
    is_experiment08b_dcp_container "${id}" || continue
    name="$(dcp_label "${id}" "com.microsoft.developer.usvc-dev.name")"
    current="$(container_creator_identity "${id}")"
    [[ "${name}" =~ ^${service}-[a-z0-9]+$ ]] || continue
    [[ "${current}" == "${creator}" ]] || continue
    matches+=("${id}"$'\t'"${current}"$'\t'"${name}")
  done
  [[ "${#matches[@]}" -le 1 ]] || aspire_state_fail "multiple containers matched ${service} for stored AppHost identity: ${matches[*]}"
  [[ "${#matches[@]}" -eq 1 ]] || return 1
  printf '%s\n' "${matches[0]}"
}

owned_container_ids() {
  local creator="$1" ids="${2:-all}" id current
  if [[ "${ids}" == "running" ]]; then
    ids="$(docker ps -q)"
  else
    ids="$(docker ps -aq)"
  fi
  for id in ${ids}; do
    is_experiment08b_dcp_container "${id}" || continue
    current="$(container_creator_identity "${id}")"
    [[ "${current}" == "${creator}" ]] || continue
    printf '%s\n' "${id}"
  done
}

unpause_owned_workloads() {
  local creator="$1" id match
  for service in virtual-customer virtual-worker; do
    match="$(container_for_identity "${service}" "${creator}" 1 || true)"
    [[ -n "${match}" ]] || continue
    id="$(printf '%s\n' "${match}" | cut -f1)"
    docker unpause "${id}" >/dev/null 2>&1 || true
  done
}

stop_apphost_pid() {
  local pid="${1:-}"
  [[ -n "${pid}" ]] || return 0
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}" >/dev/null 2>&1 || true
    for _ in {1..30}; do
      kill -0 "${pid}" >/dev/null 2>&1 || return 0
      sleep 1
    done
    kill -9 "${pid}" >/dev/null 2>&1 || true
  fi
}
