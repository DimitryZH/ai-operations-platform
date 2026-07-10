# Stateful Agent Runtime Implementation Notes

**Status:** Initial foundation import for AI Operations Platform.
**Scope:** Base private GCP Stateful VM runtime foundation only.

## Summary

This module provides a small GCP-native Terraform layer for a private,
single-writer OpenClaw gateway with preserved state.

The implementation models:

- dedicated private VPC/subnet by default, or reviewed existing network inputs
- Cloud Router and Cloud NAT for private outbound access
- IAP-only SSH and gateway firewall rules
- Google health-check-only probe access
- dedicated least-privilege runtime service account
- repository-scoped Artifact Registry read access
- named-secret-scoped Secret Manager access
- separate protected `pd-balanced` state disk
- Ubuntu 24.04 LTS instance template with no public IP
- systemd-managed existing OpenClaw container image pinned by digest
- zonal stateful managed instance group with `target_size = 1`
- TCP autohealing check with a conservative initial delay
- daily snapshot policy with initial 14-day retention

## Resource Decisions

### Data Disk

The data disk is an explicit `google_compute_disk` attached to the instance
template by name. Because target size is exactly one, the disk has one intended
writer. The managed instance group marks the device stateful with
`delete_rule = NEVER`. Terraform also applies `prevent_destroy`.

Decommissioning or replacing the authoritative disk requires a reviewed code
change and recovery decision.

### Update Policy

The update policy uses recreate semantics and zero surge. This permits downtime
but prevents overlapping old and new gateway writers. No autoscaler exists.

### Health Check

TCP is the default health-check mode. HTTP autohealing should remain deferred
until endpoint behavior is proven safe for replacement decisions.

### Secret Retrieval

Terraform grants access to named existing secrets. At service start, a root-only
helper obtains a short-lived VM service account token from the metadata server,
retrieves each secret through the Secret Manager API, and writes it to
`/run/openclaw/secrets` as runtime-user-readable files.

Secret values are not placed in:

- Terraform variables or state
- instance metadata
- startup script
- systemd command lines
- Git

### Container Lifecycle

systemd owns restarts. Docker does not receive an autonomous restart policy.
The unit:

- requires `/var/lib/openclaw` to be mounted
- prepares secrets and pulls the pinned image before start
- drops all Linux capabilities
- enables `no-new-privileges`
- mounts only explicit state, workspace, runtime, and secret paths
- logs to journald
- stops the container gracefully

## Required APIs

Required before a future apply, but intentionally not managed by this Terraform
root:

```text
artifactregistry.googleapis.com
compute.googleapis.com
iap.googleapis.com
logging.googleapis.com
secretmanager.googleapis.com
```

## Deferred Work

Deferred from this first import:

- monitoring and service-state exporter
- Telegram status-only operator channel
- restore-drill automation
- context lifecycle management
- platform adapters
- operational agents and workflow orchestration

## Risks

- The state disk protection is intentionally strict and requires explicit
  decommission steps.
- A bad health signal can still cause a replacement loop.
- Applying a new template causes downtime because surge is prohibited.
- Scheduled snapshots are not a substitute for tested restore drills.
- PR/write behavior remains a separate capability decision.
