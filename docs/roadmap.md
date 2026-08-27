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
| Sequential dispatch safety | One database-backed dispatcher tick claims at most one eligible task through a durable global lease, monotonic fencing token, active-attempt exclusion, and a short database claim transaction released before the fake executor call. | PostgreSQL integration tests cover competing ticks, active attempts, and stale fencing tokens. |
| Fail-closed capability path | Capability checks are recorded before dispatch; rejected or exceptional checks leave a durable audit trail and retry-eligible task state as defined by the local workflow. | Fake executor capabilities only. |
| CI validation | GitHub Actions uses Python 3.13, PostgreSQL 16, Alembic migrations, and `SRE_CONTROL_PLANE_TEST_DATABASE_URL`. | Latest accepted control-plane CI run completed `41 passed` with no skipped tests. |

The local core intentionally does not implement a real investigator, Kubernetes,
Prometheus, logs, GitOps, GitHub publication, evidence storage, GCP deployment,
restart reconciliation, automatic retry, timeout, cancellation, or a live SRE
Platform investigation.

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

1. **Restart reconciliation and stale-attempt recovery**: reconcile durable
   lease, heartbeat, invocation, and adapter-observable state before dispatch;
   never automatically retry an ambiguous attempt.
2. **Durable evidence and GitHub publication**: persist evidence references,
   publish bounded findings and links to GitHub, and retain the publication
   audit trail without treating GitHub as transactional workflow state.
3. **One real read-only executor prototype**: implement one product-neutral
   adapter behind the existing boundary and verify its capabilities fail closed.
4. **Minimum GCP deployment**: deploy the accepted ADR 0002 target with private
   exposure, bounded orchestration ticks, least privilege, and no public ingress.
5. **Complete SRE Platform staging demonstration**: run the approved
   SRE-owned controlled scenario and collect only permitted read-only evidence.
6. **Orchestrator benchmark and portfolio closeout**: execute the accepted
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
