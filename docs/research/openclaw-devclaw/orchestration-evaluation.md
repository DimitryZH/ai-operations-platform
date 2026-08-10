# OpenClaw/DevClaw Orchestration Evaluation

## 1. Executive Summary

Evidence-backed finding: The evaluated OpenClaw/DevClaw architecture did not
provide sufficient deterministic worker execution, durable external task state,
bounded recovery, and operational efficiency to serve as the primary
orchestrator for the AI Operations Platform (RECOVERY-01, RECOVERY-02,
SECURITY-01, CODEX-01, CODEX-02, DECISION-INPUT-01).

The evaluation also preserves meaningful successes. The private GCP runtime
foundation, loopback Gateway model, IAP operator boundary, OAuth-oriented model
integration, scoped GitHub workflow state, human approval gates, architecture
first execution model, logical roles, immutable baselines, validation method,
and governed knowledge reuse remain useful platform inputs (VISION-01,
VISION-02, INFRA-01, INFRA-02, RUNTIME-01, AUTH-01, GITHUB-01, GOVERNANCE-01,
WORKER-01, KNOWLEDGE-01, EXP06-01, EXP06-02, EXP07-01, EXP07-02).

Engineering inference: OpenClaw remains a viable candidate for communication
gateway or interactive runtime use, and DevClaw remains useful as workflow
research. The evaluated worker-orchestration architecture requires redesign
before it can be treated as a primary platform control plane (RUNTIME-01,
COMPAT-01, RECOVERY-01, RECOVERY-02, SECURITY-01, CODEX-02).

Recommendation: Subject to a later Architecture Decision Record, do not select
the evaluated OpenClaw/DevClaw architecture as the AI Operations Platform
primary orchestration foundation. Retain GitHub-native auditability, explicit
human approval gates, logical role separation, durable state outside ephemeral
agent sessions, replaceable executors, and pre-execution capability negotiation
(VISION-02, GITHUB-01, GOVERNANCE-01, WORKER-01, CODEX-02,
DECISION-INPUT-01).

## 2. Research Question

Did the evaluated OpenClaw/DevClaw architecture provide sufficient reliability,
recoverability, security, auditability, state consistency, execution capability,
and operational efficiency to serve as the primary orchestrator for the AI
Operations Platform?

Answer: No. The accepted evidence supports useful communication, workflow, and
governance patterns, but it does not support selecting the evaluated
OpenClaw/DevClaw worker architecture as the primary orchestrator. The decisive
gaps are execution readiness, capability detection, recovery scope, durable task
state, observability, and operator/token efficiency (RECOVERY-01, RECOVERY-02,
SECURITY-01, CODEX-01, CODEX-02, DECISION-INPUT-01).

## 3. Scope and Evaluated Versions

This report evaluates the OpenClaw/DevClaw architecture captured by the accepted
issue #9 evidence package and merged through PR #11 at merge commit
`ac1845753f2cba632d8c5178d701e38ca4eeaf46` (GITHUB-01).

Evaluated components:

- OpenClaw communication gateway, interactive runtime, and engineering-task
  gateway (RUNTIME-01, AUTH-01).
- DevClaw role model, workflow model, task-state model, worker runtime, and
  recovery model (WORKER-01, GOVERNANCE-01, RECOVERY-01, RECOVERY-02).
- Compatibility overlay for OpenClaw `2026.7.1`, DevClaw `1.6.10`, and
  compatibility revision `aiops-1` (RUNTIME-01, COMPAT-01).
- Managed private GCP DevBox and runtime foundation (INFRA-01, INFRA-02,
  INFRA-03, INFRA-04).
- OpenAI OAuth/model integration and GitHub integration (AUTH-01, GITHUB-01).
- Skill Workshop and governed knowledge reuse (KNOWLEDGE-01, KNOWLEDGE-02).
- Direct Codex as an executor used after explicit human approval in Experiment
  08B (CODEX-01, CODEX-02).

This report does not create an ADR, select a replacement orchestrator, update
the Vision, or modify runtime, infrastructure, application, or skill files.

## 4. Environment and Architecture

Evidence-backed finding: The evaluated foundation used a private GCP runtime
model with preserved disk, IAP-only operator access, Secret Manager boundaries,
systemd-owned service lifecycle, and a status-only Telegram channel without
approval or execution authority (INFRA-01, INFRA-02, INFRA-03).

Evidence-backed finding: Gateway validation expected a loopback listener, RPC
health, plugin loading, pinned OpenClaw and DevClaw versions, disabled
heartbeat, sequential project execution, restricted token files, OpenAI OAuth
mode where enabled, and absence of common unsafe credential environment
variables (RUNTIME-01, AUTH-01, GOVERNANCE-02).

Unresolved question: The accepted evidence documents a managed-service restart
model and a disk-backed reboot state model, but it found no direct successful
PASS artifact for managed-service restart persistence or VM reboot persistence
validation (INFRA-03, INFRA-04).

## 5. Evaluation Method

The method is evidence-index driven. The accepted evidence index and chronology
are treated as the primary evidence map, and this report references their stable
Evidence IDs rather than reopening unrestricted primary evidence
(GITHUB-01).

Evidence handling:

- Direct evidence is used for committed files, GitHub state, merge commits,
  validation artifacts, and human review/closeout facts.
- Reported evidence is used where an agent or operator report records a result
  but is not independently complete.
- Inference is labeled where the conclusion combines accepted evidence items or
  interprets a readiness boundary.
- Recommendation is labeled separately from evidence-backed findings.
- Unresolved questions are preserved where the evidence package is incomplete
  or attribution is not settled.

The readiness model is taken from the accepted evidence package:

1. Infrastructure available
2. Gateway process running
3. Gateway listener available
4. RPC ready
5. Plugin loaded
6. Dispatch accepted
7. Worker session created
8. Command executed
9. Repository read completed
10. Repository mutation completed
11. Validation completed
12. Commit created
13. Branch pushed
14. Pull request updated
15. Task completed

Control-plane readiness does not prove execution readiness. Dispatch acceptance
does not prove command execution. Session existence does not prove filesystem,
Git, Docker, API, validation, push, PR, or completion capability. Worker
identity is not authoritative durable task state (RUNTIME-01, RECOVERY-01,
SECURITY-01).

## 6. Successful Capabilities

Evidence-backed finding: The private runtime architecture, preserved disk
model, IAP operator boundary, systemd-managed service model, and loopback
Gateway exposure are valid platform inputs for a secure assisted-operations
environment (INFRA-01, INFRA-02, INFRA-03, RUNTIME-01).

Evidence-backed finding: OpenAI OAuth/model integration and credential hygiene
were part of the validation contract, with restricted token handling and no
unsafe credential environment variables expected when enabled (AUTH-01,
RUNTIME-01).

Evidence-backed finding: GitHub issues, comments, pull requests, branches,
commits, reviews, and merge commits provided durable audit state across the
experiment series (GITHUB-01, EXP06-01, EXP06-02, EXP07-01, EXP07-02,
EXP08-01, EXP08-02).

Evidence-backed finding: Human approval gates, architecture-first planning,
logical architect/developer/tester roles, sequential workflow governance, and
immutable accepted baselines were demonstrated and should be retained
(VISION-02, WORKER-01, GOVERNANCE-01, GOVERNANCE-02, EXP06-01, EXP07-01,
EXP07-02, EXP08-01, EXP08-02).

Evidence-backed finding: Functional validation, negative validation, recovery
validation where actually evidenced, and governed knowledge reuse produced
successful outcomes in Experiments 06 and 07 and supported the valid Experiment
08 migration result (KNOWLEDGE-01, KNOWLEDGE-02, EXP06-01, EXP06-02,
EXP07-01, EXP07-02, EXP08-02, CODEX-01, CODEX-02).

Limitation: These successes do not prove later worker runtime reliability,
restart persistence validation, reboot persistence validation, full workflow
capability after narrow sandbox recovery, or primary-orchestrator suitability
(INFRA-03, INFRA-04, WORKER-01, RECOVERY-02, SECURITY-01).

## 7. Failure Taxonomy

Compatibility failures: DevClaw integration required a compatibility overlay
and a pinned 23-tool contract. That is a valid controlled integration pattern,
but the platform would inherit ongoing overlay maintenance and semantic
compatibility risk (RUNTIME-01, COMPAT-01). Impact: compatibility work is a
primary-orchestrator risk unless isolated behind replaceable executor adapters.

Worker lifecycle failures: Accepted evidence separated dispatch acceptance and
worker session records from command completion. Runtime evidence retained
dispatch, diagnosis, recovery, and direct completion trails, but worker state
did not consistently establish task completion capability (RUNTIME-02,
RECOVERY-01, SECURITY-01). Impact: session state was not reliable enough to be
authoritative platform task state.

Sandbox and namespace failures: A minimal read-only subagent smoke failed
before useful command execution with a Bubblewrap loopback namespace error.
A narrow AppArmor/userns recovery enabled a minimal sandboxed command, but did
not prove full developer workflow capability (RECOVERY-01, RECOVERY-02).
Impact: the architecture could report control-plane readiness while execution
remained unavailable.

Filesystem and Git failures: Later capability checking still found workflow
capability concerns, including an active Git-process boundary in the captured
run (SECURITY-01). Impact: repository mutation, commit, and branch update could
not be assumed from dispatch or session creation.

Docker and runtime-access failures: The issue #10 failure taxonomy requires
separating host capability from worker capability. The accepted evidence
supports that capability inheritance was not established by minimal command
execution or Gateway readiness (RECOVERY-01, RECOVERY-02, SECURITY-01). Impact:
Docker/runtime access must be negotiated before activating an execution
attempt.

State-consistency failures: GitHub state was durable and authoritative, while
worker/session state was not sufficient proof of execution or completion
(GITHUB-01, RUNTIME-02, SECURITY-01). Impact: durable task state must live
outside ephemeral worker sessions.

Dispatch and readiness ambiguity: Gateway health, plugin loading, dispatch
acceptance, session creation, command execution, repository mutation,
validation, push, PR update, and completion are separate readiness states
(RUNTIME-01, RECOVERY-01, SECURITY-01). Impact: primary orchestrator design must
prove execution readiness, not only control-plane readiness.

Recovery-workflow failures: Recovery required diagnosis, bounded host changes,
and follow-up capability checks. The narrow recovery enabled a minimal command
but did not establish full workflow capability (RECOVERY-01, RECOVERY-02,
SECURITY-01). Impact: recovery effort was too broad and fragile for routine
platform execution.

Observability gaps: The evidence package had to distinguish GitHub durable
state from worker records and agent-authored reports. Attempt ownership,
capability status, and stale/running/blocked distinctions were insufficient for
primary orchestration (GITHUB-01, RUNTIME-02, SECURITY-01). Impact:
observability must expose task, attempt, executor, and capability state.

Operational-efficiency failures: Experiment 08B required direct Codex
continuation under explicit human approval after worker/runtime concerns.
Accepted closeout recorded worker orchestration reliability and cost concerns
without making a precise benchmark claim (CODEX-01, CODEX-02,
DECISION-INPUT-01). Impact: compatibility and recovery overhead dominated the
engineering value for the evaluated architecture.

Attribution boundary: These failures should not all be attributed to OpenClaw
or DevClaw product defects. The evidence leaves some attribution unresolved
between product behavior, integration behavior, compatibility overlay, sandbox,
host configuration, permissions, and environment (RECOVERY-01, RECOVERY-02,
SECURITY-01).

## 8. Workflow and Governance Findings

Evidence-backed finding: GitHub-native workflow governance worked. Issues, PRs,
comments, branches, heads, merge commits, and closeout comments provided the
most durable audit trail (GITHUB-01, EXP06-01, EXP06-02, EXP07-01, EXP07-02,
EXP08-01, EXP08-02, CODEX-02).

Evidence-backed finding: Human gates and architecture-first execution helped
control risk and preserve reviewability across architecture, implementation,
testing, correction, merge, and skill-promotion stages (VISION-02,
GOVERNANCE-01, WORKER-01, KNOWLEDGE-01).

Engineering inference: The workflow model is stronger when decoupled from a
single worker runtime. The platform should retain governance and role
separation while allowing executor replacement (GOVERNANCE-01, WORKER-01,
CODEX-01, CODEX-02).

## 9. Runtime and Execution Findings

Evidence-backed finding: Gateway validation and plugin loading are useful
control-plane signals but do not prove worker execution. Minimal command
execution is also insufficient to prove repository mutation, validation, Git,
Docker, push, PR update, or task completion (RUNTIME-01, RECOVERY-01,
RECOVERY-02, SECURITY-01).

Evidence-backed finding: Experiment 08B was completed through direct Codex
under explicit human approval after worker use was prohibited for the
continuation. Final reports recorded PASS on the final PR head, while keeping
worker/direct execution as an operational comparison rather than a controlled
benchmark (CODEX-01, CODEX-02, EXP08-02).

Recommendation: Future execution attempts should not become active until the
executor has explicitly negotiated required filesystem, Git, Docker/runtime,
network/API, validation, branch, and PR capabilities (RECOVERY-01, RECOVERY-02,
SECURITY-01, CODEX-02).

## 10. State and Recovery Findings

Evidence-backed finding: The accepted evidence supports a documented
systemd-managed restart model and disk-backed reboot state model, but no direct
successful PASS artifact was found for managed-service restart persistence
validation or VM reboot persistence validation (INFRA-03, INFRA-04).

Evidence-backed finding: A narrow recovery made a minimal sandboxed command
pass, but did not establish full developer workflow capability (RECOVERY-02,
SECURITY-01).

Engineering inference: Primary platform state must be external, durable, and
attempt-aware. Worker session records can be evidence about an attempt, but
they cannot be the authoritative record of task state (GITHUB-01, RUNTIME-02,
SECURITY-01).

## 11. Security and Permission Findings

Evidence-backed finding: The evaluated security posture included private GCP
runtime boundaries, IAP-only operator access, status-only Telegram behavior,
restricted token files, OpenAI OAuth validation, controlled GitHub permissions,
and no automatic merge/remediation model (VISION-02, INFRA-01, INFRA-02,
AUTH-01, GITHUB-01).

Evidence-backed finding: Permission isolation also contributed to execution
uncertainty. Sandbox, namespace, and Git/process capability boundaries had to
be diagnosed before worker capability could be trusted (RECOVERY-01,
RECOVERY-02, SECURITY-01).

Recommendation: Preserve least privilege and human approval, but make
capability detection explicit so security boundaries fail closed before task
dispatch becomes an active implementation attempt (VISION-02, AUTH-01,
GOVERNANCE-01, SECURITY-01).

## 12. Observability Findings

Evidence-backed finding: GitHub provided durable workflow observability, but
Gateway health, plugin status, dispatch acceptance, and worker session records
were not enough to prove active execution or completion (GITHUB-01, RUNTIME-01,
RUNTIME-02, RECOVERY-01, SECURITY-01).

Engineering inference: A primary orchestrator needs first-class visibility into
task state, attempt state, executor identity, capability handshake results,
current command activity, repository mutation status, validation status, push
status, PR status, and human approval gates (GITHUB-01, GOVERNANCE-01,
SECURITY-01).

## 13. Operational Cost

Evidence-backed fact: The accepted evidence records the architecture and
runtime elements that would have cost implications, including a private GCP
runtime, preserved disk, IAP, systemd services, Secret Manager boundaries,
pinned OpenClaw/DevClaw versions, and a compatibility overlay (INFRA-01,
INFRA-02, INFRA-03, RUNTIME-01, COMPAT-01).

Evidence-backed fact: The accepted evidence does not record exact
infrastructure spend, operator hours, recovery hours, dollar costs, token
costs, or controlled wall-clock comparisons (CODEX-02, DECISION-INPUT-01).

Decision input: The accepted closeout and decision-input evidence supports a
qualitative burden concern: worker orchestration reliability and cost concerns
were significant enough to inform the recommendation against the evaluated
primary-orchestrator architecture (CODEX-02, DECISION-INPUT-01).

Engineering inference: Compatibility maintenance and recovery burden are
material platform risks because the integration depended on pinned versions, a
compatibility overlay, sandbox recovery, and follow-up capability checking
(RUNTIME-01, COMPAT-01, RECOVERY-01, RECOVERY-02, SECURITY-01). This is a
qualitative inference, not a measured cost total.

INSUFFICIENT EVIDENCE: Infrastructure cost magnitude cannot be classified from
architecture evidence alone. Operator time, recovery time, and opportunity cost
also cannot be quantified or assigned measured magnitude categories from the
accepted evidence.

## 14. Time and Token-Cost Assessment

Evidence-backed fact: The accepted package does not record exact token counts,
exact dollar costs, exact operator hours, or controlled wall-clock measurements
(CODEX-02, DECISION-INPUT-01).

Decision input: The accepted closeout preserves qualitative worker
orchestration reliability and cost concerns as architecture-decision input
(CODEX-02, DECISION-INPUT-01).

Engineering inference: The worker orchestration path carried a qualitative
time/token burden because accepted evidence records diagnostics, sandbox
failure, bounded recovery, capability concerns, and a later human-approved
direct Codex continuation (RECOVERY-01, RECOVERY-02, SECURITY-01, CODEX-01,
CODEX-02). This inference does not assign exact elapsed time, token count, or
performance ratio.

INSUFFICIENT EVIDENCE: The accepted evidence does not support claiming direct
Codex had a lower execution time. It supports successful final direct
completion reports, but not a measured time advantage over worker execution
(CODEX-01, CODEX-02).

INSUFFICIENT EVIDENCE: Token-cost magnitude remains unmeasured. The report may
use qualitative burden as decision input, but it does not assert exact totals,
ratios, or measured token-cost classes.

## 15. Worker Execution and Direct Codex Comparison

This is an operational comparison, not a controlled scientific benchmark. The
accepted evidence does not prove identical environments, identical permissions,
or identical starting conditions (CODEX-01, CODEX-02).

| Dimension | OpenClaw/DevClaw worker execution | Direct Codex execution |
| --- | --- | --- |
| Task scope | Used across earlier architecture/developer/tester workflows and Experiment 08 attempts (WORKER-01, EXP06-01, EXP07-01, EXP07-02, EXP08-02). | Used for final Experiment 08B continuation after explicit human approval (CODEX-01, CODEX-02). |
| Environment | Private runtime with Gateway, DevClaw plugin, compatibility overlay, sandbox, and worker sessions (INFRA-01, RUNTIME-01, COMPAT-01). | Direct Codex path under explicit no-worker constraint (CODEX-01). |
| Permissions | Intended least privilege and controlled GitHub/token handling, but worker capability was not guaranteed by dispatch/session state (AUTH-01, GITHUB-01, SECURITY-01). | Human-approved direct executor completed final validation/correction reports without OpenClaw/DevClaw workers (CODEX-01, CODEX-02). |
| Execution reliability | Successful earlier experiments exist, but later worker/runtime evidence exposed sandbox and capability blockers (WORKER-01, EXP06-01, EXP07-02, RECOVERY-01, SECURITY-01). | Final 08B reports recorded PASS on the final PR head and accepted closeout (CODEX-01, CODEX-02, EXP08-02). |
| Repository mutation | Not proven by dispatch or session creation; later capability concerns included Git-process boundaries (SECURITY-01). | Final deliverables were validated and merged through GitHub state (EXP08-02, CODEX-01, CODEX-02). |
| Docker/runtime access | Required explicit capability proof; not established by control-plane readiness (RECOVERY-01, RECOVERY-02, SECURITY-01). | Final direct completion reports indicate that the required validation path completed successfully, but the accepted evidence does not independently establish Docker/runtime capability parity with the worker environment (CODEX-01, CODEX-02). |
| Recovery burden | Decision-input evidence supports qualitative worker recovery burden: diagnosis and narrow recovery did not prove full workflow readiness (RECOVERY-01, RECOVERY-02, SECURITY-01, CODEX-02). | Direct Codex was used after explicit human approval and completed final reports; the accepted evidence does not measure comparative recovery time or prove environment parity (CODEX-01, CODEX-02). |
| Final deliverables | Earlier worker-supported experiments were successful, but evaluated primary-orchestrator suitability failed on later reliability and cost concerns (EXP06-01, EXP07-02, DECISION-INPUT-01). | Experiment 08B migration result remained technically valid and accepted (EXP08-02, CODEX-02). |

## 16. Component Scorecard

| Component | Rating | Evidence IDs | Rationale | Limitations | Platform-design consequence |
| --- | --- | --- | --- | --- | --- |
| OpenClaw communication gateway | INSUFFICIENT EVIDENCE | INFRA-02, RUNTIME-01, AUTH-01 | The accepted evidence supports the loopback Gateway design, status-only operator boundary, and validation contract. | It does not directly establish operational PASS for the communication-gateway capability. | Preserve the gateway as a candidate design pattern, but require operational validation before scoring it as passed. |
| OpenClaw interactive runtime | INSUFFICIENT EVIDENCE | RUNTIME-01, AUTH-01, RECOVERY-02 | The accepted evidence supports intended runtime checks and a narrow post-recovery minimal command path. | It does not directly establish operational PASS for interactive runtime usability across the evaluated role. | Preserve interactive runtime as a candidate role, but require direct usability validation before platform scoring. |
| OpenClaw engineering-task gateway | REQUIRES REDESIGN | RUNTIME-01, RECOVERY-01, SECURITY-01 | Control-plane readiness did not reliably imply command, repository, Git, Docker, validation, or PR capability. | Attribution across product, integration, sandbox, host, and permission layers is unresolved. | Redesign execution handshake and attempt state before primary use. |
| Managed Gateway lifecycle | INSUFFICIENT EVIDENCE | INFRA-03, INFRA-04 | The systemd restart model and disk-backed reboot model are documented. | No direct successful restart or reboot persistence PASS artifact was found. | Treat lifecycle model as design evidence until benchmarked. |
| Authentication/model integration | INSUFFICIENT EVIDENCE | AUTH-01, RUNTIME-01 | The accepted evidence supports the OAuth/model and credential-hygiene validation contract. | It does not directly establish operational PASS for authentication/model integration. | Retain OAuth and secret-hygiene requirements, but require operational auth/model validation before scoring the component as passed. |
| GitHub integration | PASS | GITHUB-01, GOVERNANCE-01, EXP06-01, EXP07-02, EXP08-02 | GitHub provided durable issues, comments, branches, PRs, heads, merge commits, and closeout state. | GitHub state does not make agent-authored reports independently true. | Keep GitHub-native auditability as a core platform control. |
| DevClaw role model | PASS WITH LIMITATIONS | WORKER-01, GOVERNANCE-01, EXP06-01, EXP07-02 | Logical architect/developer/tester separation worked as a governance concept. | It does not prove the worker runtime remained reliable later. | Retain logical roles independent of DevClaw workers. |
| DevClaw workflow model | PASS WITH LIMITATIONS | GOVERNANCE-01, GOVERNANCE-02, WORKER-01, KNOWLEDGE-01 | Architecture-first, human-gated, sequential workflow remains useful. | Sequential workflow controls do not prove execution capability. | Use a simpler sequential workflow as first implementation. |
| DevClaw task-state model | REQUIRES REDESIGN | RUNTIME-02, GITHUB-01, SECURITY-01 | Worker/session state was not authoritative compared with durable GitHub state. | Accepted evidence is summarized and does not expose raw session internals. | Put durable task and attempt state outside ephemeral sessions. |
| DevClaw worker execution | REQUIRES REDESIGN | RECOVERY-01, RECOVERY-02, SECURITY-01, CODEX-01 | Later worker execution hit sandbox/capability limits, and minimal recovery did not prove full workflow capability. | Earlier worker-supported experiments succeeded, so this is not a universal product failure claim. | Workers must be replaceable executors with preflight capability negotiation. |
| Capability detection | REQUIRES REDESIGN | RUNTIME-01, RECOVERY-01, RECOVERY-02, SECURITY-01 | Gateway/plugin readiness and dispatch/session records were insufficient capability proof. | Some root-cause attribution remains unresolved. | Require explicit filesystem, Git, Docker, API, validation, push, and PR capability handshakes. |
| Durable task state | REQUIRES REDESIGN | GITHUB-01, RUNTIME-02, SECURITY-01 | GitHub was durable; worker records were not enough to prove active or complete attempts. | GitHub alone may not provide all future internal orchestrator state fields. | Store task, attempt, executor, capability, and approval state externally. |
| Recovery | REQUIRES REDESIGN | INFRA-03, INFRA-04, RECOVERY-01, RECOVERY-02, SECURITY-01 | Recovery exposed sandbox and workflow capability gaps; lifecycle persistence PASS artifacts were absent. | Narrow recovery success was real but limited. | Benchmark restart, reboot, stale state, and failed-attempt recovery before selection. |
| Observability | REQUIRES REDESIGN | GITHUB-01, RUNTIME-02, SECURITY-01 | Durable GitHub observability was strong, but worker attempt/capability visibility was insufficient. | Raw restricted logs were intentionally not republished. | Add first-class task, attempt, capability, and execution telemetry. |
| Security boundary | PASS WITH LIMITATIONS | VISION-02, INFRA-01, INFRA-02, AUTH-01, SECURITY-01 | Least privilege, IAP, token hygiene, status-only channel, and no automatic merge are strong patterns. | Permission boundaries also produced execution uncertainty. | Preserve least privilege while failing closed before active execution. |
| Compatibility overlay | REQUIRES REDESIGN | RUNTIME-01, COMPAT-01 | Controlled overlay was necessary to integrate pinned versions and a tool contract. | Semantic correctness of every tool was not proven. | Isolate compatibility in replaceable adapters and budget maintenance explicitly. |
| Operational efficiency | NOT SELECTED | RECOVERY-01, RECOVERY-02, SECURITY-01, CODEX-02, DECISION-INPUT-01 | Recovery, diagnostics, and orchestration cost were disproportionate for primary-orchestrator use. | No exact dollar, token, or wall-clock totals are asserted. | Do not select this architecture as primary; benchmark future candidates. |
| Governed knowledge reuse | PASS WITH LIMITATIONS | KNOWLEDGE-01, KNOWLEDGE-02, EXP06-02, EXP07-02 | Skill review and reuse produced useful method structure. | Reusable knowledge did not eliminate target-specific inspection. | Retain governed knowledge promotion with validation per target. |
| Managed Linux DevBox | PASS WITH LIMITATIONS | INFRA-01, INFRA-04, RECOVERY-01 | Private DevBox and disk-backed state model are useful platform infrastructure. | VM reboot persistence validation lacked a direct PASS artifact; later reboot diagnostics found worker sandbox failure. | Keep private runtime pattern, but prove reboot/recovery behavior with acceptance benchmarks. |
| Direct Codex as executor | PASS WITH LIMITATIONS | CODEX-01, CODEX-02, EXP08-02 | Direct Codex completed final 08B validation/correction under explicit human approval. | It was not a controlled identical-environment benchmark and is not a replacement-framework selection. | Treat executors as replaceable and validate each through the same benchmark. |

## 17. Reusable Patterns

- Private GCP runtime with IAP-only operator access and restricted credential
  handling (INFRA-01, INFRA-02, AUTH-01).
- Loopback-only Gateway exposure for bounded local control-plane access
  (RUNTIME-01).
- GitHub issues and PRs as durable workflow and audit state (GITHUB-01).
- Human approval gates for architecture, implementation, correction, testing,
  merge, and knowledge promotion (VISION-02, GOVERNANCE-01).
- Logical architect/developer/tester role separation (WORKER-01).
- Architecture-first planning and sequential workflow control (GOVERNANCE-01,
  GOVERNANCE-02).
- Immutable accepted baselines and explicit validation closeout (EXP06-01,
  EXP07-01, EXP07-02, EXP08-01, EXP08-02).
- Negative validation and recovery validation where actually evidenced
  (EXP07-02, CODEX-01, CODEX-02).
- Governed knowledge review and reusable skill promotion with target-specific
  validation (KNOWLEDGE-01, KNOWLEDGE-02).
- Replaceable executor concept, demonstrated by direct Codex continuation after
  explicit human approval (CODEX-01, CODEX-02).

## 18. Rejected Patterns

- Treating Gateway health, RPC readiness, plugin loading, dispatch acceptance,
  or session creation as proof of execution readiness (RUNTIME-01, RECOVERY-01,
  SECURITY-01).
- Treating worker session state as authoritative durable task state
  (RUNTIME-02, GITHUB-01, SECURITY-01).
- Starting active execution attempts before filesystem, Git, Docker/runtime,
  API, validation, branch, and PR capabilities are proven (RECOVERY-01,
  RECOVERY-02, SECURITY-01).
- Relying on compatibility overlays as an unbounded primary-platform
  maintenance path (RUNTIME-01, COMPAT-01).
- Treating narrow sandbox recovery as proof of full engineering workflow
  readiness (RECOVERY-02, SECURITY-01).
- Claiming managed-service restart or VM reboot persistence validation passed
  without direct PASS artifacts (INFRA-03, INFRA-04).
- Collapsing valid Experiment 08 migration results into orchestration failure,
  or erasing successful Experiments 06 and 07 (EXP06-01, EXP06-02, EXP07-01,
  EXP07-02, EXP08-02, CODEX-02).

## 19. Recommended Platform Direction

Recommendation: The evidence supports recommending that the evaluated
OpenClaw/DevClaw architecture is not selected as the primary orchestration
foundation for the AI Operations Platform (RECOVERY-01, RECOVERY-02,
SECURITY-01, CODEX-02, DECISION-INPUT-01).

Recommendation: OpenClaw may remain useful as a communication gateway or
interactive runtime, subject to explicit capability and lifecycle validation
(RUNTIME-01, AUTH-01, RECOVERY-02).

Recommendation: DevClaw workflow concepts should remain research inputs, but
the worker runtime should not be a required platform dependency without
redesign (WORKER-01, GOVERNANCE-01, RECOVERY-01, SECURITY-01).

Recommendation: The first platform implementation should use a simpler
sequential workflow with GitHub-native auditability, human approval gates,
durable external task state, replaceable executor adapters, and pre-execution
capability negotiation (VISION-02, GITHUB-01, GOVERNANCE-01, CODEX-02).

Recommendation: Future orchestrators should be evaluated with a reusable
acceptance benchmark that covers restart, reboot, stale state, sandbox,
filesystem, Git, Docker/runtime access, validation, push, PR update,
observability, token/time cost, and human intervention (INFRA-03, INFRA-04,
RECOVERY-01, RECOVERY-02, SECURITY-01, DECISION-INPUT-01).

This report does not select n8n, Google ADK, LangGraph, Temporal, Cloud
Workflows, Restate, DBOS, a custom orchestrator, or any other replacement
framework.

## 20. Limitations

- The worker/direct Codex comparison is operational, not a controlled benchmark
  with identical environments (CODEX-01, CODEX-02).
- Evidence spans multiple experiments and repositories, so conclusions are
  bounded to the evaluated versions, architecture, integration, environment,
  and observed behavior (EXP06-01, EXP07-02, EXP08-02, DECISION-INPUT-01).
- Product, integration, compatibility overlay, sandbox, host, permission, and
  environment attribution remains partly unresolved (RECOVERY-01, RECOVERY-02,
  SECURITY-01).
- Exact token counts, dollar costs, operator hours, and performance ratios were
  not recorded in the accepted evidence (CODEX-02, DECISION-INPUT-01).
- Restart and reboot state models are documented, but direct successful
  managed-service restart persistence and VM reboot persistence PASS artifacts
  were not found (INFRA-03, INFRA-04).
- Earlier successful Experiments 06 and 07 prevent a universal negative claim
  about OpenClaw or DevClaw (EXP06-01, EXP06-02, EXP07-01, EXP07-02).
- The valid Experiment 08 migration result remains separate from the
  orchestration-platform result (EXP08-02, CODEX-02).

## 21. Evidence References

This report uses the accepted Evidence IDs from
`docs/research/openclaw-devclaw/evidence-index.md` and chronology from
`docs/research/openclaw-devclaw/experiment-chronology.md`.

Referenced Evidence IDs:

- VISION-01: Platform architecture and roadmap documentation.
- VISION-02: Operating model and security model guardrails.
- VISION-03: Umbrella issue #8 coordination.
- INFRA-01: Private GCP runtime foundation.
- INFRA-02: Status-only operator channel.
- INFRA-03: Managed-service restart model without direct PASS artifact.
- INFRA-04: VM reboot state model without direct PASS artifact.
- RUNTIME-01: Gateway and DevClaw validation scripts.
- RUNTIME-02: Issue #16 retained runtime evidence summary.
- COMPAT-01: DevClaw compatibility overlay.
- AUTH-01: Gateway authentication and credential validation contract.
- GITHUB-01: GitHub workflow state.
- WORKER-01: Validated role model evidence.
- GOVERNANCE-01: Human approval gates.
- GOVERNANCE-02: Disabled autonomy and sequential execution controls.
- RECOVERY-01: Minimal read-only subagent smoke failure.
- RECOVERY-02: Narrow AppArmor/userns recovery validation.
- SECURITY-01: Capability preflight and Git/process boundary evidence.
- KNOWLEDGE-01: Experiment 06 governed knowledge closeout.
- KNOWLEDGE-02: Experiment 07B tester report on skill reuse.
- EXP06-01: Experiment 06 implementation PR merge evidence.
- EXP06-02: Experiment 06 closeout and skill review evidence.
- EXP07-01: Experiment 07A baseline merge evidence.
- EXP07-02: Experiment 07B Aspire migration merge and tester PASS evidence.
- EXP08-01: Experiment 08A Compose baseline merge evidence.
- EXP08-02: Experiment 08B Aspire PR merge evidence.
- CODEX-01: Human-approved direct Codex final validation/correction.
- CODEX-02: Human closeout accepting the final Experiment 08B result.
- DECISION-INPUT-01: Architecture decision input preserving success and
  failure evidence.
