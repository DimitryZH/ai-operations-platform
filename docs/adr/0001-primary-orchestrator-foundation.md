# ADR 0001: Primary Orchestrator Foundation

## Status

Proposed.

This ADR records a proposed architecture decision for human review in issue
#13. It becomes accepted only through the normal pull request review and merge
process.

## Context

The OpenClaw/DevClaw experiment produced two independent outcomes that must
remain separate.

Application-modernization outcome: The migration workflow and completed
migrations remain valid. Experiment 06, Experiment 07, and the Experiment 08B
Aspire migration produced useful implementation, validation, review, and
closeout results that remain part of the platform evidence base (EXP06-01,
EXP06-02, EXP07-01, EXP07-02, EXP08-02, CODEX-01, CODEX-02).

Orchestration-platform outcome: The evaluated OpenClaw/DevClaw architecture did
not meet the AI Operations Platform requirements for deterministic execution,
durable external task state, bounded recovery, capability certainty,
observability, and operational efficiency as the primary orchestrator
(RECOVERY-01, RECOVERY-02, SECURITY-01, CODEX-01, CODEX-02,
DECISION-INPUT-01).

The accepted issue #9 evidence package and issue #10 evaluation are the
authoritative evidence basis for this decision. This ADR does not reopen
unrestricted primary evidence discovery and does not create new Evidence IDs.

## Decision

Do not select the evaluated OpenClaw/DevClaw architecture as the primary
orchestration foundation for the AI Operations Platform.

The platform direction is:

- OpenClaw may remain an optional communication gateway or interactive runtime,
  subject to separate operational validation.
- DevClaw remains useful as workflow research and a source of governance
  concepts, but is not a required primary-orchestration dependency.
- Durable task and attempt state must exist outside ephemeral agent sessions.
- Executor implementations must be replaceable.
- Capability negotiation must occur before an execution attempt becomes active.
- GitHub-native auditability and explicit human approval gates remain platform
  requirements.
- Logical architect, developer, and tester roles remain useful independently of
  the worker runtime.
- The first platform implementation should use a simpler sequential
  control-plane workflow.
- The platform remains GCP-first without coupling the architecture to one agent
  runtime.

This ADR does not select, rank, or compare a replacement framework. Replacement
framework selection remains a separate research task.

## Decision Drivers

- Deterministic execution readiness must be proven before active execution.
- Capability detection must explicitly cover filesystem, Git, Docker/runtime,
  API, validation, branch, and pull request operations.
- Durable task and attempt state must be independent from ephemeral worker
  sessions.
- Recovery must be bounded across restart, reboot, stale state, failed
  attempts, and partial capability recovery.
- Attempt lifecycle state must distinguish dispatch, session creation, command
  execution, repository mutation, validation, push, PR update, and completion.
- Observability must show task, attempt, executor, capability, validation,
  approval, and GitHub state.
- Security boundaries must preserve least privilege while failing closed before
  work begins.
- Human approval remains required for architecture, mutation, merge, and skill
  application decisions.
- GitHub issues, pull requests, comments, commits, reviews, and merge commits
  remain durable audit evidence.
- Compatibility burden must be bounded rather than allowed to dominate routine
  platform operation.
- Operator intervention and time/token burden must be controlled, even where
  exact measurements are not yet available.
- Executors must be replaceable so the control plane is not coupled to one
  worker runtime.
- The platform must remain compatible with GCP-first private runtime
  constraints.

## Evidence Basis

Evidence-backed fact: GitHub provided durable issue, branch, PR, commit, review,
merge, and closeout state across the evaluated workstreams (GITHUB-01,
EXP06-01, EXP06-02, EXP07-01, EXP07-02, EXP08-02, CODEX-02).

Evidence-backed fact: Human approval gates, least-privilege boundaries,
architecture-first workflow, logical role separation, and governed knowledge
reuse produced useful platform patterns (VISION-02, GOVERNANCE-01, WORKER-01,
KNOWLEDGE-01, KNOWLEDGE-02).

Evidence-backed fact: Gateway validation, plugin loading, dispatch acceptance,
session creation, command execution, repository mutation, validation, push, PR
update, and completion are separate readiness states (RUNTIME-01, RECOVERY-01,
SECURITY-01).

Evidence-backed fact: The accepted evidence did not contain direct successful
managed-service restart persistence validation or VM reboot persistence
validation artifacts (INFRA-03, INFRA-04).

Evidence-backed fact: A narrow AppArmor/userns recovery enabled a minimal
sandboxed command, but did not establish full developer workflow capability
(RECOVERY-02, SECURITY-01).

Engineering inference: A primary platform control plane should own durable
task, attempt, executor, capability, approval, and GitHub state separately from
any worker runtime (GITHUB-01, RUNTIME-02, SECURITY-01).

Decision input: The accepted orchestration evaluation recommends against
selecting the evaluated OpenClaw/DevClaw architecture as the primary
orchestrator while preserving reusable communication, governance, audit, role,
validation, and knowledge patterns (CODEX-02, DECISION-INPUT-01).

Insufficient evidence: Exact infrastructure cost, operator hours, recovery
hours, token counts, dollar costs, direct-Codex time advantage, and controlled
worker/direct runtime parity were not measured in the accepted evidence
(CODEX-01, CODEX-02, DECISION-INPUT-01).

## Alternatives Considered

Retain the evaluated OpenClaw/DevClaw architecture as the primary orchestrator.
This was rejected for the evaluated architecture because Gateway and plugin
readiness did not prove execution readiness, worker/session state was not
authoritative durable task state, recovery remained too broad for routine
operation, and operational burden was a decision input against primary use
(RECOVERY-01, RECOVERY-02, SECURITY-01, DECISION-INPUT-01).

Retain OpenClaw/DevClaw only in narrower optional roles. This remains allowed.
OpenClaw can be reconsidered as a communication gateway or interactive runtime
after separate operational validation. DevClaw can continue informing workflow
research and governance concepts without being a required primary dependency
(RUNTIME-01, AUTH-01, WORKER-01, GOVERNANCE-01).

Move to a simpler sequential control-plane model with replaceable executors.
This is the selected architectural pattern for the first platform
implementation. It preserves GitHub auditability, human approval, logical
roles, durable external state, explicit capability negotiation, and executor
replaceability without selecting the concrete replacement technology in this
ADR (VISION-02, GITHUB-01, GOVERNANCE-01, CODEX-02).

## Consequences

Positive consequences:

- The platform is less coupled to one worker runtime.
- Gateway, control-plane, executor, state, and recovery concerns become easier
  to separate.
- Durable task and attempt state ownership becomes explicit.
- Capability handshakes become a required boundary before work begins.
- Recovery semantics become simpler to validate and reason about.
- GitHub auditability and human approval gates remain first-class controls.
- Executor replacement becomes a supported architecture property.
- Acceptance testing can target observable task and capability boundaries.

Costs and tradeoffs:

- A new control-plane implementation is still required.
- Executor adapter contracts must be defined.
- Durable task and attempt state needs a concrete persistence design.
- Capability negotiation adds explicit preflight work.
- Some OpenClaw/DevClaw functionality becomes optional rather than
  foundational.
- Replacement-framework research remains unresolved.

## Retained Patterns

- Architecture-first planning.
- Immutable accepted baselines.
- Logical architect, developer, and tester roles.
- GitHub issues and pull requests as durable workflow evidence.
- Explicit human approval gates.
- Least-privilege GitHub integration.
- Negative validation and recovery validation where actually evidenced.
- Evidence-based human review.
- Governed reusable knowledge promotion.
- Replaceable execution engines.
- GCP-private runtime patterns where useful.

## Rejected Assumptions

- Gateway health proves executor readiness.
- Plugin loading proves engineering-task capability.
- Dispatch acceptance proves execution.
- Session creation proves filesystem, Git, Docker/runtime, API, validation,
  push, PR update, or completion capability.
- Worker session state is authoritative durable task state.
- A narrow sandbox recovery proves complete workflow readiness.
- Compatibility overlays can grow without a bounded maintenance budget.
- One agent runtime should own communication, orchestration, execution, state,
  and recovery simultaneously.
- Direct Codex completion proves independent Docker/runtime parity with the
  worker environment.
- The lack of selected primary-orchestrator fit invalidates successful
  Experiments 06, 07, or the valid Experiment 08B migration.

## Risks and Limitations

- This decision is bounded to the evaluated architecture, versions,
  integration, environment, and platform requirements.
- It is not a universal rejection of OpenClaw or DevClaw.
- Some attribution remains unresolved between product behavior, integration
  behavior, compatibility overlay, sandbox, host configuration, permissions,
  and environment.
- Restart and reboot models are documented, but accepted evidence does not
  include direct successful persistence validation artifacts.
- Worker execution and direct Codex execution were compared operationally, with
  no proof of identical environments or identical starting conditions.
- Exact cost, time, token, and operator-intervention measurements were not
  recorded.
- The next orchestrator implementation and acceptance benchmark remain future
  work.

## Revisit Criteria

This decision can be revisited for a candidate architecture that demonstrates,
through a reusable acceptance benchmark:

- deterministic execution;
- explicit capability negotiation;
- restart and reboot recovery;
- stale-attempt recovery;
- durable external task and attempt state;
- bounded compatibility burden;
- sufficient task, attempt, executor, and capability observability;
- least privilege without hidden capability ambiguity;
- acceptable time, token, and operator-intervention burden;
- repeatable GitHub auditability;
- explicit human approval boundaries.

These criteria are product-neutral and do not permanently reject any specific
runtime or framework.

## References

- Umbrella issue #8:
  https://github.com/DimitryZH/ai-operations-platform/issues/8
- Evidence issue #9:
  https://github.com/DimitryZH/ai-operations-platform/issues/9
- Evidence PR #11:
  https://github.com/DimitryZH/ai-operations-platform/pull/11
- Evidence PR #11 merge commit:
  `ac1845753f2cba632d8c5178d701e38ca4eeaf46`
- Evaluation issue #10:
  https://github.com/DimitryZH/ai-operations-platform/issues/10
- Evaluation PR #12:
  https://github.com/DimitryZH/ai-operations-platform/pull/12
- Evaluation PR #12 merge commit:
  `cff15dbd2d94631858b3f09aebff692313b87e37`
- ADR issue #13:
  https://github.com/DimitryZH/ai-operations-platform/issues/13
- Accepted evidence index:
  `docs/research/openclaw-devclaw/evidence-index.md`
- Accepted experiment chronology:
  `docs/research/openclaw-devclaw/experiment-chronology.md`
- Accepted orchestration evaluation:
  `docs/research/openclaw-devclaw/orchestration-evaluation.md`
