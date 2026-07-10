# Stateful Agent Runtime Import Notes

## Source Repository

```text
C:\projects\ai\ai-agent-host
```

The source repository was used as a read-only reference.

## Source Paths Imported

```text
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\terraform\
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\systemd\openclaw.service.tftpl
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\scripts\bootstrap-openclaw.sh.tftpl
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\docs\README.md
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\docs\stateful-vm-operations-runbook.md
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\docs\stateful-vm-backup-and-restore.md
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\docs\stateful-vm-implementation-summary.md
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\monitoring\
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\systemd\openclaw-service-state-exporter.service.tftpl
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\systemd\openclaw-service-state-exporter.timer.tftpl
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\terraform\service_state_exporter.tf
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\terraform\service_state_alert_policy.tf
C:\projects\ai\ai-agent-host\gcp\openclaw_stateful_vm\terraform\monitoring.tf
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
gcp/stateful-agent-runtime/docs/README.md
gcp/stateful-agent-runtime/docs/operations-runbook.md
gcp/stateful-agent-runtime/docs/backup-and-restore.md
gcp/stateful-agent-runtime/docs/monitoring-baseline.md
gcp/stateful-agent-runtime/docs/implementation-notes.md
gcp/stateful-agent-runtime/docs/import-notes.md
```

## Excluded Material

- existing target runtime scaffold outside this module
- Telegram adapter code and systemd unit
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
- decide when to import Telegram status-only support

## Next Planned Commits

1. Add Telegram status-only operator channel after token and allowlist handling
   are reviewed.
2. Add context lifecycle scaffolding under the platform layer.
3. Add platform adapters and operational agents after the runtime foundation is
   stable.
