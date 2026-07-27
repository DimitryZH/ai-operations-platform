#!/usr/bin/env bash
set -euo pipefail

repo_url="https://github.com/DimitryZH/ai-operations-platform.git"
branch="chore/experiment-07a-knowledge-review-workflow"
bundle="/home/dimitryzuravleff_gmail_com/ai-ops-experiment-07a-knowledge-review.bundle"
workdir="/tmp/devclaw-workflows/application-modernization-lab/issue-8/2026-07-27/knowledge-review/push-worktree"

if [[ ! -f "${bundle}" ]]; then
  echo "missing bundle: ${bundle}" >&2
  exit 1
fi

mkdir -p "${workdir}"
cd "${workdir}"

if [[ ! -d .git ]]; then
  git init >/dev/null
fi

git remote remove origin >/dev/null 2>&1 || true
git remote add origin "${repo_url}"
git fetch "${bundle}" "${branch}:refs/remotes/bundle/${branch}" >/dev/null
sha="$(git rev-parse "refs/remotes/bundle/${branch}")"

github_token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r '.token // empty'
)"

if [[ -z "${github_token}" || "${github_token}" == "null" ]]; then
  echo "GitHub App broker did not return a token." >&2
  exit 1
fi

askpass="$(mktemp)"
cleanup() {
  rm -f "${askpass}"
}
trap cleanup EXIT

cat > "${askpass}" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "x-access-token" ;;
  *Password*) printf '%s\n' "${GITHUB_TOKEN}" ;;
  *) printf '\n' ;;
esac
EOF
chmod 700 "${askpass}"

GITHUB_TOKEN="${github_token}" GIT_ASKPASS="${askpass}" GIT_TERMINAL_PROMPT=0 \
  git push "${repo_url}" "${sha}:refs/heads/${branch}"

unset github_token

printf 'pushed_sha=%s\n' "${sha}"
