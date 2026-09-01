# Roadmap

This repository is building a GCP-first, AI-native operations control plane.
Its first deliverable is a bounded, sequential, read-only, GitHub-auditable SRE
investigation vertical slice for the existing
[SRE Platform](https://github.com/DimitryZH/sre-platform) staging scenario.

The SRE Platform owns its environments, controlled failures, rollout behavior,
SLO validation, rollback, recovery, and operational evidence. AI Operations
Platform owns investigation request, task, attempt, capability, executor,
result, evidence, publication, and human-review state. Neither repository may
claim the other repository's incomplete work as complete.

## Completed Foundations

- GCP private Stateful VM runtime foundation, Persistent Disk state model,
  IAP-only operator access, Secret Manager runtime integration, and
  systemd-managed OpenClaw runtime documentation.
- OpenClaw/DevClaw evidence consolidation, ADR 0001, and the product-neutral
  orchestrator acceptance benchmark specification.
- The first SRE investigation contract for the repository-verified staging
  scenario: `online-shop-stage`, `frontend`, `online-shop-stage` Argo CD
  application, and read-only evidence collection.
- ADR 0002, which accepts the minimum first-MVP control-plane architecture:
  Python 3.13, FastAPI, Pydantic, PostgreSQL, SQLAlchemy, Alembic, a
  database-backed sequential dispatcher, a product-neutral executor adapter,
  and a defined GCP target.

## Implemented And Validated Locally

The local control-plane core is implemented and covered by automated tests. It
is not a deployed MVP or a live SRE Platform investigation.

| Capability | Implemented local behavior | Validation boundary |
| --- | --- | --- |
| Runnable control-plane skeleton | Python 3.13 FastAPI API, Pydantic schemas, PostgreSQL persistence metadata, Alembic migrations, health/readiness endpoints, and deterministic fake executor. | Local tests and GitHub Actions. |
| Deterministic fake workflow | Request intake persists `READY`; a bounded fake execution produces a schema-valid result and stops at `AWAITING_HUMAN_REVIEW`; explicit human completion, rejection, or follow-up is recorded. | Fake executor only; no external system is contacted. |
| Durable request and retry history | Request and fingerprint deduplication, explicit operator-controlled retry, new attempt identity per retry, retained attempts, results, reviews, and transitions. | No automatic retry. Terminal tasks and duplicate retry decisions cannot create another attempt. |
| Sequential dispatch and reconciliation safety | One database-backed dispatcher tick first reconciles an expired or ambiguous attempt through durable identity and status lookup, then claims at most one eligible task through a durable global lease and monotonic fencing token. Database locks are released before fake-executor calls. | PostgreSQL integration tests cover competing ticks, reconciliation recovery, active attempts, and stale fencing tokens. |
| Fail-closed capability path | Capability checks are recorded before dispatch; rejected or exceptional checks leave a durable audit trail and retry-eligible task state as defined by the local workflow. | Fake executor capabilities only. |
| Durable evidence and publication audit | Schema-valid results produce sanitized, SHA-256-addressed evidence packages. Artifact metadata, logical publication intents, and append-only publication outcomes are durable and visible through the task API. | The local evidence adapter and fake publisher remain defaults. Cloud Storage and live publication are not deployed by the local core. |
| Bounded GitHub publisher | A product-neutral GitHub publisher validates exact target identity, pagination, response receipts, canonical idempotency markers, redirects, and retryable versus terminal outcomes. | The publisher is opt-in; its live smoke is explicitly gated and is not a default workflow action. GitHub remains an audit surface, never transactional state. |
| Bounded HolmesGPT executor prototype | A product-neutral non-streaming HTTP adapter validates endpoint, capabilities, canonical dispatch identity, JSON response media type, result schema, and reconciliation identity. | `PROTOTYPE_REQUIRED`: fake execution remains the default. No HolmesGPT deployment, authentication, model invocation, runtime RBAC, Prometheus/log enforcement, or live investigation is claimed. |
| GCP deployment foundation | Terraform and a non-root Python 3.13 container define private Cloud Run, Cloud SQL PostgreSQL, Cloud Storage, Secret Manager containers, scheduler OIDC, least-privilege IAM, structured logging, monitoring, and a controlled migration job. The bootstrap phase has been applied in `ai-operations-platform-507220` with remote GCS state, private networking, private-IP Cloud SQL, evidence storage, service accounts, bounded IAM, logging, monitoring, and empty Secret Manager containers. | Bootstrap only: no Cloud Run service, migration job, Scheduler job, secret version, image publication, runtime configuration, live executor, GitHub publisher, Kubernetes access, or SRE Platform mutation has occurred. Fake adapters remain locked defaults. |
| CI validation | GitHub Actions uses Python 3.13, PostgreSQL 16, Alembic migrations, and `SRE_CONTROL_PLANE_TEST_DATABASE_URL`. | The latest accepted control-plane run completed `157 passed, 1 skipped`; PostgreSQL integration tests ran, and the only skip was an opt-in live smoke test. |

The local core intentionally does not deploy a real investigator, Kubernetes,
Prometheus, logs, GitOps, GitHub publication, evidence storage, or GCP
resources. It does not implement automatic retry, general timeout/cancellation,
or a live SRE Platform investigation.

## First MVP Completion Boundary

The first SRE Investigation MVP is complete only when a GitHub-auditable,
read-only vertical slice has demonstrated all of the following against the
approved SRE Platform staging scenario:

1. a bounded operator request or normalized event creates durable task and
   attempt state;
2. restart reconciliation safely resolves unfinished or stale attempts before
   further dispatch;
3. a selected prototype executor passes fail-closed capability verification
   for the approved read-only scope;
4. the executor returns schema-valid findings with durable evidence references;
5. the control plane publishes durable GitHub references and records explicit
   human review and closeout;
6. the minimum GCP deployment runs the bounded sequential workflow without
   public ingress;
7. the SRE Platform-owned staging demonstration supplies real, read-only
   investigation evidence and leaves recovery ownership with SRE Platform.

This boundary does not include autonomous remediation, production rollout,
production SLO validation, automatic merge, parallel execution, or a broad
incident-management platform.

## Remaining First MVP Sequence

The remaining work is intentionally ordered and bounded:

1. **Prepare reviewed runtime deployment**: use the applied bootstrap
   foundation only after a new reviewed plan supplies an immutable image digest,
   out-of-band database secret version, controlled migration job path,
   authenticated internal readiness check, and paused Scheduler runtime plan.
2. **Bind reviewed production adapters**: configure bounded evidence storage
   and GitHub publication without changing the database source of truth or
   enabling default live writes.
3. **One real read-only executor prototype**: verify one product-neutral
   candidate's capabilities fail closed for the approved scope. HolmesGPT is
   not selected by the local adapter prototype.
4. **Complete SRE Platform staging demonstration**: run the approved
   SRE-owned controlled scenario and collect only permitted read-only evidence.
5. **Orchestrator benchmark and portfolio closeout**: execute the accepted
   benchmark against the integrated candidate architecture and publish only
   evidence-supported results.

The milestone for this sequence is **First SRE Investigation MVP**. Future
implementation issues will be created only as the sequence is refined; this
roadmap does not create or imply a broad backlog.

## Candidate And Architecture Status

ADR 0002 selects the minimum control-plane architecture for the first MVP. It
does not select a primary orchestrator, an AI model, or a final investigator.

HolmesGPT remains `PROTOTYPE_REQUIRED`: it is a credible read-only candidate,
not an accepted executor. Its deployment and invocation boundary, PromQL and
logs enforcement, workload-bounded access, and effective HTTP API protection
still require a fail-closed prototype validation. The current fake executor is
not evidence that HolmesGPT or another real executor is suitable.

The accepted orchestrator benchmark has not been executed. No benchmark
measurement, scorecard result, replacement-framework selection, or final
orchestrator decision is claimed by this roadmap.

## Deferred Until After The First MVP

- parallel or multi-agent execution
- autonomous remediation and write-capable actions
- multiple executor types
- broad incident-management automation and production-scale alert routing
- automatic retry, timeout, cancellation, and long-running workflow expansion
- automatic merge and write-capable ChatOps
- multi-cloud abstraction
- additional FinOps or secure-delivery use cases

## Explicitly Out Of Scope For Now

- changing the accepted first SRE scenario or its read-only boundary
- treating the fake executor as a real investigation integration
- claiming a GCP deployment, live staging investigation, or SRE Platform
  production validation before direct evidence exists
- selecting HolmesGPT or another investigator before prototype validation
- modifying the SRE Platform repository from this workstream
- accessing a cluster, GCP, or other cloud resources for roadmap work
