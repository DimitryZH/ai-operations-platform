# Initial Migration Closeout

This document closes the initial migration of AI Operations Platform into its
new repository shape.

## Migrated

- GCP private Stateful VM runtime foundation
- Persistent Disk state model for the self-hosted OpenClaw runtime
- IAP-only operator access model
- Secret Manager runtime integration
- systemd-managed runtime service
- service-state monitoring baseline
- disabled-by-default service-state alert policy skeleton
- Telegram status-only operator channel
- platform context lifecycle foundation

## Intentionally Not Migrated

- legacy container-service scaffold
- restore-drill automation
- backend bootstrap automation
- full alert routing
- incident workflows
- agent remediation logic
- platform adapters
- operational agents
- private notes, raw logs, local state, and secret material

## Current Repository Structure

```text
ai-operations-platform/
|-- docs/
|-- gcp/
|   `-- stateful-agent-runtime/
|-- platform/
|   `-- context/
|-- LICENSE
`-- README.md
```

## Runtime Foundation

The active runtime foundation is `gcp/stateful-agent-runtime/`.

It is GCP-first, private by default, single-writer, disk-backed, and managed by
Terraform and systemd. Optional service-state and Telegram components remain
controlled by explicit enable flags and reviewed environment inputs.

## Operational Boundaries

- Runtime state and operational context are separate concerns.
- Context is explicit, reviewable, bounded, and non-secret.
- Telegram is status-only and does not grant approval authority.
- Monitoring writes and alert policy creation remain disabled by default.
- Destructive actions, infrastructure mutation, credential changes, and
  capability expansion require explicit human approval.

## Remaining Future Work

- validate the imported runtime in the target repository
- review Terraform plans with sanitized environment values
- design context lifecycle implementation interfaces
- design operator workflows and approval workflows
- decide whether this repository owns backend bootstrap automation
- add future platform adapters, agents, and orchestration as separate reviewed
  work
