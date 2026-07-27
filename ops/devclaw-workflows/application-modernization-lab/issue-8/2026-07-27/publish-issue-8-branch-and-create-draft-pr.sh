#!/usr/bin/env bash
set -euo pipefail

repo_full="DimitryZH/application-modernization-lab"
repo="/workspace/repos/application-modernization-lab"
branch="issue-8-bank-of-anthos-compose"
expected_commit="cdffffd0703f13bad9d873ca3ed60e2f1ec9ba04"
base_branch="main"
issue_id="8"
result_file="$(dirname "$0")/publish-result.json"
askpass_file="$(dirname "$0")/github-app-askpass.sh"

if [[ ! -d "${repo}/.git" ]]; then
  echo "Repository checkout not found: ${repo}" >&2
  exit 1
fi

current_branch="$(git -C "${repo}" branch --show-current)"
current_head="$(git -C "${repo}" rev-parse HEAD)"
status_short="$(git -C "${repo}" status --short)"

if [[ "${current_branch}" != "${branch}" ]]; then
  echo "Unexpected branch: ${current_branch}; expected ${branch}" >&2
  exit 1
fi

if [[ "${current_head}" != "${expected_commit}" ]]; then
  echo "Unexpected HEAD: ${current_head}; expected ${expected_commit}" >&2
  exit 1
fi

if [[ -n "${status_short}" ]]; then
  echo "Working tree is not clean:" >&2
  printf '%s\n' "${status_short}" >&2
  exit 1
fi

if ! git -C "${repo}" log -1 --pretty=%B | grep -Fxq "Co-authored-by: DmitryZhu <zhdm78@gmail.com>"; then
  echo "Required Co-authored-by trailer is missing from HEAD commit." >&2
  exit 1
fi

github_token="$(
  curl --silent --show-error --fail \
    --unix-socket /run/devclaw/github-token-broker.sock \
    http://localhost/token |
    jq -r '.token // empty'
)"

if [[ -z "${github_token}" ]]; then
  echo "GitHub App broker did not return a token." >&2
  exit 1
fi

cat > "${askpass_file}" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "x-access-token" ;;
  *Password*) printf '%s\n' "${GITHUB_TOKEN}" ;;
  *) printf '\n' ;;
esac
ASKPASS
chmod 700 "${askpass_file}"

GIT_TERMINAL_PROMPT=0 \
GIT_ASKPASS="${askpass_file}" \
GITHUB_TOKEN="${github_token}" \
git -C "${repo}" push "https://github.com/${repo_full}.git" "${branch}:${branch}"

GIT_TERMINAL_PROMPT=0 \
GIT_ASKPASS="${askpass_file}" \
GITHUB_TOKEN="${github_token}" \
git -C "${repo}" -c remote.origin.url="https://github.com/${repo_full}.git" fetch origin "${branch}"

git -C "${repo}" branch --set-upstream-to="origin/${branch}" "${branch}" >/dev/null

api_get() {
  local url="$1"
  curl --silent --show-error --fail-with-body -K - <<EOF
url = "${url}"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF
}

api_post() {
  local url="$1"
  local data="$2"
  local payload_file
  payload_file="$(mktemp)"
  printf '%s' "${data}" > "${payload_file}"
  curl --silent --show-error --fail-with-body -X POST --data-binary @"${payload_file}" -K - <<EOF
url = "${url}"
header = "Authorization: Bearer ${github_token}"
header = "Accept: application/vnd.github+json"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF
  rm -f "${payload_file}"
}

existing_prs="$(api_get "https://api.github.com/repos/${repo_full}/pulls?state=open&head=DimitryZH:${branch}")"
existing_url="$(jq -r '.[0].html_url // empty' <<<"${existing_prs}")"
existing_number="$(jq -r '.[0].number // empty' <<<"${existing_prs}")"

if [[ -n "${existing_url}" ]]; then
  jq -nc \
    --arg branch "${branch}" \
    --arg commit "${current_head}" \
    --arg pr_url "${existing_url}" \
    --arg pr_number "${existing_number}" \
    --arg status "existing" \
    '{status:$status, branch:$branch, commit:$commit, prUrl:$pr_url, prNumber:($pr_number|tonumber)}' |
    tee "${result_file}"
  exit 0
fi

title="feat(experiment-07a): add Bank of Anthos Compose baseline"
body="$(cat <<EOF
## Summary

Adds the Experiment 07A Bank of Anthos Docker Compose baseline from the approved architecture for issue #${issue_id}.

## Validation

Developer reported successful end-to-end validation with:

\`\`\`bash
./scripts/validate-compose.sh
\`\`\`

Validation covered service identity, readiness, frontend login, deposit flow, persistence restart, negative dependency behavior, and cleanup.

## Notes

- Uses pinned upstream commit \`1e40564f9ff572a28281198903e19da93e506770\`.
- No generated JWT keys, credentials, cookies, logs, database dumps, or local evidence should be committed.
- Draft PR is created for independent tester validation before human review.

Refs #${issue_id}
EOF
)"

payload="$(jq -nc \
  --arg title "${title}" \
  --arg head "${branch}" \
  --arg base "${base_branch}" \
  --arg body "${body}" \
  '{title:$title, head:$head, base:$base, body:$body, draft:true}')"

created_pr="$(api_post "https://api.github.com/repos/${repo_full}/pulls" "${payload}")"
pr_url="$(jq -r '.html_url' <<<"${created_pr}")"
pr_number="$(jq -r '.number' <<<"${created_pr}")"

jq -nc \
  --arg branch "${branch}" \
  --arg commit "${current_head}" \
  --arg pr_url "${pr_url}" \
  --arg pr_number "${pr_number}" \
  --arg status "created" \
  '{status:$status, branch:$branch, commit:$commit, prUrl:$pr_url, prNumber:($pr_number|tonumber)}' |
  tee "${result_file}"
