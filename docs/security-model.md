# Security Model

AI Operations Platform follows a least-privilege operational model for a
GCP-first, self-hosted runtime foundation.

## Core Principles

- private runtime by default
- IAP-only operator access
- dedicated runtime service accounts
- Secret Manager for secret values
- no secret values in Git, Terraform variables, metadata, docs, or context
- human approval before destructive actions
- status-only Telegram channel without execution authority

## Runtime Isolation

The current runtime foundation is `gcp/stateful-agent-runtime/`.

It uses:

- private Compute Engine VM without a public IP
- OS Login and IAP for operator access
- preserved Persistent Disk for runtime state
- systemd for runtime process ownership
- Secret Manager retrieval into VM-local files
- Terraform-managed IAM and infrastructure boundaries

## Context Boundary

Operational context must remain separate from runtime state and execution
authority.

Context may store sanitized summaries, evidence references, operator intent,
and explicit approval records. It must not store secrets, raw credentials, real
Telegram chat IDs, Terraform state, local tfvars, raw plans, or private
operator notes.

## Telegram Boundary

The Telegram operator channel is status-only. Supported commands are `/status`,
`/health`, `/whoami`, and `/help`.

Telegram messages are observation inputs only. They are not approval signals and
must not authorize mutation, remediation, Terraform actions, shell execution,
GitHub write actions, or incident workflows.
