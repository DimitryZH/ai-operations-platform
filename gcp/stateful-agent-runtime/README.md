# Stateful Agent Runtime

This module is the GCP private Stateful VM runtime foundation for AI
Operations Platform.

It imports the proven single-writer OpenClaw runtime pattern into a
product-neutral module path. OpenClaw names remain where they describe the
current runtime, service, container, state path, environment variables, or
operator commands.

## What This Module Provides

- private Compute Engine runtime with no public VM IP
- zonal stateful managed instance group with target size `1`
- preserved Persistent Disk mounted at `/var/lib/openclaw`
- IAP and OS Login operator access
- Secret Manager runtime retrieval into VM-local files
- systemd-managed OpenClaw container
- digest-pinned image rollout
- daily snapshot policy for the authoritative state disk
- manual rollback by previous image digest or reviewed state recovery

## What Was Imported

- Terraform source for the private VM, network, IAM, state disk, instance
  template, stateful MIG, health check, snapshot policy, and outputs
- `openclaw.service` systemd template
- bootstrap template for disk mount, secret retrieval, runtime environment
  rendering, and systemd wiring
- runtime documentation index, operations runbook, backup and restore guide,
  implementation notes, and import notes

## Intentionally Excluded

- monitoring and service-state exporter code
- Telegram status-only adapter
- context lifecycle work
- platform adapters
- restore-drill automation
- backend bootstrap state setup
- local Terraform state, local tfvars, plans, logs, secret values, and internal
  evidence

## Directory Layout

```text
gcp/stateful-agent-runtime/
|-- README.md
|-- terraform/
|-- systemd/
|-- scripts/
`-- docs/
```

## Manual Configuration Required

Before any future plan or apply, review and set:

- `project_id`, `region`, and `zone`
- immutable `container_image` digest
- Artifact Registry project, location, and repository
- Secret Manager secret IDs for gateway, model, and optional GitHub mode
- operator and admin IAM members
- machine type, disk sizes, network choice, and snapshot retention
- remote Terraform backend ownership

Do not place secret values in tracked files, Terraform variables, metadata, or
startup scripts.

## First Validation Commands

Local-only formatting checks:

```bash
terraform -chdir=gcp/stateful-agent-runtime/terraform fmt -recursive
terraform -chdir=gcp/stateful-agent-runtime/terraform fmt -check -recursive
```

Optional local Terraform validation before any reviewed plan:

```bash
terraform -chdir=gcp/stateful-agent-runtime/terraform init -backend=false
terraform -chdir=gcp/stateful-agent-runtime/terraform validate
```

Do not run infrastructure plans or applies without a separate approval.

## Next Planned Imports

Add these as separate commits after the base private VM runtime is reviewed:

- monitoring and service-state exporter baseline
- Telegram status-only operator channel
- context lifecycle module
- platform adapters
