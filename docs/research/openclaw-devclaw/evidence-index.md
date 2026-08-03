# OpenClaw/DevClaw Evidence Index

## Purpose and Scope

This index records publishable evidence for the OpenClaw/DevClaw experiment
series supporting AI Operations Platform issue #9 and umbrella issue #8:

- AI Operations Platform issue #8:
  https://github.com/DimitryZH/ai-operations-platform/issues/8
- AI Operations Platform issue #9:
  https://github.com/DimitryZH/ai-operations-platform/issues/9

It is limited to evidence discovery, validation, classification, durable
references, readiness-state separation, and chronology support. It does not
make the final orchestration evaluation, architecture decision, ADR, vision
update, or downstream issue #10 recommendation.

Starting `main` SHA for this work: `28ce38da2db14b4b42684c81113cdb391960a327`.

## Discovery Method

The evidence was collected with a bounded two-pass process.

Pass 1 performed a shallow inventory of repository documentation, runtime
validation scripts, DevClaw workflow artifacts, and GitHub issue/PR state.

Pass 2 read only targeted sources needed to verify versions, stage ordering,
human approvals, stage results, worker-state claims, filesystem/Git/Docker
findings, sandbox and namespace findings, direct Codex continuation, final
validation, manual merge, and issue closeout.

GitHub issue, PR, review, comment, and commit state is treated as the
authoritative source for GitHub workflow facts. Agent-authored comments are
indexed as reported evidence unless corroborated by human comments, PR merge
state, commit state, or repository artifacts.

## Evidence Classification Rules

| Classification | Use |
| --- | --- |
| Direct evidence | A source directly records the fact being used, such as a GitHub PR merge state, a committed file, or a validation script output. |
| Reported evidence | A worker, operator, or closeout report states a result that is useful but not independently complete by itself. |
| Inference | A finding derived by comparing multiple sources or by interpreting a readiness boundary. |
| Decision input | Evidence relevant to the later architecture evaluation, without making the decision in this document. |

Each evidence item states what it proves and what it does not prove.

## Sensitivity Rules

| Sensitivity | Use |
| --- | --- |
| Public | Safe to publish directly as repository-relative paths, GitHub URLs, issue/PR numbers, or commit SHAs. |
| Internal | Useful operational evidence that may refer to VM/runtime behavior or sanitized local workflow artifacts. Contents should be summarized rather than copied wholesale. |
| Restricted | Evidence that may contain security posture, runtime internals, raw transcripts, local paths, credentials-adjacent context, or machine-specific details. Index only summarized findings and durable safe references. |

Do not reproduce access tokens, OAuth credentials, private keys, cookies,
complete environment dumps, raw session databases, raw SQLite files, raw worker
registries, private user information, full audit logs, long runtime logs, or
unnecessary machine-specific absolute paths.

## Readiness-State Model

| # | State | What It Means | Common False Equivalence |
| ---: | --- | --- | --- |
| 1 | Infrastructure available | VM, disk, network boundary, service units, and base runtime can exist. | Not worker readiness. |
| 2 | Gateway process running | The Gateway service process is active. | Not proof that it listens or accepts RPC. |
| 3 | Gateway listener available | A loopback listener is reachable. | Not proof that RPC calls work. |
| 4 | RPC ready | Gateway health/status RPCs respond. | Not proof that plugins or workers work. |
| 5 | Plugin loaded | OpenClaw reports DevClaw/Codex plugin loading. | Not command execution. |
| 6 | Dispatch accepted | DevClaw accepted a task/session request. | Not proof that a worker executed anything. |
| 7 | Worker session created | A session record exists. | Not proof of filesystem, Git, Docker, or API access. |
| 8 | Command executed | A minimal command ran inside the intended sandbox. | Not proof that real implementation capability exists. |
| 9 | Repository read completed | The worker read the needed repository and issue context. | Not proof of write, build, test, or push capability. |
| 10 | Repository mutation completed | Files were changed in the intended checkout. | Not proof that Git can commit or push. |
| 11 | Validation completed | Required tests or checks ran to completion. | Not proof of merge readiness without review. |
| 12 | Commit created | A local or remote commit exists. | Not proof that branch or PR was updated. |
| 13 | Branch pushed | The branch ref was updated on GitHub. | Not proof that PR metadata/reporting is correct. |
| 14 | Pull request updated | PR head/body/state was updated. | Not proof of merge or issue completion. |
| 15 | Task completed | Human-reviewed closeout confirms accepted scope. | Not a universal platform decision. |

Infrastructure readiness is not worker readiness. Gateway readiness is not
execution readiness. Plugin loading is not command execution. Dispatch
acceptance is not proof of execution. Session creation is not proof of
filesystem, Git, Docker, or API access. Worker identity is not authoritative
durable task state.

## Evidence Inventory

### Platform Vision

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| VISION-01 | 2026-07 platform docs | AI Operations Platform | Committed docs | `docs/architecture.md`; `docs/roadmap.md` | Direct evidence | Public | The platform goal was a GCP-first private runtime foundation with bounded human-reviewed workflows and known validation limits. | It does not decide the final orchestrator for issue #10. |
| VISION-02 | 2026-07 operating model | AI Operations Platform | Committed docs | `docs/operating-model.md`; `docs/security-model.md` | Direct evidence | Public | Human approval, least privilege, status-only observation, and no automatic merge/remediation were core guardrails. | It does not prove individual worker runs complied. |
| VISION-03 | Issue #8 umbrella | GitHub | Issue | https://github.com/DimitryZH/ai-operations-platform/issues/8 | Decision input | Public | The final OpenClaw/DevClaw evaluation is coordinated through an umbrella issue with child workstreams. | It does not complete the child evaluation work. |

### Infrastructure

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| INFRA-01 | Runtime foundation | AI Operations Platform | Committed docs and IaC paths | `gcp/stateful-agent-runtime/`; `docs/migration-closeout.md`; `docs/security-model.md` | Direct evidence | Public | The imported runtime foundation uses private VM, preserved disk, IAP-only access, Secret Manager, and systemd boundaries. | It does not prove current VM health on any later date. |
| INFRA-02 | Operator channel | AI Operations Platform | Committed docs | `gcp/stateful-agent-runtime/docs/telegram-status-only-operator-channel.md` | Direct evidence | Public | Telegram was status-only and explicitly had no approval or execution authority. | It does not prove Telegram was enabled in a specific environment. |
| INFRA-03 | Managed-service restart model | AI Operations Platform | Committed runtime notes | `gcp/stateful-agent-runtime/docs/implementation-notes.md`; `gcp/stateful-agent-runtime/docs/operations-runbook.md` | Direct evidence | Public | The Stateful Agent Runtime design makes systemd responsible for OpenClaw container restarts and documents restart/health validation as an operational step. | It does not prove a managed-service restart validation actually passed. |
| INFRA-04 | VM reboot state model | AI Operations Platform | Committed runtime docs | `gcp/agent-devbox/README.md`; `gcp/stateful-agent-runtime/docs/implementation-notes.md` | Direct evidence | Public | The Agent DevBox and Stateful Runtime documentation state that disk-backed runtime/workspace state is expected to survive VM reboot or instance recreation. | It does not prove a VM reboot persistence validation actually passed. |

### OpenClaw Runtime

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RUNTIME-01 | Runtime validation scripts | AI Operations Platform | Committed validation scripts | `gcp/agent-devbox/runtime/validate-openclaw-gateway.sh`; `gcp/agent-devbox/runtime/validate-openclaw-devclaw.sh` | Direct evidence | Public | The intended managed Gateway checks include loopback listener, RPC health, plugin loading, OpenClaw `2026.7.1`, DevClaw `1.6.10`, compatibility revision `aiops-1`, disabled heartbeat, and sequential project execution. | It does not prove every future worker command can execute. |

### DevClaw Integration

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RUNTIME-02 | Issue #16 runtime evidence | AI Operations Platform | Operator artifact summary | `ops/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/README.md` | Reported evidence | Internal | The issue #16 artifact set retained dispatch, runtime diagnosis, recovery, and direct completion trail while omitting raw oversized logs. | It does not replace GitHub issue/PR state. |

### Compatibility

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| COMPAT-01 | Compatibility overlay | AI Operations Platform | Committed runtime checks | `gcp/agent-devbox/runtime/devclaw-compat/`; `gcp/agent-devbox/runtime/validate-openclaw-devclaw.sh` | Direct evidence | Public | DevClaw integration depended on a reviewed compatibility overlay and an expected 23-tool contract. | It does not prove semantic correctness of every tool. |

### Identity and Authentication

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AUTH-01 | Gateway auth validation | AI Operations Platform | Committed validation script | `gcp/agent-devbox/runtime/validate-openclaw-gateway.sh` | Direct evidence | Restricted | The validation contract required restricted Gateway token files, OpenAI OAuth marker when enabled, no API-key profiles, and absence of common unsafe credential environment variables. | It does not publish or verify secret values. |

### GitHub Integration

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GITHUB-01 | GitHub workflow state | GitHub | Issues, PRs, commits | AppModLab PRs #6, #7, #9, #11, #15, #17; AI Ops issues #8 and #9 | Direct evidence | Public | GitHub provided durable issue, branch, PR, head SHA, merge commit, comment, and closeout state. | It does not make agent-authored reports independently true. |

### Worker Execution

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WORKER-01 | Validated role model | AI Operations Platform and Application Modernization Lab | Case study plus GitHub state | `docs/case-studies/experiment-06-online-boutique-compose-to-aspire.md`; https://github.com/DimitryZH/application-modernization-lab/issues/5 | Direct evidence | Public | Architect/developer/tester separation, human gates, and GitHub durable workflow state worked for Experiment 06. | It does not prove the same worker runtime remained reliable later. |

### Workflow Governance

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GOVERNANCE-01 | Human approval gates | AI Operations Platform and GitHub | Docs and issue comments | `docs/operating-model.md`; AppModLab issue comments for #5, #8, #10, #14, #16 | Direct evidence | Public | Architecture, implementation, correction, testing, merge, and skill application were gated by human approval. | It does not prove workers stopped correctly without checking each stage. |
| GOVERNANCE-02 | Disabled autonomy | AI Operations Platform | Validation script | `gcp/agent-devbox/runtime/validate-openclaw-gateway.sh` | Direct evidence | Public | Runtime guardrails expected disabled heartbeat and sequential DevClaw project execution. | It does not prove old experimental heartbeat transcripts were impossible in all contexts. |

### Recovery

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RECOVERY-01 | 2026-08-01 runtime diagnosis | AI Operations Platform | Runtime diagnostic artifact | `ops/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics/post-reboot-minimal-smoke-status.json`; `ops/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics/results/summary.txt` | Direct evidence | Restricted | A minimal read-only subagent smoke failed before useful command execution with `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`. | It does not prove the application implementation was invalid. |
| RECOVERY-02 | 2026-08-01 bounded fix validation | AI Operations Platform | Runtime diagnostic summary | `ops/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/runtime-diagnostics/results/narrow-userns-apparmor-validation-20260801T151310Z/validation-summary.json` | Direct evidence | Restricted | A narrow AppArmor/userns recovery allowed a minimal sandboxed command to execute under the Codex/OpenClaw path. | It did not establish full developer workflow capability. |

### Security and Permissions

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SECURITY-01 | 2026-08-01 capability preflight | AI Operations Platform | Runtime recovery artifact | `ops/devclaw-workflows/application-modernization-lab/issue-16/2026-07-31/correction-recovery/execution-capability-current.json` | Direct evidence | Restricted | Later capability checking still encountered workflow capability concerns, including an active Git-process boundary in the captured run. | It does not show final implementation failure; direct Codex later completed validation. |

### Knowledge Reuse

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| KNOWLEDGE-01 | Experiment 06 closeout | AI Operations Platform and AppModLab | Case study, PR, issue closeout | `docs/case-studies/experiment-06-online-boutique-compose-to-aspire.md`; https://github.com/DimitryZH/application-modernization-lab/pull/7 | Direct evidence | Public | Knowledge review produced an operator-reviewed `compose-to-aspire-migration` skill artifact after merge. | It does not prove the skill was complete for all future migrations. |
| KNOWLEDGE-02 | Experiment 07B tester report | GitHub | Issue comment | https://github.com/DimitryZH/application-modernization-lab/issues/10#issuecomment-5108818410 | Reported evidence | Public | The migration skill helped structure validation but did not replace repository-specific inspection and runtime probing. | It does not certify the skill as generally sufficient. |

### Experiment 06

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXP06-01 | 2026-07-20 to 2026-07-21 | Application Modernization Lab | Issue and PR metadata | https://github.com/DimitryZH/application-modernization-lab/issues/5; https://github.com/DimitryZH/application-modernization-lab/pull/6 | Direct evidence | Public | Online Boutique Compose-to-Aspire PR #6 merged on 2026-07-21 with head `955a38062c847b4ecd418ecd9c7af20b438882d9` and merge commit `7ccfcbd649448a35f7d52c7f04c8680cb5ddae17`. | It does not prove later DevClaw runtime reliability. |
| EXP06-02 | 2026-07-21 closeout | Application Modernization Lab | PR and issue closeout | https://github.com/DimitryZH/application-modernization-lab/pull/7; https://github.com/DimitryZH/application-modernization-lab/issues/5#issuecomment-5038470419 | Direct evidence | Public | Experiment 06 closeout docs and skill review merged via PR #7 with merge commit `2a641624342f06c959a5ffa100cb651ea5de5ada`; issue #5 closed completed. | It does not prove future skill reuse without validation. |

### Experiment 07

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXP07-01 | 2026-07-22 to 2026-07-27 | Application Modernization Lab | Issue, comment, PR metadata | https://github.com/DimitryZH/application-modernization-lab/issues/8; https://github.com/DimitryZH/application-modernization-lab/pull/9 | Direct evidence | Public | Bank of Anthos Compose baseline PR #9 merged with head `71d059bf5871d2bc5776a9a26688a3e410f78f62` and merge commit `3de8845412853525aeb77d85db23f2d14b1bfc73`. | It does not include the Aspire migration. |
| EXP07-02 | 2026-07-28 | Application Modernization Lab | Issue comments and PR metadata | https://github.com/DimitryZH/application-modernization-lab/issues/10; https://github.com/DimitryZH/application-modernization-lab/pull/11 | Direct evidence | Public | Bank of Anthos Aspire PR #11 merged with head `8649b3be4bc63db80a1e185f42a0dbd5d0c21aa1` and merge commit `5976290742724acfef15766b53dba39f7a8484e9`; tester report was PASS. | It does not prove all future Aspire targets are covered by the existing skill. |

### Experiment 08

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXP08-01 | 2026-07-30 to 2026-07-31 | Application Modernization Lab | Issue comments and PR metadata | https://github.com/DimitryZH/application-modernization-lab/issues/14; https://github.com/DimitryZH/application-modernization-lab/pull/15 | Direct evidence | Public | AKS Store Demo Compose baseline PR #15 merged with head `83f1f255f111ee0562cab154c7c4ddf312d848b9` and merge commit `38ab6b49868c8b4e490e2464d749f8b0fa92e905`. | It does not implement Aspire. |
| EXP08-02 | 2026-07-31 to 2026-08-02 | Application Modernization Lab | Issue comments and PR metadata | https://github.com/DimitryZH/application-modernization-lab/issues/16; https://github.com/DimitryZH/application-modernization-lab/pull/17 | Direct evidence | Public | AKS Store Demo Aspire PR #17 merged with final head `bdad00156bd9d6035dc400d56b9a5d39fd39d0e7` and merge commit `fe23e445c39ce0b7636641a14bacef671482fad5`. | It does not by itself decide the AI Operations Platform orchestration architecture. |

### Direct Codex Completion

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CODEX-01 | 2026-08-01 final validation | Application Modernization Lab | Human approval and agent report comments | https://github.com/DimitryZH/application-modernization-lab/issues/16#issuecomment-5154853686; https://github.com/DimitryZH/application-modernization-lab/issues/16#issuecomment-5155082279; https://github.com/DimitryZH/application-modernization-lab/issues/16#issuecomment-5155261075 | Direct evidence for approval, reported evidence for validation details | Public | Human approved direct Codex final validation/correction with no OpenClaw/DevClaw workers; final reports state PASS on the final PR head. | It does not make this repository's issue #10 architecture decision. |

### Final Closeout

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CODEX-02 | 2026-08-02 final closeout | Application Modernization Lab | Human closeout comment | https://github.com/DimitryZH/application-modernization-lab/issues/16#issuecomment-5158539452 | Direct evidence | Public | Human closeout accepted the 08B migration, documented merge commit and residual limitation, and recorded an execution-model conclusion. | The conclusion is an input to issue #10, not a decision made by this index. |

### Architecture Decision Inputs

| ID | Date/Stage | Repository/System | Source Type | Durable Source Reference | Classification | Sensitivity | Supported Finding | Does Not Prove |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DECISION-INPUT-01 | Architecture decision point | AI Operations Platform and AppModLab | Umbrella issue and experiment closeouts | AI Ops issue #8; AppModLab issue #16 closeout | Decision input | Public | Later evaluation should preserve both successful workflow concepts and later reliability failures. | It does not select the next orchestrator. |

## Contradictory or Unresolved Evidence

| Topic | Sources | Preserved Conflict or Limitation |
| --- | --- | --- |
| Runtime readiness vs worker execution | RUNTIME-01, RECOVERY-01, RECOVERY-02 | Gateway/plugin validation can pass while sandboxed worker command execution later fails. A narrow fix enabled a minimal smoke, but full workflow readiness remained a separate question. |
| Worker reports vs durable GitHub state | WORKER-01, GITHUB-01, EXP08-02, CODEX-01 | Agent-authored comments are useful, but PR metadata, commit SHAs, human review, and issue closeout are the authoritative durable workflow state. |
| Skill reuse value vs completeness | KNOWLEDGE-01, KNOWLEDGE-02, EXP07-02 | The Compose-to-Aspire skill provided useful method structure but still required target-specific inspection and did not guarantee success for Experiment 08. |
| Experiment result vs orchestration result | EXP08-02, CODEX-02, DECISION-INPUT-01 | Experiment 08B's Aspire migration was accepted as valid even though the worker orchestration model became too costly and unreliable for the remaining work. |
| Sandbox recovery scope | RECOVERY-01, RECOVERY-02, SECURITY-01 | A post-fix minimal command could run, but that did not prove full filesystem, Git, Docker, push, PR, and validation capability for a senior developer workflow. |
| Managed-service restart validation | INFRA-03 | The repository contains design/runbook evidence for systemd-managed restart behavior, but no committed or GitHub-linked direct PASS artifact was found for a successful managed-service restart persistence validation. |
| VM reboot persistence validation | INFRA-04 | The repository contains design evidence that disk-backed state should survive reboot, but no committed or GitHub-linked direct PASS artifact was found for a successful VM reboot persistence validation. |

## Publication Boundary

This index publishes only sanitized references, summaries, GitHub URLs, issue/PR
numbers, commit SHAs, and repository-relative paths. It intentionally does not
copy raw Gateway logs, worker transcripts, runtime databases, credentials,
tokens, OAuth data, private keys, cookies, local environment dumps, or complete
session registries.

Restricted evidence is indexed by safe repository-relative artifact paths and
summarized findings only. Future readers should inspect those artifacts with the
same boundary before quoting or republishing them.

## Guidance for Later Evaluation Report

The later evaluation for issue #10 should:

- use this index and the chronology as the starting evidence map;
- preserve positive evidence for infrastructure, Gateway runtime, GitHub
  integration, role separation, human gates, and successful Experiments 06 and
  07;
- preserve negative evidence for worker runtime, sandbox, filesystem, Git,
  Docker, recovery, cost, and workflow-control failures;
- avoid claiming that all OpenClaw/DevClaw experiments failed;
- avoid claiming OpenClaw or DevClaw is universally unusable;
- restrict conclusions to the evaluated versions, integration, environment,
  and architecture;
- separate the accepted Application Modernization Lab migration outcomes from
  the AI Operations Platform orchestration decision;
- not treat this issue #9 documentation package as the final architecture
  recommendation.
