#!/usr/bin/env bash
set -euo pipefail

repo="/workspace/repos/application-modernization-lab"
branch_expected="experiment-08/aks-store-aspire-migration"
head_expected="6722ff491c2a9053a9f76b4bb9223b64f3ec6b3b"
root="/tmp/direct-codex-workflows/application-modernization-lab/issue-16/pr17"
out_dir="${1:-${root}/preserve-$(date -u +%Y%m%dT%H%M%SZ)}"

fail() {
  printf '[direct-codex-preserve-issue-16-pr17-worktree] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -d "${repo}/.git" ]] || fail "missing repository checkout: ${repo}"
command -v git >/dev/null 2>&1 || fail "missing git"
command -v tar >/dev/null 2>&1 || fail "missing tar"

mkdir -p "${out_dir}/metadata" "${out_dir}/untracked-files"

ps -eo pid,ppid,user,stat,comm,args ww |
  awk '$5 ~ /^(codex|openclaw|node|npm|bash)$/ && $0 ~ /(subagent|application-modernization-lab|openclaw|codex)/ { print }' \
  > "${out_dir}/worker-process-scan.txt" || true

git_repo() {
  git -c "safe.directory=${repo}" -C "${repo}" "$@"
}

branch="$(git_repo branch --show-current)"
head="$(git_repo rev-parse HEAD)"
head_tree="$(git_repo rev-parse 'HEAD^{tree}')"

[[ "${branch}" == "${branch_expected}" ]] || fail "expected branch ${branch_expected}, found ${branch}"
[[ "${head}" == "${head_expected}" ]] || fail "expected HEAD ${head_expected}, found ${head}"

git_repo status --short > "${out_dir}/git-status-short.txt"
git_repo status --short --branch > "${out_dir}/git-status-short-branch.txt"
git_repo diff --no-ext-diff > "${out_dir}/git-diff.patch"
git_repo diff --no-ext-diff --binary > "${out_dir}/git-diff-binary.patch"
git_repo diff --no-ext-diff --cached --binary > "${out_dir}/git-diff-cached-binary.patch"
git_repo diff --no-ext-diff --binary HEAD -- > "${out_dir}/git-diff-head-binary.patch"
git_repo ls-files --others --exclude-standard > "${out_dir}/untracked-files.txt"
git_repo ls-files --others --exclude-standard -z > "${out_dir}/untracked-files.z"
git_repo status --porcelain=v1 -z > "${out_dir}/git-status-porcelain-v1.z"

if [[ -s "${out_dir}/untracked-files.z" ]]; then
  tar -C "${repo}" --null -T "${out_dir}/untracked-files.z" -cf "${out_dir}/untracked-files.tar"
  tar -C "${out_dir}/untracked-files" -xf "${out_dir}/untracked-files.tar"
fi

find "${repo}/experiments/08-aks-store-demo/02-compose-to-aspire" \
  -type f \( -name '*.sh' -o -name '*.ps1' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.cmd' -o -name '*.bat' \) \
  -printf '%M %m %u:%g %p\n' \
  > "${out_dir}/file-modes.txt" 2>/dev/null || true

{
  printf 'capturedAt=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'branch=%s\n' "${branch}"
  printf 'head=%s\n' "${head}"
  printf 'headTree=%s\n' "${head_tree}"
  printf 'repo=%s\n' "${repo}"
} > "${out_dir}/metadata/branch-head.txt"

jq -n \
  --arg capturedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg outDir "${out_dir}" \
  --arg branch "${branch}" \
  --arg head "${head}" \
  --arg expectedHead "${head_expected}" \
  --arg workerProcessScan "$(cat "${out_dir}/worker-process-scan.txt")" \
  '{
    capturedAt:$capturedAt,
    outDir:$outDir,
    repository:{branch:$branch, head:$head, expectedHead:$expectedHead},
    workerProcessScan:$workerProcessScan,
    artifacts:{
      statusShort:"git-status-short.txt",
      completeDiff:"git-diff.patch",
      binaryDiff:"git-diff-binary.patch",
      untrackedList:"untracked-files.txt",
      untrackedArchive:"untracked-files.tar",
      fileModes:"file-modes.txt"
    }
  }' | tee "${out_dir}/preserve-summary.json"

printf '%s\n' "${out_dir}" > "${root}/latest-preserve-dir.txt"
