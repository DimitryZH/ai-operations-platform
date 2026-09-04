# Security Model

AI Operations Platform follows a least-privilege operational model for a
GCP-first operations control plane and private runtime foundation.

## Core Principles

- private runtime by default
- IAP-only operator access
- dedicated runtime service accounts
- Secret Manager for secret values
- no secret values in Git, Terraform variables, metadata, docs, or context
- explicit capability verification before active execution attempts
- fail-closed behavior for missing, ambiguous, or unverifiable capabilities
- human approval before destructive actions
- status-only Telegram channel without execution authority

## Runtime Isolation

The current runtime foundation is `gcp/stateful-agent-runtime/`.

It uses:

- private Compute Engine VM without a public IP
- OS Login and IAP for operator access
- preserved Persistent Disk for private runtime state
- systemd for runtime process ownership
- Secret Manager retrieval into VM-local files
- Terraform-managed IAM and infrastructure boundaries

## Control-Plane Boundary

The control plane owns or coordinates task state, attempt state, capability
requirements, capability verification, approval records, dispatch decisions,
evidence references, timeout handling, recovery, and final closeout.

The control plane must not treat gateway health, plugin loading, dispatch
acceptance, session creation, or minimal command execution as proof that an
executor can complete the requested operational work. Capability handshakes
must verify required filesystem, Git, Docker/runtime, API, validation, branch,
or pull request capabilities before an attempt becomes active.

If capability status is missing or ambiguous, execution fails closed.

The current GCP control-plane deployment evidence is split by phase:

- [bootstrap foundation evidence](deployments/gcp-sre-control-plane-bootstrap-2026-09-01.md)
- [private fake-runtime evidence](deployments/gcp-sre-control-plane-runtime-2026-09-01.md)
- [SRE replay executor evidence](deployments/gcp-sre-control-plane-sre-replay-executor-2026-09-04.md)

The deployed runtime remains private and authenticated, uses fake adapters only,
keeps Scheduler paused, and does not grant cluster access or live publication
authority.

PostgreSQL remains the source of truth for task, attempt, result, evidence
reference, publication, and review state. The GCS evidence adapter is only an
artifact sink behind the product-neutral evidence-store interface. It writes
sanitized JSON outside database transactions and locks, addresses objects by
the package SHA-256, uses generation preconditions for idempotent creation, and
records only validated artifact metadata back into PostgreSQL. Before accepting
a GCS object, it fail-closes on missing or unsafe object metadata, unexpected
remote size, non-JSON content type, oversized readback, or SHA-256 mismatch.

The GitHub publisher remains behind the product-neutral publisher interface and
is disabled by default for local development and tests. The private GCP runtime
can select it only through an explicit `github` publisher mode, an exact
repository and Issue allowlist match, and a Secret Manager version reference.
Terraform never stores the token value. GitHub calls occur outside database
transactions and locks, and PostgreSQL records only append-only publication
outcomes and validated references.

The bounded SRE replay executor remains behind the product-neutral executor
interface and is disabled by default. It can be selected only through explicit
`sre_replay` executor mode and an exact approved provider declaration for the
first staging contract. The declaration models Kubernetes, Prometheus, GitOps,
and optional recovery-observation boundaries with read-only verbs/actions,
approved namespace and GitOps scopes, and an exact Prometheus query allowlist.
It fails closed on missing, malformed, broader-than-approved, write-capable, or
unsafe declarations. It uses sanitized replay fixtures only and must not be
represented as live staging, production, recovery, cluster, HolmesGPT, or model
validation.

## Context Boundary

Operational context must remain separate from runtime state and execution
authority.

Context may store sanitized summaries, evidence references, operator intent,
and explicit approval records. It must not store secrets, raw credentials, real
Telegram chat IDs, Terraform state, local tfvars, raw plans, or private
operator notes.

## Delivery Safeguards

Experiment 06 validated durable safeguards for a reviewable application
migration workflow. The public evidence is summarized in the
[Online Boutique Compose-to-Aspire case study](case-studies/experiment-06-online-boutique-compose-to-aspire.md).

- GitHub access was repository-scoped for reviewable delivery work.
- Issues, branches, pull requests, comments, and merge history provided durable
  delivery evidence.
- Automatic merge remained disabled.
- Architecture approval, merge approval, and skill application required
  explicit human decisions.
- Credentials and tokens were excluded from source, documentation, evidence,
  and reusable skill content.
- Skill Workshop used a proposal-first lifecycle before human Apply.
- The application migration did not mutate GCP or Terraform resources.
- Validation was designed to prevent unrelated runtime resources from
  producing false-positive evidence.

Those safeguards remain useful independently of the runtime or executor chosen
for a future implementation.

## Telegram Boundary

The Telegram operator channel is status-only. Supported commands are `/status`,
`/health`, `/whoami`, and `/help`.

Telegram messages are observation inputs only. They are not approval signals and
must not authorize mutation, remediation, Terraform actions, shell execution,
GitHub write actions, incident workflows, capability expansion, or merge.
