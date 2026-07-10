# Backup & Restore

The current backup and restore model starts with the GCP Stateful VM runtime
foundation.

## Runtime State

Runtime state belongs to `gcp/stateful-agent-runtime/`.

The runtime uses a preserved Persistent Disk for durable OpenClaw state. Backup
and restore details for this foundation are documented in:

- [Stateful Runtime Backup And Restore](../gcp/stateful-agent-runtime/docs/backup-and-restore.md)

## Platform Context

Platform context is separate from runtime state. Context backup should retain
reviewed summaries, decisions, approval records, and evidence references only
when they have operational value.

Do not back up or retain:

- secret values
- raw credentials or tokens
- real Telegram chat IDs
- Terraform state files
- local tfvars
- raw plans
- private operator notes
- sensitive raw logs

## Restore Boundary

Restoring runtime state must not imply approval to execute remediation,
Terraform changes, shell commands, or capability expansion. Those actions still
require explicit human approval.
