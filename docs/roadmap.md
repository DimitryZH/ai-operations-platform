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

## Current

- align the platform Vision, architecture narrative, diagrams, and roadmap
  with ADR 0001 through issue #15
- preserve historical migration outcomes while separating them from
  orchestration-platform selection
- keep OpenClaw and DevClaw as optional or research inputs unless separate
  evidence supports a narrower operational role
- keep candidate runtime, workflow, and control-plane mappings as hypotheses
  until a separate evidence-backed selection is accepted

## Planned

- define a product-neutral acceptance benchmark for future orchestrator or
  executor candidates
- evaluate future candidates against the accepted control-plane requirements
- make any replacement selection through a separate evidence-backed decision
- implement the first simpler sequential control-plane workflow
- define replaceable executor-adapter contracts
- implement capability declaration and verification before active attempts
- implement durable task and attempt state outside ephemeral agent sessions
- define timeout, recovery, and stale-attempt handling
- expand specialized integrations after the executor-adapter contract is
  stable

## Candidate Status

No replacement framework is selected, recommended, ranked, or compared by this
roadmap.

OpenClaw may be reconsidered as an optional communication gateway or
interactive runtime after separate operational validation. DevClaw remains
workflow research and a source of governance concepts, not a required primary
dependency.

Other candidates, including runtime frameworks, workflow frameworks, control
planes, operational assistants, GitHub-native automation, cloud-agent
frameworks, incident-analysis tools, and cost-optimization tools, remain
hypotheses until evaluated through a product-neutral acceptance benchmark and
accepted through separate review.

## Deferred

- parallel or multi-agent execution
- full alert routing
- incident workflows
- automated remediation
- platform adapters beyond the first executor-adapter contract
- specialized operational agents
- restore-drill automation
- cross-project reusable-skill value validation

## Explicitly Out Of Scope For Now

- selecting, recommending, ranking, or comparing a replacement framework
- implementing a benchmark in this documentation update
- alternate cloud-provider scope
- cloud-provider abstraction
- write-capable Telegram commands
- unapproved autonomous remediation
- automatic merge
- secrets, real chat IDs, Terraform state, tfvars, raw plans, or private
  operator notes in tracked files
