# Stateful Agent Runtime Docs

This directory documents the first AI Operations Platform import of the GCP
private Stateful VM runtime foundation.

## Current Docs

- [Operations Runbook](operations-runbook.md)
- [Backup And Restore](backup-and-restore.md)
- [Implementation Notes](implementation-notes.md)
- [Import Notes](import-notes.md)

## Runtime Posture

- one active OpenClaw gateway writer
- no public VM IP
- no public OpenClaw endpoint
- operator access through IAP and OS Login
- state on a preserved Persistent Disk mounted at `/var/lib/openclaw`
- runtime secrets loaded from Secret Manager at service start
- image rollout by immutable digest
- daily scheduled snapshots of the authoritative state disk

## Documentation Boundaries

These docs describe the base runtime foundation only. Later modules should add
separate documentation for monitoring, Telegram status-only operation, context
lifecycle management, platform adapters, and operational agents.

Do not record secret values, token material, private operator notes, raw plans,
or raw logs in this documentation tree.
