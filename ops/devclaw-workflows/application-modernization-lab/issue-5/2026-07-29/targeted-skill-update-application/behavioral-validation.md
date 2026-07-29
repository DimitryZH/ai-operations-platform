# Behavioral Validation

## Method

Three new isolated foreground OpenClaw sessions consumed the active `compose-to-aspire-migration` skill after application. The sessions received neutral scenario prompts only. They did not receive the approved patch, required after-state checksums, or expected wording.

Each prompt explicitly required read-only behavior and prohibited file, repository, GitHub, infrastructure, label, and runtime-state mutation.

## Scenario A: Architecture Planning

- Role: Architecture Planning.
- Session key: `agent:main:issue-5-behavioral-scenario-a-20260729T192953Z`.
- Agent session identifier: `514a7866-ed86-4e94-ba17-f015c2c47bcb`.
- Created: `2026-07-29T19:29:53Z`.
- Completed: `2026-07-29T19:32:03Z`.
- Reused session: no.
- Result: pass.
- Supporting active skill sections:
  - `references/compose-inventory.md` / Compose Input Inventory.
  - `references/aspire-modeling.md` / AppHost Structure Guidance.
  - `references/validation-checklist.md` / Compose-Versus-Aspire Comparison.

Assessment:

- Identified application-visible runtime assumptions including hostname, working directory, numeric user, entrypoint, command, runtime flags, aliases, and endpoint exposure.
- Did not reduce analysis to environment variables alone.
- Recommended preservation or approved validation of differences.
- Did not introduce source-application-specific content.

Evidence extract:

> Preserve application-visible runtime assumptions: hostname behavior, working directory, numeric user identity, entrypoint, command, and runtime flags.

## Scenario B: Stateful Validation Planning

- Role: Stateful Validation Planning.
- Session key: `agent:main:issue-5-behavioral-scenario-b-20260729T192953Z`.
- Agent session identifier: `423fbafd-0eb4-4009-b1e7-77ea730da4a0`.
- Created: `2026-07-29T19:32:03Z`.
- Completed: `2026-07-29T19:33:42Z`.
- Reused session: no.
- Result: pass.
- Supporting active skill sections:
  - `references/validation-checklist.md` / Stateful Dependency Validation.
  - `references/validation-checklist.md` / Evidence Requirements.

Assessment:

- Required current-run application evidence through normal UI/API workflow.
- Included controlled AppHost stop.
- Explicitly preserved configured durable storage.
- Restarted the AppHost and verified the same application-level evidence.
- Distinguished preserved-storage restart from full reset.
- Rejected volume existence or seeded data alone as sufficient evidence.

Evidence extract:

> Before restart: create record `X` with marker `Y`. After restart: GET/list/search through the app returns the same `X` and `Y`.

## Scenario C: Compose/Aspire Comparison

- Role: Compose/Aspire Comparison.
- Session key: `agent:main:issue-5-behavioral-scenario-c-20260729T192953Z`.
- Agent session identifier: `545400b8-86f1-40e7-b849-bc5cea421399`.
- Created: `2026-07-29T19:33:42Z`.
- Completed: `2026-07-29T19:35:28Z`.
- Reused session: no.
- Result: pass.
- Supporting active skill sections:
  - `references/compose-inventory.md` / Baseline Freeze Checklist.
  - `references/validation-checklist.md` / Compose-Versus-Aspire Comparison.
  - `references/validation-checklist.md` / Concurrent Runtime Isolation Validation.

Assessment:

- Identified relative path resolution risk for copied Compose files and overrides.
- Required retaining the original Compose project directory and effective Compose file order.
- Recommended preserving original project-directory resolution or using explicitly equivalent absolute paths.
- Kept concurrent Compose/Aspire comparison conditional rather than mandatory for every migration.

Evidence extract:

> Scenario C is high-risk for false comparison results because copying Compose files or overrides can silently change how relative bind mounts resolve.

## Overall Behavioral Result

All three behavioral scenarios passed. No corrective skill change is required.
