# Orchestrator Acceptance Benchmark

## 1. Purpose And Scope

This benchmark defines a reusable, product-neutral acceptance specification for
future orchestration and executor architectures for the AI Operations Platform.

It converts the accepted OpenClaw/DevClaw experiment lessons and
[ADR 0001](../adr/0001-primary-orchestrator-foundation.md) requirements into a
repeatable evaluation contract.

This document defines the benchmark only. It does not execute scenarios,
evaluate candidates, select a replacement framework, recommend a candidate,
rank candidates, install software, configure runtime components, or modify
infrastructure.

Historical application-modernization evidence remains technically valid.
Experiment 06, Experiment 07, and the valid Experiment 08B Aspire migration
remain successful application outcomes. They do not establish that the
evaluated OpenClaw/DevClaw architecture is the primary platform orchestrator,
do not override ADR 0001, and do not prove restart or reboot recovery.

## 2. Architecture Under Test

The architecture under test is the integrated candidate architecture needed to
execute and govern the reference workflow. It may include:

- communication gateway
- control plane
- durable state
- executor adapter
- executor
- target repository or platform
- validation tooling
- GitHub integration
- human-review boundary

A candidate does not need to implement all responsibilities in one product.
The benchmark evaluates whether the integrated architecture satisfies the
required responsibilities and boundaries.

A gateway, agent runtime, workflow engine, database, or executor is not by
itself the complete orchestrator unless the evaluated architecture also proves
the required state, approval, capability, recovery, evidence, and audit
contracts.

## 3. Candidate-Neutral Terminology

| Term | Benchmark meaning |
| --- | --- |
| Candidate architecture | The complete integrated architecture being evaluated. |
| Communication gateway | The intake or interaction surface for operators, status, approvals, and optional interactive runtime access. |
| Control plane | The component or set of components that owns task and attempt state, approvals, dispatch decisions, capability requirements, recovery, evidence references, and final closeout. |
| Durable state | Authoritative task, attempt, approval, capability, recovery, and evidence state that survives outside an ephemeral executor session. |
| Executor adapter | The boundary that translates a control-plane attempt into executor-specific actions and capability checks. |
| Executor | The replaceable worker that performs bounded engineering or operations work. |
| Capability handshake | The declared and verified capability contract required before an attempt becomes active. |
| Attempt | One bounded execution try for a task, with its own identity, capability result, state, evidence, and outcome. |
| Human approval | A durable human decision that authorizes a bounded action or state transition. |

Named technologies may appear only in historical references, accepted-decision
references, or explicit non-selection boundaries. This benchmark does not
create candidate-specific weights, exceptions, or shortlists.

## 4. Required Test Environment

Each future benchmark run must declare a controlled environment before
execution begins:

- repository under test and immutable starting baseline
- benchmark fixture or documentation-only change target
- approved branch naming convention
- required validation commands
- GitHub issue or task reference
- expected Draft pull request behavior
- human approval mechanism
- allowed filesystem scope
- allowed network and API scope
- allowed runtime, Docker, cloud, or Kubernetes scope where applicable
- secret handling and redaction rules
- timeout, retry, and safety budgets
- evidence publication location

The default fixture should be documentation-only or otherwise harmless. The
fixture must be small enough to repeat safely and must not require destructive
actions against live infrastructure.

The environment description must avoid credentials, raw logs, raw session
databases, private runtime state, sensitive security configuration, and
unnecessary machine-specific absolute paths.

## 5. Standard Reference Workflow

Every future candidate must be evaluated against the same bounded sequential
workflow or an explicitly mapped equivalent:

1. Accept a bounded task.
2. Create a durable task identity.
3. Create a distinct execution-attempt identity.
4. Record required executor capabilities.
5. Select or assign an executor.
6. Perform a capability handshake.
7. Fail closed if a required capability is missing or ambiguous.
8. Wait for required human approval before mutation.
9. Dispatch the approved attempt.
10. Read a controlled repository baseline.
11. Make a bounded change on a dedicated branch.
12. Run defined validation.
13. Record structured execution and validation results.
14. Create a commit.
15. Push the branch.
16. Create or update a Draft pull request.
17. Preserve evidence and GitHub references.
18. Stop for human review.
19. Record final closeout only after the accepted human action.

This workflow is sequential by design. Parallel execution, autonomous merge,
and unattended remediation are outside the benchmark's default reference path.

## 6. Task And Attempt Lifecycle Model

The benchmark requires an unambiguous mapping from candidate vocabulary to the
following task and attempt lifecycles.

Task lifecycle:

- proposed
- awaiting approval
- approved
- active
- blocked
- completed
- cancelled
- rejected

Attempt lifecycle:

- created
- capability check pending
- capability check failed
- ready
- dispatched
- executing
- validating
- awaiting human review
- succeeded
- failed
- timed out
- stale
- cancelled
- recovered or superseded

Dispatch acceptance, session creation, command execution, repository mutation,
validation, push, pull-request update, and accepted completion must remain
distinct states. A candidate must not treat one of those states as proof of a
later state.

Each attempt record must correlate:

- task ID
- attempt ID
- executor ID
- capability result
- approval
- repository and branch
- commit
- pull request
- validation result
- evidence references
- recovery or supersession state

This benchmark does not select a database, event store, workflow engine, or
persistence product.

## 7. Capability Handshake Contract

Before an attempt becomes active, the candidate architecture must declare and
verify every capability required by the reference task.

The handshake must cover applicable capabilities:

- repository read
- repository write
- bounded filesystem access
- Git status and diff
- branch creation
- commit creation
- push
- GitHub issue access
- Draft pull-request creation or update
- validation tooling
- runtime or Docker access
- network access
- external API access
- cloud or Kubernetes access
- evidence publication

Each capability record must include:

| Field | Requirement |
| --- | --- |
| Capability ID | Stable identifier for the capability being checked. |
| Required status | Required or optional for the attempt. |
| Declared status | Candidate-declared availability and scope. |
| Verification method | How the declaration is tested before dispatch. |
| Verification result | PASS, FAIL, BLOCKED, or NOT TESTED for the capability check. |
| Evidence reference | Durable reference to bounded evidence. |
| Failure reason | Required for FAIL, BLOCKED, or NOT TESTED. |

A declaration alone is insufficient evidence. A required capability must fail
closed when it is absent, ambiguous, unverifiable, incorrectly scoped, lost
after recovery, or different from the capability approved by the operator.

## 8. Readiness-State Model

The benchmark preserves the readiness distinctions accepted in the evidence
package:

| # | State | What it proves | What it does not prove |
| ---: | --- | --- | --- |
| 1 | Infrastructure available | The host, network boundary, base runtime, or managed service can exist. | Worker readiness, control-plane readiness, or task completion. |
| 2 | Gateway process running | A gateway process is active. | Listener availability or RPC readiness. |
| 3 | Gateway listener available | A listener is reachable. | RPC success, plugin load, or execution capability. |
| 4 | Control-plane API or RPC ready | Basic API or RPC health responds. | Capability negotiation or execution readiness. |
| 5 | Integration or plugin loaded | A declared integration is present. | Command execution or repository access. |
| 6 | Dispatch accepted | A request was accepted for handling. | Executor session creation or work execution. |
| 7 | Executor session or attempt created | An attempt or session record exists. | Filesystem, Git, Docker/runtime, API, validation, push, or PR capability. |
| 8 | Minimal command executed | A narrow command ran in the intended environment. | Full implementation workflow capability. |
| 9 | Repository read completed | The baseline was inspected. | Write, build, validation, commit, or push capability. |
| 10 | Repository mutation completed | Intended files changed in the controlled scope. | Validation success or Git commit capability. |
| 11 | Validation completed | Required checks ran to completion. | Human acceptance or merge readiness. |
| 12 | Commit created | A commit exists. | Branch push or PR update success. |
| 13 | Branch pushed | Remote branch state changed. | Correct PR metadata or accepted completion. |
| 14 | Pull request updated | Draft PR state or metadata was created or updated. | Merge approval or task closeout. |
| 15 | Human-reviewed task completion | Human review accepted the bounded result. | Universal platform suitability or candidate selection. |

A higher-level PASS must not be inferred solely from a lower-level readiness
signal.

## 9. Durable-State Requirements

The candidate architecture must prove that authoritative state survives outside
ephemeral executor sessions.

Required checks:

- task-state persistence
- attempt-state persistence
- approval-state persistence
- capability-result persistence
- evidence-reference persistence
- executor-session loss handling
- control-plane restart handling
- executor restart handling
- host or VM reboot handling where the architecture depends on that boundary
- stale-attempt detection
- duplicate-dispatch prevention
- safe retry or supersession
- partial execution handling
- recovery after capability loss

Restart and reboot checks are future benchmark requirements. The historical
OpenClaw/DevClaw evidence established the need for those checks, but did not
include direct successful managed-service restart persistence or VM reboot
persistence PASS artifacts.

## 10. Functional Test Scenarios

| Scenario | Required behavior | Required evidence | Result |
| --- | --- | --- | --- |
| Task intake | Accept a bounded task and create durable task state. | Task ID, input scope, creation timestamp, source reference. | NOT TESTED |
| Attempt creation | Create a distinct attempt with executor assignment. | Attempt ID, executor ID, task correlation. | NOT TESTED |
| Capability verification | Declare and verify required capabilities before dispatch. | Capability records with methods, results, and evidence. | NOT TESTED |
| Human mutation approval | Block mutation until required approval is durable. | Approval reference and state transition. | NOT TESTED |
| Baseline read | Read the controlled repository baseline. | Repository, branch, commit, and read evidence. | NOT TESTED |
| Bounded mutation | Change only approved files or fixture scope. | Diff summary and changed-file list. | NOT TESTED |
| Validation | Run predeclared validation. | Command, bounded output, exit status, and result. | NOT TESTED |
| Commit and push | Create a commit and push the benchmark branch. | Commit SHA and remote branch reference. | NOT TESTED |
| Draft PR update | Create or update a Draft PR and stop for review. | Pull request URL, number, head SHA, and Draft status. | NOT TESTED |
| Final closeout | Record completion only after accepted human action. | Human review or closeout reference. | NOT TESTED |

These scenarios are definitions only. They were not executed by this issue.

## 11. Failure-Injection And Recovery Scenarios

Each future failure scenario must be run against the same field contract:

| Field | Requirement |
| --- | --- |
| Preconditions | Baseline state before the injected failure. |
| Injected failure | Exact failure introduced by the benchmark. |
| Expected state transition | Required task and attempt state changes. |
| Prohibited behavior | Actions that must not occur. |
| Required recovery behavior | Safe recovery, retry, supersession, or stop behavior. |
| Required evidence | Durable references proving the result. |
| PASS rule | Conditions required to pass. |
| FAIL rule | Conditions requiring candidate failure. |
| BLOCKED rule | Environment, permission, integration, or setup blocker that prevents attribution to the candidate. |
| NOT TESTED rule | Scenario omitted or not executed; never treated as PASS. |

Required failure scenarios:

| Scenario | Preconditions | Injected failure | Expected state transition | Prohibited behavior | Required recovery behavior | Required evidence | PASS rule | FAIL rule | BLOCKED rule | NOT TESTED rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Required capability missing before dispatch | Task and attempt exist; required capabilities are known. | Remove or deny one required capability before dispatch. | Attempt moves to capability check failed or blocked before dispatch. | Repository, infrastructure, or runtime mutation. | Stop or request approved capability correction. | Capability record and state transition. | Required capability fails closed before dispatch. | Attempt dispatches or mutates despite missing capability. | External permission or setup prevents checking capability at all. | Scenario not executed. |
| Capability declaration inconsistent with verification | Candidate declares a capability. | Verification contradicts the declaration. | Attempt moves to capability check failed. | Treating declaration as proof. | Stop and preserve contradiction evidence. | Declaration, verification method, result. | Contradiction blocks activation. | Attempt becomes active from declaration alone. | Verification system unavailable for non-candidate reasons. | Scenario not executed. |
| Executor unavailable before dispatch | Capabilities and approval path are known. | Assigned executor is unavailable. | Attempt stays ready, blocked, or failed before dispatch. | Creating false execution or completion records. | Reassign only through approved policy or stop. | Executor health and attempt state. | No active execution is recorded. | Dispatch or execution is falsely reported. | Environment outage prevents executor attribution. | Scenario not executed. |
| Executor failure during execution | Approved attempt is executing. | Executor fails after starting. | Attempt moves to failed, timed out, stale, or superseded. | Duplicate uncontrolled execution. | Preserve partial state and require safe retry or supersession. | Attempt timeline and failure evidence. | Failure is bounded and recoverable or safely stopped. | State is lost or duplicate execution occurs. | Host or platform outage prevents attribution. | Scenario not executed. |
| Control-plane restart during active attempt | Attempt is active and state is durable. | Restart the control-plane boundary. | Task and attempt state survive and reconcile. | Treating restart as completion. | Resume observation, mark stale, or supersede safely. | Pre/post restart state and reconciliation evidence. | State survives and no duplicate dispatch occurs. | State loss or uncontrolled redispatch occurs. | Benchmark cannot restart control plane safely. | Scenario not executed. |
| Executor-session loss | Attempt has an executor session. | Lose the session. | Attempt becomes stale, failed, or superseded. | Assuming session loss equals success. | Detect loss and require recovery policy. | Session-loss signal and attempt state. | Loss is detected and bounded. | Loss is invisible or reported as success. | Session cannot be observed due benchmark setup. | Scenario not executed. |
| Timeout | Attempt has a declared timeout. | Exceed the timeout. | Attempt moves to timed out. | Continuing indefinitely or hiding timeout. | Stop, retry, or supersede according to policy. | Timeout budget and event evidence. | Timeout is enforced and audited. | Timeout ignored or obscured. | Environment clock or scheduling issue blocks attribution. | Scenario not executed. |
| Stale running attempt | Attempt appears running beyond valid heartbeat or lease. | Remove heartbeat, lease, or progress signal. | Attempt moves to stale. | Treating stale as successful or active indefinitely. | Require safe recovery or supersession. | Staleness rule and state evidence. | Stale condition is detected. | Stale state is not represented. | Benchmark cannot observe required signal. | Scenario not executed. |
| Validation failure | Mutation is completed. | Validation command fails. | Attempt moves to failed or awaiting correction. | Push or PR completion claim as if validation passed. | Preserve failure and require correction approval where needed. | Validation command, exit status, bounded output. | Failure blocks completion. | Failure is hidden or converted to PASS. | Validation tool unavailable for setup reasons. | Scenario not executed. |
| Git push failure | Commit exists locally. | Remote push fails. | Attempt records push failure. | Claiming branch pushed or PR updated. | Retry within budget or stop. | Git result and branch state. | Failure is explicit and bounded. | PR/update success claimed without push. | Remote outage or credential scope blocks attribution. | Scenario not executed. |
| Pull-request update failure | Branch has been pushed. | PR creation or update fails. | Attempt records PR update failure. | Claiming human-review stop point. | Retry within budget or stop for operator. | PR API/CLI result and branch reference. | Failure is explicit and review state is not fabricated. | Completion recorded without PR state. | GitHub outage or permission setup blocks attribution. | Scenario not executed. |
| Duplicate dispatch request | An attempt already exists. | Submit duplicate dispatch. | Duplicate is rejected, deduplicated, or superseded deterministically. | Concurrent uncontrolled attempts. | Preserve correlation and selected policy. | Dispatch IDs and attempt records. | No duplicate uncontrolled execution occurs. | Multiple active attempts mutate same scope. | Test harness cannot issue duplicate safely. | Scenario not executed. |
| Partial repository mutation | Mutation starts. | Interrupt after partial change. | Attempt records partial execution. | Hiding partial state or pushing unvalidated changes. | Revert, repair, or supersede under approved policy. | Diff and state evidence. | Partial state is visible and bounded. | Partial mutation escapes as success. | Fixture cannot safely represent partial mutation. | Scenario not executed. |
| Capability loss after restart | Capability had passed earlier. | Restart causes capability to disappear or change scope. | Attempt requires re-verification and fails closed if needed. | Reusing stale capability approval. | Re-handshake before active work continues. | Before/after capability records. | Capability loss blocks execution. | Stale verification is reused. | Restart boundary cannot be exercised safely. | Scenario not executed. |
| Recovery requiring a new attempt | Existing attempt cannot continue safely. | Force recovery path requiring supersession. | Old attempt is failed, stale, cancelled, or superseded; new attempt gets new identity. | Reusing old identity ambiguously. | Create a correlated replacement attempt. | Old and new attempt records. | Supersession is explicit. | Attempt lineage is ambiguous. | Benchmark setup cannot model recovery. | Scenario not executed. |
| Unauthorized or unapproved mutation attempt | No mutation approval is present. | Attempt mutation without approval. | Attempt is rejected or blocked. | Any repository, infrastructure, runtime, or GitHub mutation. | Preserve security evidence and require approval. | Approval state and denied action evidence. | Mutation is blocked. | Mutation occurs. | Permission model cannot test safely. | Scenario not executed. |

`BLOCKED` is distinct from candidate failure when the blocker belongs to the
environment, permissions, integration, or benchmark setup. `NOT TESTED` never
means `PASS`.

## 12. Security And Least-Privilege Checks

The benchmark must verify:

- least-privilege access
- bounded repository and filesystem scope
- separation of read and write capabilities
- explicit approval before mutation
- secret redaction
- no credentials in tracked files or evidence
- no publication of raw session databases
- no publication of private runtime state
- no unnecessary machine-specific details
- denial of undeclared capabilities
- fail-closed behavior
- evidence that security restrictions do not create hidden execution ambiguity

A candidate must not receive a PASS merely because security controls exist. It
must prove that unauthorized actions are blocked and required authorized
capabilities are verified before execution.

## 13. Human-Approval Checks

The benchmark must preserve explicit human gates for:

- architecture or benchmark acceptance
- mutation authorization
- material scope changes
- recovery actions that expand permissions or change the environment
- PR readiness
- merge
- final closeout

Automatic merge must not be required or used by the benchmark.

## 14. GitHub Audit And Evidence Requirements

Each future run must preserve durable GitHub references for:

- issue or task specification
- approval
- branch
- commit
- pull request
- validation result
- corrections
- review
- manual merge where performed
- final issue closeout

GitHub is the required durable workflow, evidence, audit, and human-review
boundary for benchmark publication. It must not be treated as the internal
execution-state engine.

## 15. Observability Requirements

The operator must be able to observe:

- task identity and state
- attempt identity and state
- selected executor
- required, declared, and verified capabilities
- approval state
- dispatch state
- execution state
- validation state
- timeout and stale-attempt state
- recovery or supersession state
- result
- GitHub references
- evidence references

The system must distinguish accepted but not dispatched, dispatched but not
executing, executing, blocked, validating, awaiting review, failed, timed out,
stale, superseded, and completed.

A session record alone is not sufficient observability.

## 16. Repeatability Requirements

Each benchmark run must be reproducible from:

- benchmark version
- candidate architecture and version
- immutable starting baseline
- fixture definition
- predeclared capabilities
- predeclared validation
- predeclared timeout and safety budgets
- environment description
- evidence package
- completed scorecard

Candidate-specific adaptations must be recorded as compatibility work. They
must not change mandatory gates or weaken acceptance criteria.

## 17. Time, Cost, Token, And Operator-Intervention Measurement

Future benchmark runs must measure or explicitly mark unavailable:

- elapsed time
- active execution time
- recovery time
- operator interventions
- approval interactions
- retries
- failed attempts
- compatibility work
- token usage where observable
- model or API cost where observable
- infrastructure cost where observable

Where universal numeric limits cannot yet be justified, the benchmark run must
declare candidate-specific budgets before execution and freeze them for that
run.

Every value must be classified as one of:

- measured value
- estimated value
- unavailable measurement
- threshold declared before execution
- threshold changed after execution

A candidate receives no credit for unmeasured time, cost, token, or
intervention claims. The historical OpenClaw/DevClaw experiment did not record
exact infrastructure spend, operator hours, recovery hours, token counts,
dollar costs, or controlled wall-clock comparisons.

## 18. Acceptance Gates

Mandatory gates are independent from scored qualities. A failed mandatory gate
cannot be overridden by an aggregate score.

Mandatory gates:

- no unapproved mutation
- no automatic merge
- durable external task and attempt state
- explicit capability verification
- fail-closed behavior
- unambiguous attempt lifecycle
- bounded recovery behavior
- repeatable GitHub audit trail
- required validation completion
- preservation of security boundaries
- successful human-review stop point
- no false claim of completion from dispatch or session state

Scored qualities may describe comparative usability, effort, cost,
integration burden, and fit, but they cannot compensate for a mandatory-gate
failure.

## 19. Kill Criteria

An evaluation must stop when continuing would:

- require exposing credentials or sensitive state
- require uncontrolled privilege expansion
- modify resources outside approved scope
- invalidate the controlled baseline
- make result attribution impossible
- exceed a predeclared safety or operational budget
- require weakening acceptance criteria to obtain PASS
- create repeated uncontrolled or duplicate execution
- make durable state inconsistent or unrecoverable

Kill criteria produce FAIL, BLOCKED, or NOT TESTED according to the attribution
and evidence rules. They do not produce PASS.

## 20. Result Classifications

| Result | Allowed when | Candidate-level handling |
| --- | --- | --- |
| PASS | Required direct evidence proves the scenario or gate satisfied the benchmark contract. | Candidate-level PASS requires PASS for every applicable mandatory gate and every required scenario. |
| CONDITIONAL PASS | Every applicable mandatory gate passes, every required scenario has direct evidence, no required scenario is FAIL, BLOCKED, or NOT TESTED, and remaining limitations affect only predeclared non-mandatory qualities within predeclared bounds. | Candidate-level CONDITIONAL PASS is not allowed when an applicable mandatory gate fails or when a required scenario is FAIL, BLOCKED, or NOT TESTED. |
| FAIL | Candidate behavior violates the benchmark contract, required evidence contradicts the claim, or a mandatory gate fails for candidate-attributable reasons. | Any candidate-attributable failure of an applicable mandatory gate requires candidate-level FAIL. |
| BLOCKED | The scenario cannot be attributed to the candidate because the blocker belongs to environment, permissions, integration, or benchmark setup. | Any applicable mandatory gate or required scenario classified as BLOCKED prevents candidate-level PASS. |
| NOT TESTED | The scenario, gate, or measurement was not executed or no evidence was captured. | Any applicable mandatory gate or required scenario classified as NOT TESTED prevents candidate-level PASS. |

Candidate-level derivation rules:

- Candidate-level PASS requires PASS for every applicable mandatory gate and
  every required scenario.
- Any applicable mandatory gate or required scenario classified as BLOCKED or
  NOT TESTED prevents candidate-level PASS.
- Candidate-level CONDITIONAL PASS requires every applicable mandatory gate to
  pass and every required scenario to have direct evidence.
- A required scenario classified as FAIL, BLOCKED, or NOT TESTED prevents
  candidate-level CONDITIONAL PASS.
- Remaining limitations for candidate-level CONDITIONAL PASS may affect only
  predeclared non-mandatory qualities and must remain within predeclared
  bounds.
- Any candidate-attributable failure of an applicable mandatory gate requires
  candidate-level FAIL.
- Aggregate scoring cannot override mandatory gates or candidate-level result
  derivation rules.

Contradictions must be recorded as contradictions. Retries and recovered
attempts must preserve the original attempt result and the replacement or
superseding attempt lineage.

## 21. Reusable Scorecard

Future evaluations may copy this empty scorecard without changing the core
criteria.

| Category | Mandatory gate | Result | Evidence | Notes |
| --- | ---: | --- | --- | --- |
| Architecture-boundary separation | Yes | NOT TESTED | - | - |
| Durable task and attempt state | Yes | NOT TESTED | - | - |
| Capability negotiation | Yes | NOT TESTED | - | - |
| Deterministic sequential execution | Yes | NOT TESTED | - | - |
| Failure handling and recovery | Yes | NOT TESTED | - | - |
| Security and least privilege | Yes | NOT TESTED | - | - |
| Human approval boundaries | Yes | NOT TESTED | - | - |
| GitHub auditability | Yes | NOT TESTED | - | - |
| Observability | Yes | NOT TESTED | - | - |
| Repeatability | Yes | NOT TESTED | - | - |
| Compatibility burden | No | NOT TESTED | - | - |
| Time and operator intervention | No | NOT TESTED | - | - |
| Token and API cost | No | NOT TESTED | - | - |
| Infrastructure cost | No | NOT TESTED | - | - |
| GCP-first deployment fit | No | NOT TESTED | - | - |

Do not populate this scorecard with results for any named candidate in the
benchmark specification itself.

## 22. Evidence Package Template

Each future benchmark run must produce a bounded evidence package.

Run metadata:

- benchmark version
- candidate architecture and version information
- environment description
- immutable starting baseline
- issue or task reference
- branch and pull request reference
- final candidate-level classification

Evidence records:

| Field | Requirement |
| --- | --- |
| Evidence reference | Stable repository-relative path, GitHub URL, commit SHA, PR number, issue comment, or sanitized artifact reference. |
| Classification | Direct evidence, reported evidence, inference, or recommendation. |
| Scenario or gate | Scenario, mandatory gate, scorecard row, or measurement supported by the evidence. |
| Supported finding | Narrow finding supported by the evidence. |
| Does not prove | Explicit boundary for the evidence. |
| Sensitivity | Public, internal, or restricted. |
| Publication rule | Whether the content can be quoted, summarized, or only referenced. |

Required package contents:

- declared capabilities
- verified capabilities
- task and attempt timeline
- failure-injection results
- recovery results
- validation results
- GitHub references
- time, cost, token, retry, and intervention measurements
- contradictions and limitations
- completed scorecard
- final recommendation
- human-review record

This benchmark does not create new OpenClaw/DevClaw Evidence IDs.

## 23. Limitations And Interpretation Rules

This benchmark is informed by the accepted OpenClaw/DevClaw evidence, but it
must not retroactively present that experiment as having executed this
benchmark.

Interpretation rules:

- Application-modernization success remains separate from orchestration
  platform selection.
- The evaluated OpenClaw/DevClaw architecture was not selected as the primary
  platform orchestrator.
- OpenClaw and DevClaw are not universally rejected.
- Direct Codex final completion reports do not prove identical worker
  capability or environment parity.
- Restart and reboot recovery must be tested by future benchmark runs and must
  not be claimed from historical design evidence.
- Historical time, token, cost, recovery, and operator-intervention values must
  not be invented.
- `NOT TESTED` is never `PASS`.
- `BLOCKED` remains distinct from candidate failure when attribution belongs to
  environment, permissions, integration, or benchmark setup.
- No candidate may be selected, recommended, ranked, or compared by this
  specification.

## 24. References

- Umbrella issue #8:
  https://github.com/DimitryZH/ai-operations-platform/issues/8
- Evidence issue #9:
  https://github.com/DimitryZH/ai-operations-platform/issues/9
- Evaluation issue #10:
  https://github.com/DimitryZH/ai-operations-platform/issues/10
- ADR issue #13:
  https://github.com/DimitryZH/ai-operations-platform/issues/13
- Vision and roadmap issue #15:
  https://github.com/DimitryZH/ai-operations-platform/issues/15
- Benchmark issue #17:
  https://github.com/DimitryZH/ai-operations-platform/issues/17
- Evidence PR #11:
  https://github.com/DimitryZH/ai-operations-platform/pull/11
- Evaluation PR #12:
  https://github.com/DimitryZH/ai-operations-platform/pull/12
- ADR PR #14:
  https://github.com/DimitryZH/ai-operations-platform/pull/14
- Vision and roadmap PR #16:
  https://github.com/DimitryZH/ai-operations-platform/pull/16
- Vision merge commit:
  `e5c9d0c52c368879d9c64052c398679aceb7d2fb`
- ADR 0001:
  [Primary Orchestrator Foundation](../adr/0001-primary-orchestrator-foundation.md)
- Accepted evidence index:
  [OpenClaw/DevClaw Evidence Index](../research/openclaw-devclaw/evidence-index.md)
- Accepted experiment chronology:
  [OpenClaw/DevClaw Experiment Chronology](../research/openclaw-devclaw/experiment-chronology.md)
- Accepted orchestration evaluation:
  [OpenClaw/DevClaw Orchestration Evaluation](../research/openclaw-devclaw/orchestration-evaluation.md)
- Platform architecture:
  [Architecture](../architecture.md)
- Operating model:
  [Operating Model](../operating-model.md)
- Security model:
  [Security Model](../security-model.md)
- Backup and restore model:
  [Backup & Restore](../backup-restore.md)
- Roadmap:
  [Roadmap](../roadmap.md)
