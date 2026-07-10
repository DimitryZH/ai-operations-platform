# Roadmap

This repository is centered on a GCP-first Stateful VM runtime foundation for
AI Operations Platform.

## Completed Foundation Imports

- private Stateful VM runtime foundation
- service-state monitoring baseline
- Telegram status-only operator channel
- context lifecycle foundation

## Near-Term Direction

1. Review and harden the Stateful VM runtime foundation.
2. Keep service-state monitoring disabled or limited until each environment
   explicitly approves writes and alerts.
3. Keep Telegram status-only and disabled by default unless a reviewed
   environment provides token and allowlist inputs.
4. Evolve `platform/context/` from documentation into reviewed interfaces only
   after the context lifecycle boundaries are accepted.

## Later Platform Layers

- operational agents
- workflow orchestration
- platform adapters
- human-approved remediation workflows

## Boundaries

- no legacy container-service scaffold as the platform foundation
- no alternate cloud-provider planning in the current foundation
- no Telegram capability expansion without a separate design and approval
- no secrets, real chat IDs, Terraform state, tfvars, raw plans, or private
  operator notes in tracked files
