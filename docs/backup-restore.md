# Backup & Restore

The current backup and restore model starts with the GCP Stateful VM runtime
foundation and extends toward durable control-plane task and attempt state.

## Runtime State

Runtime state for the private GCP foundation belongs to
`gcp/stateful-agent-runtime/`.

The runtime uses a preserved Persistent Disk for durable VM-local state. Backup
and restore details for this foundation are documented in:

- [Stateful Runtime Backup And Restore](../gcp/stateful-agent-runtime/docs/backup-and-restore.md)

Restoring VM runtime state is separate from restoring or resuming an operations
task.

## Control-Plane State

Durable task and attempt state must exist outside ephemeral agent sessions.
Control-plane backup and restore should preserve reviewable records needed to
understand task identity, attempt identity, executor assignment, capability
verification, approval state, evidence references, GitHub references, recovery
state, and final closeout.

Restored task or attempt records must not become active until required
capabilities are declared and verified again. Missing or ambiguous capability
state must fail closed.

## Platform Context

Platform context is separate from runtime state and execution authority. Context
backup should retain reviewed summaries, decisions, approval records, and
evidence references only when they have operational value.

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

Restoring runtime, context, task, or attempt state must not imply approval to
execute remediation, Terraform changes, shell commands, GitHub writes, runtime
changes, merge, or capability expansion. Those actions still require explicit
human approval.
