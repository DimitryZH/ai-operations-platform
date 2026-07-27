# Experiment 07A Knowledge Review Workflow

## Purpose and Scope

This workflow records the bounded DevClaw Knowledge Review / Skill Workshop operation for completed Experiment 07A in `DimitryZH/application-modernization-lab`.

The operation created, revised, and later applied one Skill Workshop proposal after explicit human approval:

`kubernetes-to-compose-migration`

The active skill snapshot is recorded under `applied-skill/kubernetes-to-compose-migration/`.

## Prerequisites

- `application-modernization-lab` issue #8 is closed as completed.
- PR #9 is merged at merge commit `3de8845412853525aeb77d85db23f2d14b1bfc73`.
- Corrective commit `71d059bf5871d2bc5776a9a26688a3e410f78f62` is included in PR #9.
- Pinned upstream Bank of Anthos commit is `1e40564f9ff572a28281198903e19da93e506770`.
- Managed Agent DevBox Gateway is active.
- DevClaw developer and tester workers are inactive.
- Skill Workshop proposal application requires explicit human approval.
- Heartbeat and autonomous Skill Workshop execution remain disabled.

## Execution Sequence

1. Verify local `application-modernization-lab` checkout is clean on `main` at merge commit `3de8845412853525aeb77d85db23f2d14b1bfc73`.
2. Verify PR #9 is merged and issue #8 is closed as completed.
3. Create `chore/experiment-07a-knowledge-review-workflow` in `ai-operations-platform`.
4. Write the foreground Knowledge Review request verbatim to `prompts/knowledge-review-request.md`.
5. Copy this workflow bundle to Agent DevBox.
6. Run `scripts/preflight-knowledge-review.sh`.
7. Run one foreground DevClaw Knowledge Review turn with `scripts/dispatch-knowledge-review.sh`.
8. Run `scripts/verify-knowledge-review-proposal.sh`.
9. Copy evidence and generated proposal artifacts back into this workflow folder.
10. Record the governed revision artifacts.
11. After explicit human approval, apply the proposal to the active OpenClaw workspace skill store.
12. Copy apply evidence and the active skill snapshot back into this workflow folder.
13. Commit this workflow recording branch for human review.
14. Push the exact commit through a git bundle transfer and broker-authenticated DevBox push if local GitHub credentials are unavailable.

## Safety Boundaries

- Do not apply, approve, revise, reject, quarantine, or enable proposals without explicit human approval.
- Do not create or edit active `SKILL.md` files outside the Skill Workshop approval/application flow.
- Do not begin Experiment 07B.
- Do not create or mutate issues, PRs, source repositories, infrastructure, Gateway configuration, or DevClaw package code.
- Do not expose or persist GitHub tokens or broker responses.
- Use only bounded foreground dispatch and bounded verification.

## Proposal Outcome

- Proposal name: `kubernetes-to-compose-migration`
- Proposal ID: `kubernetes-to-compose-migration-20260727-ddcee90daa`
- Status: `applied`
- Proposed version: `v2`
- Updated at: `2026-07-27T19:58:28.292Z`
- Applied at: `2026-07-27T19:58:28.292Z`
- Scanner result: `clean`
- Generated proposal files are recorded under `skill-workshop-proposal/kubernetes-to-compose-migration-20260727-ddcee90daa/`; this snapshot reflects the governed revision requested after the initial proposal.
- Active skill files are recorded under `applied-skill/kubernetes-to-compose-migration/`.
- Workflow recording commit is ready locally, but remote push is blocked until GitHub credentials or GitHub App permissions allow writes to `DimitryZH/ai-operations-platform`.

## Manual Human Review Result

The human operator explicitly approved applying proposal `kubernetes-to-compose-migration-20260727-ddcee90daa`. The proposal was applied after the revised scanner result remained `clean`.

## Rollback or Cleanup

The proposal is applied. A create-proposal rollback is represented by the Workshop `rollback.json` state and would remove the active skill through an explicit rollback/rejection workflow, not by deleting files ad hoc.

## Recorded Deviation

The Agent DevBox registered checkout for `application-modernization-lab` was clean but remained on `issue-8-bank-of-anthos-compose` and did not contain the merge commit locally. It was not changed because this workflow explicitly forbids modifying `application-modernization-lab`. The completed Windows checkout and GitHub PR/issue state were used as the authoritative merge evidence.

The workflow branch push is blocked: Windows local Git lacks usable GitHub credentials, and the existing Agent DevBox GitHub App token can read/write the experiment repository but received `403` for `DimitryZH/ai-operations-platform`.
