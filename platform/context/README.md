# Context Lifecycle Foundation

This directory defines the first platform-level context lifecycle foundation for
AI Operations Platform. It sits above the GCP Stateful VM runtime foundation and
describes how operational context should be captured, bounded, reviewed, and
retained before any runtime implementation exists.

## Purpose

Operational context is the reviewable information that helps operators and
future agents understand what happened, what is being investigated, what was
approved, and what remains unresolved.

Examples include:

- incident or rollout summaries
- sanitized service-state observations
- operator intent and task scope
- explicit human approvals
- links to reviewed evidence
- bounded follow-up notes

Operational context is separate from runtime infrastructure state. The Stateful
VM owns durable runtime state such as OpenClaw data, VM-local runtime files, and
Persistent Disk contents. The platform context layer owns summarized,
reviewable, non-secret operational records.

## Principles

- Runtime state and operational context are separate concerns.
- Platform context must be explicit, reviewable, and bounded.
- No secrets are stored as context.
- No raw credentials, tokens, chat IDs, tfvars, Terraform state, raw plans, or
  private operator notes are stored as context.
- Destructive actions require human approval.
- Agent memory must not silently become execution authority.
- Telegram status-only messages are observation inputs, not approval signals.

## Current Scope

This is documentation and scaffold only. It does not add runtime logic,
database schemas, APIs, Terraform, systemd units, or agent framework
dependencies.

## Documents

- [Lifecycle](lifecycle.md)
- [State Boundaries](state-boundaries.md)
- [Retention Policy](retention-policy.md)
