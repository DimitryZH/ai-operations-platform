# Roadmap

This repository is now aligned around the initial AI Operations Platform
migration: a GCP-first private Stateful VM runtime foundation with explicit
operational boundaries.

## Completed Foundation

- GCP private Stateful VM runtime foundation
- Persistent Disk state model
- IAP-only operator access
- Secret Manager runtime integration
- systemd-managed OpenClaw runtime
- service-state monitoring baseline
- Telegram status-only operator channel
- context lifecycle foundation
- removal of the legacy container-service scaffold

## Near-Term Next Steps

- validate the imported runtime from this target repository
- review Terraform plans with sanitized environment values
- run local Terraform validation before any reviewed infrastructure plan
- define a small context lifecycle implementation spike
- design operator workflows around explicit approvals
- design approval workflow records and review boundaries
- decide whether backend bootstrap automation belongs in this repository

## Deferred Work

- full alert routing
- incident workflows
- agent remediation
- platform adapters
- operational agents
- multi-agent orchestration
- restore-drill automation

## Explicitly Out Of Scope For Now

- alternate runtime foundations
- alternate cloud-provider scope
- cloud-provider abstraction
- write-capable Telegram commands
- unapproved autonomous remediation
- secrets, real chat IDs, Terraform state, tfvars, raw plans, or private
  operator notes in tracked files
