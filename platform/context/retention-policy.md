# Retention Policy

This initial retention policy is intentionally lightweight. It defines what the
platform should retain, summarize, archive, or reject before any implementation
exists.

## Transient Context

Transient context is short-lived task state. It may include current
observations, working assumptions, candidate next steps, and unresolved
questions.

Retain only while the task is active or while it is needed to produce a reviewed
summary. Expire when the task is complete, superseded, or abandoned.

## Summarized Context

Summarized context is compact, reviewed operational knowledge. It may include:

- validated runtime status
- incident or rollout summaries
- decisions and rationale
- known limitations
- follow-up items

Retain while it remains useful for future operations. Update or expire summaries
when they become stale.

## Evidence References

Evidence references point to source material without copying sensitive raw
content. Prefer stable links, file paths, command names, timestamps, and short
sanitized excerpts.

Retain evidence references when they support a decision, approval, or
post-incident summary.

## Approval Records

Approval records should identify:

- who approved
- what action was approved
- the target environment
- the allowed scope
- the time or task boundary

Retain approval records according to the operational audit requirement for the
environment. Do not infer approval from memory, old context, or Telegram
status-only messages.

## Forbidden Data

Reject or redact forbidden data instead of retaining it. This includes:

- secrets and credentials
- raw tokens
- real chat IDs
- Terraform state
- `.tfvars`
- raw plans
- sensitive raw logs
- private notes

If forbidden data is discovered in captured context, the retained summary should
record that redaction happened without preserving the value.
