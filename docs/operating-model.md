# Operating Model

AI Operations Platform assists operators. It is not an autonomous
infrastructure control system.

## Operating Philosophy

```text
Observe -> Summarize -> Recommend -> Human Approves -> Execute
```

The platform should:

- summarize operational signals
- preserve context boundaries
- recommend actions with clear scope
- require human approval before mutation
- avoid uncontrolled infrastructure changes
- keep retained context reviewable and free of secrets

## Current Operational Surface

- Stateful VM runtime foundation: `gcp/stateful-agent-runtime/`
- Service-state monitoring baseline: runtime status observations
- Telegram status-only channel: `/status`, `/health`, `/whoami`, `/help`
- Context lifecycle foundation: `platform/context/`

## Validated Delivery Pattern

Experiment 06 validated a sequential, human-reviewed delivery pattern for one
bounded application migration. The outcome is summarized in the
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

## Approval Boundary

Operational context can inform a recommendation, but it does not authorize
execution.

Destructive actions, infrastructure mutation, credential changes, capability
expansion, and remediation workflows require explicit human approval in the
active workflow.

Telegram status-only messages are not approval signals.

## Future Direction

Future platform layers may add operational agents, workflow orchestration, and
platform adapters. Those layers should consume context through explicit,
bounded, reviewable interfaces and preserve the runtime and approval
boundaries defined here.
