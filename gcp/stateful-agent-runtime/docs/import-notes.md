# Stateful Agent Runtime Import Notes

## Historical Source Reference

```text
ai-agent-host
```

The source repository was used as a read-only reference.

## Source Paths Imported

```text
gcp/openclaw_stateful_vm/terraform/
gcp/openclaw_stateful_vm/systemd/openclaw.service.tftpl
gcp/openclaw_stateful_vm/scripts/bootstrap-openclaw.sh.tftpl
gcp/openclaw_stateful_vm/docs/README.md
gcp/openclaw_stateful_vm/docs/stateful-vm-operations-runbook.md
gcp/openclaw_stateful_vm/docs/stateful-vm-backup-and-restore.md
gcp/openclaw_stateful_vm/docs/stateful-vm-implementation-summary.md
gcp/openclaw_stateful_vm/monitoring/
gcp/openclaw_stateful_vm/systemd/openclaw-service-state-exporter.service.tftpl
gcp/openclaw_stateful_vm/systemd/openclaw-service-state-exporter.timer.tftpl
gcp/openclaw_stateful_vm/terraform/service_state_exporter.tf
gcp/openclaw_stateful_vm/terraform/service_state_alert_policy.tf
gcp/openclaw_stateful_vm/terraform/monitoring.tf
gcp/openclaw_stateful_vm/telegram_adapter/
gcp/openclaw_stateful_vm/systemd/openclaw-telegram-adapter.service.tftpl
```

## Target Paths Created

```text
gcp/stateful-agent-runtime/README.md
gcp/stateful-agent-runtime/terraform/
gcp/stateful-agent-runtime/systemd/openclaw.service.tftpl
gcp/stateful-agent-runtime/scripts/bootstrap-openclaw.sh.tftpl
gcp/stateful-agent-runtime/monitoring/
gcp/stateful-agent-runtime/systemd/openclaw-service-state-exporter.service.tftpl
gcp/stateful-agent-runtime/systemd/openclaw-service-state-exporter.timer.tftpl
gcp/stateful-agent-runtime/terraform/service_state_exporter.tf
gcp/stateful-agent-runtime/terraform/service_state_alert_policy.tf
gcp/stateful-agent-runtime/terraform/monitoring.tf
gcp/stateful-agent-runtime/telegram_adapter/
gcp/stateful-agent-runtime/systemd/openclaw-telegram-adapter.service.tftpl
gcp/stateful-agent-runtime/docs/README.md
gcp/stateful-agent-runtime/docs/operations-runbook.md
gcp/stateful-agent-runtime/docs/backup-and-restore.md
gcp/stateful-agent-runtime/docs/monitoring-baseline.md
gcp/stateful-agent-runtime/docs/telegram-status-only-operator-channel.md
gcp/stateful-agent-runtime/docs/implementation-notes.md
gcp/stateful-agent-runtime/docs/import-notes.md
```

## Excluded Material

- existing target runtime scaffold outside this module
- restore-drill scripts
- backend bootstrap state setup
- `AI/` internal evidence
- planning-only material
- local Terraform state, local variable files, plans, logs, and secret values
- private operator notes and real operator identifiers

## Manual Follow-Up Items

- decide whether this repository owns remote Terraform backend bootstrap
- replace placeholder project, region, zone, image, and secret identifiers
- review service account naming and labels for the target project
- run `terraform init -backend=false` and `terraform validate` before any
  reviewed infrastructure plan
- set environment-specific Telegram token secret ID and allowed chat IDs only
  in untracked deployment inputs before enabling the adapter

## Post-Migration Follow-Up

- Context lifecycle scaffolding now lives under `platform/context/`.
- Add platform adapters and operational agents only after the runtime foundation
  is reviewed and stable.
