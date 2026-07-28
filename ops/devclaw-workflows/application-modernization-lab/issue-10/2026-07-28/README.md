# Issue 10 DevClaw Workflow Operation Scripts

Historical operator scripts for Experiment 07B in
`DimitryZH/application-modernization-lab`.

These scripts were created for issue #10 and PR #11 only. They capture the
bounded DevClaw operator actions used during the Bank of Anthos
Compose-to-Aspire migration workflow on 2026-07-28.

Do not rerun these scripts blindly. They encode issue-specific labels, branches,
commits, worker sessions, paths, and approval assumptions from the completed
Experiment 07B workflow.

## Target Context

- Repository: `DimitryZH/application-modernization-lab`
- Agent DevBox checkout: `/workspace/repos/application-modernization-lab`
- Issue: `#10`
- Pull request: `#11`
- Implementation branch: `issue-10-bank-of-anthos-aspire`
- Approved baseline: `3de8845412853525aeb77d85db23f2d14b1bfc73`
- Implementation commit: `8649b3be4bc63db80a1e185f42a0dbd5d0c21aa1`
- Merge commit: `5976290742724acfef15766b53dba39f7a8484e9`
- Active skill checked by the scripts:
  `/home/devclaw-svc/.openclaw/workspace/skills/compose-to-aspire-migration/SKILL.md`

## Scripts

- `dispatch-issue-10-architect.sh`
  Starts the issue #10 senior architect workflow after confirming `main` is at
  the approved baseline, the checkout is clean, worker slots are idle, and
  DevClaw guardrails remain sequential with heartbeat, auto-merge, and
  autonomous Skill Workshop disabled.

- `dispatch-issue-10-developer.sh`
  Starts the fresh senior developer workflow after human architecture approval.
  It requires issue #10 to be in `Implementation`, checks for idle workers and a
  clean synchronized `main`, then asks the developer to report fresh
  `compose-to-aspire-migration` skill usage before implementation.

- `inspect-issue-10-developer-status.sh`
  Read-only status snapshot for the developer stage. It reports issue labels,
  developer worker state, open PRs, local branch/head/status, and recent issue
  comments.

- `dispatch-issue-10-tester.sh`
  Starts the fresh senior tester workflow for PR #11 after human approval to
  enter validation. It checks issue #10, PR #11, idle workers, a clean
  implementation branch, and runtime guardrails before dispatching the tester.

- `inspect-issue-10-tester-status.sh`
  Read-only status snapshot for the tester stage. It reports issue labels, PR
  state, tester worker/session state, local branch/head/status, and recent issue
  comments.

## Worker And Session Assumptions

- Architect: `agent:main:subagent:application-modernization-lab-architect-senior-zandra`
- Developer: `agent:main:subagent:application-modernization-lab-developer-senior-ara`
- Tester: `agent:main:subagent:application-modernization-lab-tester-senior-sukey`
- DevClaw project: `application-modernization-lab`
- Channel: `openclaw-control-ui-main`

The dispatch scripts intentionally use fixed issue, PR, branch, session, and
label values from this completed workflow. They should be treated as audit and
recovery artifacts, not generic automation.

## Token Handling

GitHub tokens are obtained only from the local Agent DevBox token broker:

`/run/devclaw/github-token-broker.sock`

The scripts keep tokens in process variables only. They do not print tokens and
do not persist tokens to result files or repository files.

## Safe-Use Limitations

- Run only on the controlled Agent DevBox as root, where `runuser`,
  `/usr/local/bin/openclaw`, the GitHub token broker, and the registered DevClaw
  workspace exist.
- Do not use these scripts for new issues without reviewing and updating every
  issue-specific value.
- Do not run a dispatch script if any worker is already active.
- Do not run a dispatch script after the corresponding workflow stage has
  already completed.
- These scripts do not merge PRs, close issues, modify active skills, start
  Skill Workshop, enable heartbeat, enable parallel execution, or enable
  automatic merge.

Generated dispatch/status result files are ignored by the local `.gitignore`.
