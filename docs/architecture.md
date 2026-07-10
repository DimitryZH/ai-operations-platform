# Architecture

AI Operations Platform is a GCP-first platform foundation for self-hosted AI
operations runtimes.

The current architecture starts with a private Stateful VM runtime and layers
operational context, operator channels, monitoring, and future platform
capabilities above it.

## Current Layers

```text
AI Operations Platform
|-- platform/context/
|   `-- explicit operational context lifecycle boundaries
`-- gcp/stateful-agent-runtime/
    |-- private Stateful VM runtime
    |-- Persistent Disk state model
    |-- IAP-only operator access
    |-- Secret Manager runtime integration
    |-- systemd-managed OpenClaw runtime
    |-- service-state monitoring baseline
    `-- Telegram status-only operator channel
```

## Runtime Foundation

The runtime foundation lives in `gcp/stateful-agent-runtime/`.

It provides:

- private Compute Engine VM runtime with no public VM IP
- preserved Persistent Disk for durable runtime state
- Terraform-managed infrastructure
- runtime secrets loaded from Secret Manager
- systemd-managed OpenClaw service
- optional service-state exporter wiring
- optional Telegram status-only adapter wiring

## Context Layer

The context lifecycle foundation lives in `platform/context/`.

It defines how the platform separates durable runtime state from reviewable
operational context, summaries, evidence references, approvals, and forbidden
data.

## Design Boundaries

- Runtime state and operational context are separate concerns.
- Stateful VM state is durable runtime state.
- Platform context is explicit, reviewable, and bounded.
- Telegram status-only interactions are observation inputs, not approval
  signals.
- Destructive actions require human approval.
- No secrets, raw credentials, real chat IDs, Terraform state, local tfvars, or
  raw plans belong in tracked context.
