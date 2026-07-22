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

## Validated Agent Delivery Workflow

Experiment 06 validated a bounded delivery workflow layered on top of the
runtime foundation. The workflow is documented in the
[Online Boutique Compose-to-Aspire case study](case-studies/experiment-06-online-boutique-compose-to-aspire.md).

The validated reference workflow used:

- a human operator for scope, architecture approval, merge approval, and skill
  application decisions
- OpenClaw as the operator-facing control surface and agent runtime
- DevClaw for workflow, role dispatch, and task-state orchestration
- separated architect, developer, and independent tester roles
- controlled Agent DevBox execution for repository work and validation
- GitHub issues, labels, branches, pull requests, comments, and merge history
  as durable delivery state
- foreground Knowledge Review after merge
- Skill Workshop proposal review followed by explicit human Apply

This capability is separate from the core GCP runtime foundation. It validates
one sequential, human-reviewed migration workflow, not unattended production
remediation or universal autonomous delivery. Cross-project reuse value for the
applied migration skill remains unvalidated.

Hermes Agent remains historical candidate research. It was not the
implementation workflow used for Experiment 06; the validated workflow used
OpenClaw and DevClaw.

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
