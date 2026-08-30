# AI Operations Platform

AI Operations Platform is a GCP-first, AI-native operations control plane for
human-reviewed software engineering, DevOps, SRE, Platform Engineering,
Infrastructure as Code, FinOps, security, and cloud operations work.

The platform direction is defined by
[ADR 0001](docs/adr/0001-primary-orchestrator-foundation.md): durable task and
attempt state belong outside ephemeral agent sessions, executors are
replaceable, capabilities are declared and verified before active attempts, and
human approvals remain explicit control-plane decisions.

## Current Foundation

- GCP private Stateful VM runtime under `gcp/stateful-agent-runtime/`
- Persistent Disk state model for private runtime state
- IAP-only operator access
- Secret Manager integration
- systemd-managed OpenClaw runtime
- service-state monitoring baseline
- Telegram status-only operator channel
- context lifecycle foundation under `platform/context/`
- accepted ADR 0001 primary-orchestrator decision

Implemented fact: the current Stateful VM foundation includes a
systemd-managed OpenClaw runtime. Accepted evidence preserves that bounded
runtime foundation and application-modernization use without making OpenClaw
the primary platform orchestrator.

## Platform Direction

The intended architecture separates:

- operator interfaces and optional communication gateways
- the AI Operations control plane
- durable task and attempt state
- executor adapters with capability handshakes
- replaceable executors
- target repositories, platforms, and tools
- validation, evidence, human review, and GitHub audit records

OpenClaw may be reconsidered as an optional communication gateway or
interactive runtime after separate operational validation. DevClaw remains
useful as workflow research and a source of governance concepts, but it is not
a required primary-orchestration dependency.

## Recent Validation

Experiment 06 validated a governed application-migration workflow by moving
Google Cloud Online Boutique from a Docker Compose baseline to .NET Aspire in
[Application Modernization Lab](https://github.com/DimitryZH/application-modernization-lab),
with independent defect detection, corrective validation, human-controlled
merge, and operator-approved skill promotion documented in the
[case study](docs/case-studies/experiment-06-online-boutique-compose-to-aspire.md).

That migration success remains separate from the ADR 0001 decision not to
select the evaluated OpenClaw/DevClaw architecture as the primary orchestrator.
It remains technically valid historical application-modernization evidence and
does not override the orchestration non-selection recorded in ADR 0001.

## Repository Structure

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

## Documentation

- [Architecture](docs/architecture.md)
- [Security Model](docs/security-model.md)
- [Operating Model](docs/operating-model.md)
- [Backup & Restore](docs/backup-restore.md)
- [Roadmap](docs/roadmap.md)
- [Initial Migration Closeout](docs/migration-closeout.md)
- [Stateful Agent Runtime](gcp/stateful-agent-runtime/README.md)
- [SRE Control-Plane GCP Deployment Foundation](gcp/sre-control-plane/README.md)
- [Context Lifecycle Foundation](platform/context/README.md)

## Scope Boundaries

The repository is centered on a GCP-first platform foundation and an
AI-native operations control-plane direction. The legacy container-service
scaffold has been removed.

Do not commit secrets, real chat IDs, Terraform state, local tfvars, raw plans,
raw logs, private operator notes, `AI/`, or local-only roadmap material.
