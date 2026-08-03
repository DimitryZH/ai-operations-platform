#!/usr/bin/env bash
set -euo pipefail

repo="/workspace/repos/application-modernization-lab"
branch_expected="experiment-08/aks-store-aspire-migration"
exp_dir="${repo}/experiments/08-aks-store-demo/02-compose-to-aspire"
baseline_dir="${repo}/experiments/08-aks-store-demo/01-compose-baseline"
validation_dir="${exp_dir}/.local/validation"
summary="${validation_dir}/direct-codex-validation-summary.md"
ts="$(date -u +%Y%m%dT%H%M%SZ)"

log() { printf '[direct-codex-validation] %s\n' "$*"; }
fail() { printf '[direct-codex-validation] ERROR: %s\n' "$*" >&2; exit 1; }

git_repo() {
  git -C "${repo}" "$@"
}

mkdir -p "${validation_dir}"
{
  printf '# Direct Codex Validation Summary\n\n'
  printf 'Generated: %s UTC\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${summary}"

record() {
  printf -- '- %s\n' "$*" | tee -a "${summary}" >/dev/null
}

run_step() {
  local name="$1"
  shift
  log "START ${name}"
  if "$@" >"${validation_dir}/${name}.${ts}.out" 2>&1; then
    record "PASS: ${name}"
    log "PASS ${name}"
  else
    local status=$?
    record "FAIL: ${name} (exit ${status}); see .local/validation/${name}.${ts}.out"
    log "FAIL ${name}"
    tail -n 120 "${validation_dir}/${name}.${ts}.out" >&2 || true
    exit "${status}"
  fi
}

clean_stale_runtime_files() {
  local run_dir="${exp_dir}/.local/run" pid_file="${exp_dir}/.local/run/apphost.pid" pid
  if [[ -f "${pid_file}" ]]; then
    pid="$(cat "${pid_file}")"
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      mv "${run_dir}" "${validation_dir}/stale-run-${ts}"
      record "Moved stale ignored runtime state to .local/validation/stale-run-${ts}."
    fi
  fi
}

assert_ports_clear() {
  if ss -ltnp 2>/dev/null | grep -E ':(8080|8081|18888)\b'; then
    fail "ports 8080, 8081, or 18888 are still listening"
  fi
}

assert_no_owned_08b_containers() {
  local ids
  ids="$(
    docker ps -aq \
      --filter 'label=com.microsoft.developer.usvc-dev.group-version=usvc-dev.developer.microsoft.com/v1' |
      while read -r id; do
        [[ -n "${id}" ]] || continue
        name="$(docker inspect -f '{{ index .Config.Labels "com.microsoft.developer.usvc-dev.name" }}' "${id}" 2>/dev/null || true)"
        [[ "${name}" =~ ^(documentdb|rabbitmq|order-service|makeline-service|product-service|store-front|store-admin|virtual-customer|virtual-worker|ai-service)-[a-z0-9]+$ ]] && printf '%s %s\n' "${id}" "${name}"
      done
  )"
  [[ -z "${ids}" ]] || fail "Experiment 08B DCP-labeled containers remain: ${ids}"
}

assert_script_modes() {
  find "${exp_dir}/scripts" -maxdepth 1 -type f -name '*.sh' -printf '%m %p\n' |
    tee "${validation_dir}/script-modes-${ts}.txt" |
    awk '$1 !~ /^[0-7]*[1357][0-7]*$/ { bad=1; print "not executable: "$0 > "/dev/stderr" } END { exit bad ? 1 : 0 }'
}

assert_no_secrets() {
  if git_repo grep -nE '(AKIA[0-9A-Z]{16}|AZURE_OPENAI_API_KEY=.+|password: .+|client_secret|PRIVATE KEY)' -- \
      'experiments/08-aks-store-demo/02-compose-to-aspire' \
      ':!experiments/08-aks-store-demo/02-compose-to-aspire/docs/developer-validation.md'; then
    fail "potential secret pattern found"
  fi
}

cd "${repo}"
[[ "$(git_repo branch --show-current)" == "${branch_expected}" ]] || fail "wrong branch"
record "Branch preflight: $(git_repo branch --show-current), HEAD $(git_repo rev-parse HEAD)."

clean_stale_runtime_files

run_step "version-source-build" bash -lc "cd '${exp_dir}' && test \"\$(dotnet --version)\" = '10.0.110' && grep -Fq 'Sdk=\"Aspire.AppHost.Sdk/13.4.6\"' src/AppHost/AksStore.AppHost.csproj && cd '${baseline_dir}' && sha256sum -c upstream-source.sha256 && cd '${exp_dir}' && dotnet build src/AppHost/AksStore.AppHost.csproj"
run_step "positive-clean" "${exp_dir}/scripts/validate-aspire.sh" --start-apphost
assert_ports_clear
assert_no_owned_08b_containers
run_step "negative-rabbitmq-recovery" "${exp_dir}/scripts/validate-negative.sh"
assert_ports_clear
assert_no_owned_08b_containers
run_step "cleanup-isolation" bash "${exp_dir}/scripts/validate-cleanup-isolation.sh"
assert_ports_clear
assert_no_owned_08b_containers
run_step "ownership-guardrails" bash "${exp_dir}/scripts/validate-ownership-guardrails.sh"
assert_ports_clear
assert_no_owned_08b_containers
run_step "intentional-failure-cleanup" bash "${exp_dir}/scripts/validate-failure-cleanup.sh"
assert_ports_clear
assert_no_owned_08b_containers
run_step "positive-second-clean" "${exp_dir}/scripts/validate-aspire.sh" --start-apphost
assert_ports_clear
assert_no_owned_08b_containers
run_step "08a-integrity" bash -lc "cd '${baseline_dir}' && sha256sum -c upstream-source.sha256"
run_step "git-diff-check" git_repo diff --check
run_step "script-mode-check" assert_script_modes
run_step "secret-scan" assert_no_secrets

git_repo status --short > "${validation_dir}/git-status-after-validation-${ts}.txt"
record "Ports 8080, 8081, and 18888 were clear after each cleanup checkpoint."
record "No remaining Experiment 08B DCP-labeled containers after validation."
record "Git status after validation saved to .local/validation/git-status-after-validation-${ts}.txt."
log "validation completed; summary ${summary}"
