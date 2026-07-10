# Context Lifecycle

The context lifecycle defines how operational information moves from an
incoming signal to a retained, summarized, or expired record.

## Stages

1. Capture

   Capture the minimum useful operational signal. Inputs may include operator
   prompts, service-state summaries, command outcomes, incident notes, rollout
   observations, or Telegram status-only requests.

2. Normalize

   Convert captured inputs into a stable, non-secret shape. Normalize names,
   timestamps, environment references, and status fields. Remove raw payloads
   that are not needed for review.

3. Summarize

   Summarize noisy or repeated context into concise operational facts. The
   summary should preserve what was observed, what was inferred, what was
   approved, and what remains unknown.

4. Retain

   Retain only context that has a clear operational purpose. Long-lived context
   should be explicit and reviewable. Transient task context should expire
   after the task is complete or superseded.

5. Archive

   Archive important summaries, decisions, approvals, and evidence references
   when they are needed for later operations or audits. Archive summaries, not
   raw secrets, raw logs, raw Terraform plans, or local state files.

6. Expire

   Expire context that is stale, duplicated, superseded, or no longer useful.
   Expiration should not remove separately tracked approvals or durable runtime
   state.

## Long-Lived vs Transient Context

Long-lived context describes stable operational knowledge: architecture
decisions, validated runtime behavior, approved boundaries, and retained
post-incident summaries.

Transient task context describes one investigation or workflow: current goal,
recent observations, candidate actions, and unresolved questions. It should not
become a permanent instruction source without review.

## Human Approval Boundary

Context can inform a recommendation, but it does not authorize action by
itself. Destructive changes, infrastructure mutation, credential changes, and
capability expansion require explicit human approval in the active workflow.

Agent memory and retained summaries must not silently become execution
authority.
