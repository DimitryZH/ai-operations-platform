# Roadmap

This repository is aligned around the accepted AI Operations Platform direction:
a GCP-first, AI-native operations control plane with durable task and attempt
state outside ephemeral agent sessions, replaceable executors, explicit
capability handshakes, GitHub auditability, and human approval gates.

## Completed

- GCP private Stateful VM runtime foundation
- Persistent Disk state model for private runtime state
- IAP-only operator access
- Secret Manager runtime integration
- systemd-managed OpenClaw runtime
- service-state monitoring baseline
- Telegram status-only operator channel
- context lifecycle foundation
- removal of the legacy container-service scaffold
- OpenClaw/DevClaw evidence consolidation and orchestration evaluation
- ADR 0001 primary-orchestrator decision
- Vision, architecture, operating model, security model, backup and restore,
  and roadmap alignment with ADR 0001 through issue #15
- reusable, product-neutral orchestrator acceptance benchmark specification
  through issue #17 and merged PR #18
- Experiment 08 public retrospective in Application Modernization Lab through
  [issue #18](https://github.com/DimitryZH/application-modernization-lab/issues/18)
  and
  [PR #19](https://github.com/DimitryZH/application-modernization-lab/pull/19)
- complete OpenClaw/DevClaw evaluation umbrella closeout through closed issue
  #8

Implemented fact: the current Stateful VM foundation includes a
systemd-managed OpenClaw runtime. That runtime fact is distinct from the ADR
0001 decision not to select the evaluated OpenClaw/DevClaw architecture as the
primary orchestration foundation.

Historical application-modernization evidence: Experiment 06 validated a
bounded OpenClaw and DevClaw delivery workflow for an application migration.
See the
[Online Boutique Compose-to-Aspire case study](case-studies/experiment-06-online-boutique-compose-to-aspire.md)
for evidence and scope boundaries.

| Capability | Status |
|---|---|
| Governed multi-agent migration workflow | VALIDATED |
| Independent defect detection and correction loop | VALIDATED |
| Human-controlled GitHub delivery workflow | VALIDATED |
| Governed knowledge promotion through Skill Workshop | VALIDATED |
| Cross-project skill reuse | PENDING VALIDATION |

That migration success remains valid and separate from the ADR 0001 decision
not to select the evaluated OpenClaw/DevClaw architecture as the primary
orchestrator. It does not override the orchestration non-selection and must not
be read as successful managed-service restart or VM reboot recovery evidence.

The orchestrator acceptance benchmark is complete as a specification. No
candidate architecture has executed that benchmark, and no benchmark
measurement, scorecard result, or replacement selection has been accepted.

## Current

The next platform direction is a bounded, read-only SRE investigation MVP. The
first integration and demonstration environment is the existing
[SRE Platform](https://github.com/DimitryZH/sre-platform), which provides a
real GitOps, Kubernetes, progressive-delivery, SLO, monitoring, rollback, and
controlled-failure context.

The SRE Platform development and staging environments are substantially
implemented and may support initial read-only investigation work. Its
production phase remains incomplete and unvalidated, and this roadmap does not
claim production rollout, production SLO validation, production rollback, or
production recovery completion.

Read-only SRE investigation may begin against development and staging
scenarios, then accompany completion of the SRE Platform production phase where
practical. Production rollout, controlled failure, SLO analysis, rollback, and
recovery can provide realistic investigation cases, but production completion
remains owned and validated in the SRE Platform repository.

Responsibility boundaries:

- SRE Platform owns its environments, rollout scenarios, production
  completion, controlled failures, SLO validation, rollback, recovery, and
  operational evidence.
- AI Operations Platform owns durable orchestration state, capability
  negotiation, executor invocation, structured findings and evidence,
  durable GitHub references, and human-review boundaries.
- Neither project may claim the other project's incomplete work as completed.

The intended vertical workflow is:

1. accept a controlled operational signal, alert, rollout failure, or SLO
   scenario from the SRE Platform;
2. create durable task and attempt identities;
3. declare and verify required executor capabilities;
4. fail closed when a required capability is absent, ambiguous, unverifiable,
   or incorrectly scoped;
5. run one replaceable read-only SRE investigation executor;
6. collect structured findings, supporting evidence, limitations, and
   recommendations;
7. publish or link durable GitHub references;
8. stop for human review and final closeout.

This MVP is a target direction, not an implemented or validated platform
capability.

## Planned

Near-term work should proceed in this order, subject to later issue-level
refinement:

1. close the completed OpenClaw/DevClaw evaluation work in the roadmap;
2. define the bounded SRE investigation MVP contract and acceptance criteria;
3. validate the first SRE investigator candidate and deployment boundary
   against the existing SRE Platform development or staging environment;
4. decide the minimum control-plane implementation architecture through a
   separate reviewed workstream;
5. implement a thin sequential control-plane skeleton;
6. implement durable task and attempt state;
7. implement capability declaration and fail-closed verification;
8. implement one replaceable read-only SRE executor adapter;
9. use the integration during completion of the SRE Platform production phase
   where practical;
10. demonstrate the complete GitHub-auditable vertical slice;
11. execute the accepted orchestrator benchmark against the integrated
    candidate architecture;
12. consider additional executors, including FinOps and secure-delivery use
    cases, only after the first adapter contract is stable.

The next portfolio milestone is not another broad research package. It is a
small, complete cross-project demonstration showing:

- a real SRE Platform operational scenario;
- explicit investigation input;
- durable workflow state;
- controlled read-only execution;
- real monitoring, rollout, GitOps, or Kubernetes evidence;
- structured findings and recommendations;
- human governance;
- reproducible validation;
- honest limitations.

The portfolio narrative should remain clear: SRE Platform demonstrates the
operational environment and progressive-delivery scenario, while AI Operations
Platform demonstrates controlled AI-assisted investigation and governance. The
executor remains replaceable and is not itself the complete platform.

## Candidate Status

No replacement framework, control-plane technology, database, workflow engine,
transport, hosting product, or primary orchestrator is selected, recommended,
ranked, or compared by this roadmap.

OpenClaw may be reconsidered as an optional communication gateway or
interactive runtime after separate operational validation. DevClaw remains
workflow research and a source of governance concepts, not a required primary
dependency.

HolmesGPT is an unselected, read-only, replaceable candidate for the first SRE
investigation executor because its domain appears relevant to Kubernetes,
Prometheus, GitOps, rollout, and incident evidence. This roadmap does not
select or accept HolmesGPT. Its deployment mode, permissions, capability
contract, and operational suitability require a separate implementation and
validation issue. Successful HolmesGPT investigation would not by itself prove
that the complete AI Operations Platform control plane satisfies the accepted
orchestrator benchmark.

Other candidates, including runtime frameworks, workflow frameworks, control
planes, operational assistants, GitHub-native automation, cloud-agent
frameworks, incident-analysis tools, and cost-optimization tools, remain
hypotheses until evaluated through a product-neutral acceptance benchmark and
accepted through separate review.

## Deferred

- parallel and multi-agent execution
- autonomous remediation
- broad incident-management automation
- multiple executor types
- production-scale alert routing
- automatic merge
- multi-cloud abstraction
- restore-drill automation
- cross-project reusable-skill value validation

## Explicitly Out Of Scope For Now

- selecting, recommending, ranking, or comparing a replacement framework
- selecting n8n, OpenClaw, DevClaw, HolmesGPT, or any other control-plane or
  executor technology
- selecting a database, workflow engine, transport, hosting product, or
  replacement orchestrator
- implementing or formally selecting HolmesGPT
- executing the orchestrator acceptance benchmark
- claiming benchmark measurements, benchmark results, or candidate evaluation
- claiming that the SRE investigation MVP already exists
- claiming that the SRE Platform production phase is complete or validated
- modifying the SRE Platform repository
- changing ADR 0001
- alternate cloud-provider scope
- cloud-provider abstraction
- write-capable Telegram commands
- unapproved autonomous remediation
- automatic merge
- secrets, real chat IDs, Terraform state, tfvars, raw plans, or private
  operator notes in tracked files
