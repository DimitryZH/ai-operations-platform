# State Boundaries

AI Operations Platform separates runtime state, operational context, evidence,
operator intent, approvals, and forbidden data.

## Runtime Infrastructure State

Runtime infrastructure state belongs to the GCP Stateful VM runtime foundation.
Examples include:

- Persistent Disk contents
- OpenClaw runtime state
- VM-local runtime files
- systemd-managed service state
- runtime secret files loaded from Secret Manager
- Terraform-managed infrastructure state outside this repository

This state is durable runtime material. Platform context may reference its
existence or summarize observed status, but it should not copy raw runtime
state.

## Operational Context

Operational context belongs to the platform layer. Examples include:

- sanitized status summaries
- task scopes and assumptions
- incident or rollout narratives
- reviewed operational observations
- retained decision summaries
- follow-up items

Operational context should be explicit, bounded, and understandable without
granting execution authority.

## Evidence

Evidence is the supporting material behind an operational summary. Store
evidence as links, references, or compact excerpts when possible. Avoid raw log
dumps and raw plans unless a separate reviewed evidence store is designed.

## Operator Intent

Operator intent captures what a human asked the platform to inspect, explain,
recommend, or change. Intent is not the same as approval. A request to analyze
or recommend does not authorize mutation.

## Approvals

Approvals must be explicit and tied to a concrete action, scope, environment,
and time. Destructive actions and runtime mutation require active human
approval before execution.

Telegram status-only messages are observation inputs. They are not approval
signals and must not expand the adapter beyond `/status`, `/health`, `/whoami`,
and `/help`.

## Forbidden Context

Never store these as platform context:

- secret values
- raw credentials or tokens
- real Telegram bot tokens
- real Telegram chat IDs
- `.tfvars` files
- Terraform state files
- raw Terraform plans
- private operator notes
- raw logs containing sensitive data
- local-only `AI/` material
- `ROADMAP.md` if it is local-only or ignored
