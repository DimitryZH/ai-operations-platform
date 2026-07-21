# AI Operations Platform

AI Operations Platform is a GCP-first platform foundation for self-hosted AI
operations runtimes.

The current foundation starts with a private Stateful VM runtime, service-state
monitoring, a status-only Telegram operator channel, and explicit context
lifecycle boundaries.

## Recent Validation

Experiment 06 validated a governed multi-agent migration workflow by moving Google Cloud Online Boutique from a Docker Compose baseline to .NET Aspire in [Application Modernization Lab](https://github.com/DimitryZH/application-modernization-lab), with independent defect detection, corrective validation, human-controlled merge, and operator-approved skill promotion documented in the [case study](docs/case-studies/experiment-06-online-boutique-compose-to-aspire.md).

## Current Foundation

- GCP private Stateful VM runtime under `gcp/stateful-agent-runtime/`
- Persistent Disk state model for the self-hosted runtime
- IAP-only operator access
- Secret Manager integration
- systemd-managed OpenClaw runtime
- service-state monitoring baseline
- Telegram status-only operator channel
- context lifecycle foundation under `platform/context/`

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
- [Context Lifecycle Foundation](platform/context/README.md)

## Scope Boundaries

The repository is centered on the Stateful VM runtime foundation. The legacy
container-service scaffold has been removed.

Do not commit secrets, real chat IDs, Terraform state, local tfvars, raw plans,
raw logs, private operator notes, `AI/`, or local-only roadmap material.
