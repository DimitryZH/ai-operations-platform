#!/usr/bin/env bash
set -euo pipefail

repo="/workspace/repos/application-modernization-lab"
branch="experiment-08/aks-store-aspire-migration"
expected="406860ff73d7a6387911eff3110d24f2601fda5a"

cd "${repo}"
git fetch origin "${branch}:refs/remotes/origin/${branch}"

current_branch="$(git branch --show-current)"
local_head="$(git rev-parse HEAD)"
remote_head="$(git rev-parse "refs/remotes/origin/${branch}")"
status="$(git status --short)"

printf 'branch=%s\n' "${current_branch}"
printf 'local=%s\n' "${local_head}"
printf 'remote=%s\n' "${remote_head}"
printf 'expected=%s\n' "${expected}"
printf 'status=%s\n' "${status}"

[[ "${current_branch}" == "${branch}" ]] || { echo "wrong branch" >&2; exit 1; }
[[ "${local_head}" == "${expected}" ]] || { echo "local head mismatch" >&2; exit 1; }
[[ "${remote_head}" == "${expected}" ]] || { echo "remote head mismatch" >&2; exit 1; }
[[ -z "${status}" ]] || { echo "worktree is not clean" >&2; exit 1; }
