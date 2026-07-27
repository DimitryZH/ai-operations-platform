# Issue 8 DevClaw Recovery Workflow

Reusable operator scripts for recovering Experiment 07A after the developer completed local implementation but could not publish the branch/PR.

Target repository: `DimitryZH/application-modernization-lab`

Agent DevBox checkout: `/workspace/repos/application-modernization-lab`

Branch: `issue-8-bank-of-anthos-compose`

Expected local commit: `cdffffd0703f13bad9d873ca3ed60e2f1ec9ba04`

## Scripts

- `publish-issue-8-branch-and-create-draft-pr.sh`
  - Verifies the local branch and commit trailer.
  - Pushes the branch using the existing GitHub App token broker.
  - Creates or reports the draft PR.
  - Writes `publish-result.json` next to the remote script.

- `dispatch-issue-8-independent-tester.sh`
  - Reads `publish-result.json`.
  - Dispatches one fresh senior tester session.
  - Moves the issue to `Validating`.
  - Records the tester worker state.

- `check-issue-8-tester-status.sh`
  - Reads DevClaw worker and session state.
  - Prints latest tester completion evidence from the runtime audit.

- `request-issue-8-tester-pr-comment.sh`
  - Sends one follow-up turn to the completed senior tester session.
  - Asks the tester to publish a standalone validation result comment on PR #9.
  - Performs one bounded check for the resulting PR comment.

- `request-issue-8-tester-corrective-commit.sh`
  - Verifies the human review correction comment exists on PR #9.
  - Moves issue #8 back to a correction/refining state with existing labels.
  - Sends one follow-up turn asking the senior tester to make only the approved corrective commit, rerun fresh-volume validation, push, and report the new commit.

Tokens are kept in process memory only. The scripts do not print or persist GitHub tokens.
