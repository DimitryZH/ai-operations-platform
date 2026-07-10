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
