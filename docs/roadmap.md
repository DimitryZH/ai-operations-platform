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

## Validated Workflow Status

Experiment 06 validated a bounded OpenClaw and DevClaw delivery workflow for
an application migration. See the
[Online Boutique Compose-to-Aspire case study](case-studies/experiment-06-online-boutique-compose-to-aspire.md)
for evidence and scope boundaries.

| Capability | Status |
|---|---|
| Governed multi-agent migration workflow | VALIDATED |
| Independent defect detection and correction loop | VALIDATED |
| Human-controlled GitHub delivery workflow | VALIDATED |
| Governed knowledge promotion through Skill Workshop | VALIDATED |
| Cross-project skill reuse | PENDING VALIDATION |

The next proof is to reuse `compose-to-aspire-migration` in a fresh project or
session boundary, then evaluate whether it reduces unnecessary rediscovery or
improves consistency while preserving functional, negative, isolation, and
independent-review rigor.

The validated result does not mark parallel multi-agent execution, unattended
heartbeat-driven delivery, automatic merge, production remediation, destructive
infrastructure execution, universal autonomous software engineering, or
production readiness as complete.

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
