# Operating Model

AI Operations Platform assists operators through a GCP-first operations control
plane. It is not an autonomous infrastructure control system.

## Operating Philosophy

```text
Observe -> Summarize -> Recommend -> Human Approves -> Execute -> Validate -> Review
```

The platform should:

- summarize operational signals
- preserve context boundaries
- recommend actions with clear scope
- verify capabilities before execution
- require human approval before mutation
- avoid uncontrolled infrastructure changes
- retain reviewable evidence without secrets

## Current Operational Surface

- GCP Stateful VM runtime foundation: `gcp/stateful-agent-runtime/`
- service-state monitoring baseline: runtime status observations
- Telegram status-only channel: `/status`, `/health`, `/whoami`, `/help`
- context lifecycle foundation: `platform/context/`
- accepted primary-orchestrator decision:
  `docs/adr/0001-primary-orchestrator-foundation.md`

## Control-Plane Workflow

The control plane owns or coordinates task lifecycle, attempt lifecycle,
executor selection, capability requirements, approvals, dispatch, execution
tracking, validation, evidence references, recovery, and final closeout.

Before an attempt becomes active, the selected executor adapter must declare
and verify the required capabilities for the task. Capability examples include
filesystem access, Git operations, Docker/runtime access, API access,
validation commands, branch updates, and pull request updates.

If a required capability is missing, ambiguous, or not verifiable, the attempt
must fail closed before repository, infrastructure, or runtime mutation begins.

## Logical Responsibilities

Architect, developer, tester-validator, and human reviewer are logical
responsibilities in the workflow. They can be performed by different tools,
sessions, or people, but the platform should not require them to be fixed
long-running agent processes.

The first implementation should keep the workflow sequential and
human-reviewed. Parallel and multi-agent execution remain later capabilities
that require separate validation.

## Approval Boundary

Operational context can inform a recommendation, but it does not authorize
execution.

Human approvals and approval audit records are control-plane responsibilities.
Destructive actions, infrastructure mutation, credential changes, capability
expansion, merge, and reusable-knowledge application require explicit human
approval in the active workflow.

Telegram status-only messages are observation inputs only. They are not
approval signals.

## GitHub Boundary

GitHub issues, branches, pull requests, commits, comments, reviews, and merge
commits remain durable workflow evidence and review boundaries. GitHub is not
required to be the internal execution-state engine for task and attempt
lifecycle.

## Validated Delivery Pattern

Historical application-modernization evidence: Experiment 06 validated a
sequential, human-reviewed delivery pattern for one bounded application
migration. The outcome is summarized in the
[Online Boutique Compose-to-Aspire case study](case-studies/experiment-06-online-boutique-compose-to-aspire.md).

1. Create a GitHub issue with bounded scope.
2. Complete architecture analysis.
3. Obtain human architecture approval.
4. Implement through a branch and pull request.
5. Run independent tester validation.
6. Return to developer correction when evidence is insufficient.
7. Obtain human merge approval.
8. Run foreground Knowledge Review.
9. Prepare a pending Skill Workshop proposal.
10. Review and Apply the skill through an explicit human action.
11. Complete final closeout.

During the validated workflow, execution was sequential, recurring heartbeat
remained disabled, automatic merge remained disabled, and autonomous Skill
Workshop application remained disabled. Architecture, merge, and skill
application remained human decisions.

That application-modernization result remains valid. It is separate from the
ADR 0001 decision not to select the evaluated OpenClaw/DevClaw architecture as
the primary orchestrator, does not override that non-selection, and must not be
read as restart or reboot recovery evidence.

## Runtime Candidates

OpenClaw may be reconsidered as an optional communication gateway or
interactive runtime after separate operational validation. DevClaw remains
workflow research and a source of governance concepts, not a required primary
dependency.

Other executor, runtime, workflow, or control-plane frameworks remain
candidates or hypotheses until accepted through separate evidence-backed
selection.
