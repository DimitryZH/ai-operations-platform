# OpenClaw/DevClaw Experiment Chronology

This chronology supports AI Operations Platform issue #9. It references the
evidence IDs in `docs/research/openclaw-devclaw/evidence-index.md` instead of
duplicating the full evidence model. It preserves stage ordering and uses exact
dates only where supported by GitHub or committed evidence.

## Chronology

| # | Date or Stage | Event | Evidence IDs |
| ---: | --- | --- | --- |
| 1 | Initial platform objective | AI Operations Platform established a GCP-first private runtime foundation and a human-reviewed operating model for assisted operations. | VISION-01, VISION-02, INFRA-01 |
| 2 | GCP DevBox preparation | The repository retained runtime foundation and Agent DevBox validation paths for OpenClaw/DevClaw installation and checks. | INFRA-01, RUNTIME-01 |
| 3 | Persistent OpenClaw Gateway | Managed Gateway validation required systemd ownership, loopback-only listener, RPC health, restricted token files, and plugin health checks. | RUNTIME-01, AUTH-01 |
| 4 | Managed-service operation | The runtime model used systemd-managed services and preserved disk state for the private VM foundation. | INFRA-01, RUNTIME-01 |
| 5 | Managed-service restart model | Runtime documentation shows a systemd-owned restart model and runbook validation expectations for the OpenClaw service, but no direct successful restart-persistence PASS artifact was found in the reviewed repository or GitHub evidence. | INFRA-03 |
| 6 | VM reboot state model | Runtime documentation states that disk-backed Agent DevBox and Stateful Runtime state should survive VM reboot or instance recreation, but no direct successful reboot-persistence PASS artifact was found in the reviewed repository or GitHub evidence. Later reboot diagnostics instead captured a worker sandbox failure boundary. | INFRA-04, RECOVERY-01 |
| 7 | OpenAI OAuth and model validation | Gateway validation expected OpenAI OAuth mode, `openai/gpt-5.5`, no OpenAI API-key profile, and no unsafe credential environment variables when model provider mode was enabled. | AUTH-01, RUNTIME-01 |
| 8 | DevClaw installation | DevClaw validation pinned OpenClaw `2026.7.1`, DevClaw `1.6.10`, compatibility revision `aiops-1`, and a 23-tool plugin contract. | RUNTIME-01, COMPAT-01 |
| 9 | Compatibility overlay development | The DevClaw compatibility overlay became part of the controlled runtime contract and was validated against the installed plugin manifest. | COMPAT-01 |
| 10 | GitHub App and token-broker integration | Workflow evidence used GitHub issues, PRs, branch heads, merge commits, labels/comments, and restricted token handling as durable coordination state. | GITHUB-01, AUTH-01, GOVERNANCE-01 |
| 11 | Architecture-worker validation | Experiment 06 demonstrated an architecture report and human approval gate before implementation. | WORKER-01, EXP06-01, GOVERNANCE-01 |
| 12 | Developer and tester workflow validation | Experiment 06 completed developer implementation, independent tester validation, correction, human review, merge, and closeout. | EXP06-01, EXP06-02, WORKER-01 |
| 13 | Experiment 06 | Online Boutique Compose-to-Aspire PR #6 merged on 2026-07-21 at merge commit `7ccfcbd649448a35f7d52c7f04c8680cb5ddae17`; closeout PR #7 later merged at `2a641624342f06c959a5ffa100cb651ea5de5ada`. | EXP06-01, EXP06-02 |
| 14 | Experiment 07A | Bank of Anthos Compose baseline used the controlled DevClaw workflow and merged through PR #9 at merge commit `3de8845412853525aeb77d85db23f2d14b1bfc73`. | EXP07-01 |
| 15 | Experiment 07B | Bank of Anthos Compose-to-Aspire used the accepted 07A baseline, skill-guided methodology, tester PASS, and merged through PR #11 at merge commit `5976290742724acfef15766b53dba39f7a8484e9`. | EXP07-02, KNOWLEDGE-02 |
| 16 | Skill knowledge review | Experiment 06 closeout recorded an operator-reviewed `compose-to-aspire-migration` skill; later 07B testing found it useful but still incomplete for target-specific details. | KNOWLEDGE-01, KNOWLEDGE-02 |
| 17 | Experiment 08 architecture phase | Issue #14 architecture research for the AKS Store Demo Compose baseline stopped at Human Baseline Approval; issue #16 architecture research then designed the 08B Aspire migration and stopped for Human Aspire Architecture Approval. | EXP08-01, EXP08-02, GOVERNANCE-01 |
| 18 | Experiment 08 implementation phase | Experiment 08A merged the accepted Compose baseline through PR #15 at merge commit `38ab6b49868c8b4e490e2464d749f8b0fa92e905`; Experiment 08B later targeted the accepted baseline through PR #17. | EXP08-01, EXP08-02 |
| 19 | Worker-runtime and recovery failures | During issue #16, a minimal read-only subagent smoke reproduced `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`, showing failure before meaningful command execution. | RECOVERY-01 |
| 20 | Sandbox, AppArmor, Bubblewrap, namespace, filesystem, Git, and Docker investigation | Runtime diagnostics separated Bubblewrap/AppArmor/userns behavior from repository implementation correctness. A narrow recovery made a minimal command pass, but capability evidence still had workflow-level limitations. | RECOVERY-01, RECOVERY-02, SECURITY-01 |
| 21 | Direct Codex continuation under human approval | Human approval changed the 08B execution model to direct Codex only, explicitly forbidding OpenClaw/DevClaw workers, subagents, developer sessions, tester sessions, dispatch, and worker capability probes. | CODEX-01 |
| 22 | Final Experiment 08 correction and validation | Direct Codex reports for issue #16 recorded final PR head `bdad00156bd9d6035dc400d56b9a5d39fd39d0e7`, complete validation PASS, no worker use, and residual limitations. | CODEX-01, EXP08-02 |
| 23 | Human review | Human closeout for issue #16 accepted the final Experiment 08B result and documented the residual ownership-guardrail limitation as non-blocking. | CODEX-02 |
| 24 | Manual PR merge | PR #17 merged into `main` on 2026-08-02 with merge commit `fe23e445c39ce0b7636641a14bacef671482fad5`; issue #16 closeout recorded final COMPLETE status. | EXP08-02, CODEX-02 |
| 25 | Final issue closeout | The Application Modernization Lab retained the valid Aspire migration result while recording worker orchestration reliability and cost concerns. | CODEX-02, DECISION-INPUT-01 |
| 26 | Architecture decision point | AI Operations Platform issue #8 coordinates the documentation closeout, while downstream issue #10 produces the evidence-backed orchestration evaluation and recommendation for a later Architecture Decision Record. This chronology stops before both the evaluation conclusion and the formal architecture decision. | VISION-03, DECISION-INPUT-01 |

## Readiness Lessons Preserved by the Chronology

- Infrastructure availability and Gateway health were useful milestones, but
  they were not enough to prove worker command execution.
- Dispatch acceptance and worker session creation were not durable task
  completion evidence.
- Minimal smoke success was not enough to prove filesystem, Git, Docker,
  GitHub write, validation, branch push, and PR update capability.
- Human approvals and GitHub merge/closeout state are the durable workflow
  boundaries.
- The Application Modernization Lab migration results and the AI Operations
  Platform orchestration decision must remain separate.

## Out of Scope

This chronology does not implement issue #10, write the final orchestration
evaluation, choose the next orchestrator, create an ADR, or update the AI
Operations Platform Vision.
