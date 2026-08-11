# Architecture

AI Operations Platform is a GCP-first, AI-native operations control plane for
human-reviewed software engineering, DevOps, SRE, Platform Engineering,
Infrastructure as Code, FinOps, security, and cloud operations work.

The accepted architecture direction separates the communication gateway,
control plane, durable state, executor adapter, executor implementation,
validation/evidence flow, and human review boundary. It does not select,
recommend, rank, or compare a replacement framework.

## Target Architecture

```text
Operator / Interface
  |
  v
Communication Gateway
  |
  v
AI Operations Control Plane
  |-- task identity and lifecycle
  |-- attempt identity and lifecycle
  |-- executor selection and assignment
  |-- required, declared, and verified capabilities
  |-- approval gates and audit events
  |-- dispatch, timeout, recovery, and stale-attempt handling
  |-- validation and evidence references
  `-- final review and closeout
  |
  v
Durable Task / Attempt State
  |
  v
Executor Adapter / Capability Handshake
  |
  v
Replaceable Executor
  |
  v
Target Platform / Repository / Tooling
  |
  v
Validation / Evidence
  |
  v
Human Review / GitHub Audit
```

## Current Foundation

The GCP runtime foundation lives in `gcp/stateful-agent-runtime/`.

It provides:

- private Compute Engine VM runtime with no public VM IP
- preserved Persistent Disk for private runtime state
- Terraform-managed infrastructure
- runtime secrets loaded from Secret Manager
- systemd-managed OpenClaw service
- optional service-state exporter wiring
- optional Telegram status-only adapter wiring

The context lifecycle foundation lives in `platform/context/`. It separates
durable runtime state from reviewable operational context, summaries, evidence
references, approvals, and forbidden data.

Implemented fact: the current Stateful VM foundation includes a
systemd-managed OpenClaw runtime. Accepted evidence preserves this bounded
runtime foundation and historical application-modernization use. ADR 0001
separately records that the evaluated OpenClaw/DevClaw architecture was not
selected as the primary orchestration foundation.

## Control-Plane Responsibilities

The AI Operations control plane owns or coordinates:

- task identity and lifecycle
- attempt identity and lifecycle
- executor selection and assignment
- capability requirements, declarations, and verification
- human approvals and audit events
- dispatch to executor adapters
- execution and validation state
- result state
- evidence and GitHub references
- timeout, recovery, and stale-attempt handling
- final review and closeout

Capabilities must be declared and verified before an attempt becomes active. If
a required capability is missing, ambiguous, or unverifiable, the control plane
fails closed instead of dispatching the attempt.

## Gateway Boundary

Communication gateways handle request intake, operator interaction,
communication, status presentation, notifications, approval collection, and
optional access to an interactive runtime.

A gateway can host or connect to an executor in some deployments, but the
platform architecture must not depend on that coupling. Gateway health,
operator reachability, or interactive session availability is not proof of
executor readiness.

## Executor Boundary

Executors are replaceable implementation choices behind an adapter contract.
The control plane must not rely on a single agent runtime owning
communication, orchestration, execution, state, and recovery at the same time.

Executors perform bounded engineering or operations tasks, use only authorized
repository, runtime, filesystem, network, API, and tooling access, perform
required validation, and return structured execution results and evidence.

Logical architect, developer, tester-validator, and human-reviewer
responsibilities remain useful, but they are responsibilities in the workflow,
not fixed long-running agent processes.

The first implementation should use a simpler sequential workflow. Parallel or
multi-agent execution can be evaluated later after the control-plane state,
adapter contract, capability handshake, and recovery model are stable.

## GitHub Boundary

GitHub issues, branches, pull requests, comments, commits, reviews, and merge
commits remain durable workflow evidence and review boundaries. GitHub is not
required to be the platform's internal execution-state engine.

## Candidate Runtime Status

OpenClaw may remain an optional communication gateway or interactive runtime
candidate after separate operational validation. DevClaw remains useful as
workflow research and a source of governance concepts, but it is not a required
primary dependency.

Other runtime, agent, control-plane, or workflow frameworks are candidates or
hypotheses until a separate evidence-backed selection is accepted.

## Validated Application-Delivery Pattern

Experiment 06 validated a bounded application-migration workflow layered on top
of the runtime foundation. The workflow is documented in the
[Online Boutique Compose-to-Aspire case study](case-studies/experiment-06-online-boutique-compose-to-aspire.md).

That migration result remains valid, including architecture-first planning,
human approval gates, independent validation, GitHub auditability, and governed
knowledge promotion. It does not select the evaluated OpenClaw/DevClaw
architecture as the primary orchestrator and does not establish restart or
reboot recovery beyond the accepted evidence.

## Design Boundaries

- Runtime state and operational context are separate concerns.
- Durable task and attempt state belongs outside ephemeral agent sessions.
- Platform context is explicit, reviewable, bounded, and non-secret.
- Telegram status-only interactions are observation inputs, not approval
  signals.
- Human approvals and audit are control-plane responsibilities.
- Destructive actions require explicit human approval.
- No secrets, raw credentials, real chat IDs, Terraform state, local tfvars, or
  raw plans belong in tracked context.
