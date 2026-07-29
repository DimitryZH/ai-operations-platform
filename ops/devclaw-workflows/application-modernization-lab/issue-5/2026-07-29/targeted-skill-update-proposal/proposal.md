# Pending Targeted Update Proposal

## Status

`pending`

This proposal is not applied. Application requires separate explicit operator approval.

## Objective

Prepare a bounded in-place update to the existing `compose-to-aspire-migration` skill so it captures three reusable migration lessons from the merged Knowledge Review without adding application-specific or orchestration-specific content.

## Source Knowledge Review

- Source repository: `DimitryZH/application-modernization-lab`.
- Review document: `experiments/07-bank-of-anthos/compose-to-aspire-skill-knowledge-review.md`.
- Review PR: #13, merged on `2026-07-29T15:43:17Z`.
- Review decision: `TARGETED SKILL UPDATE RECOMMENDED`.
- Source issue for this proposal: AI Operations Platform issue #5.

## Bounded Scope

The proposed future active-skill update is limited to exactly three areas:

1. Container runtime assumptions.
2. Controlled stateful AppHost restart.
3. Relative bind-mount and project-directory semantics.

The proposal updates the existing skill in place. It does not create a replacement or duplicate skill.

## Files And Sections Proposed For Modification

| Active skill file | Section | Reason |
| --- | --- | --- |
| `references/compose-inventory.md` | `Baseline Freeze Checklist`, `Compose Input Inventory` | Record project-directory path resolution, runtime assumptions, and bind-mount semantics during inventory. |
| `references/aspire-modeling.md` | `AppHost Structure Guidance` | Require modeling to preserve or explicitly validate application-visible runtime assumptions. |
| `references/validation-checklist.md` | `Stateful Dependency Validation`, `Compose-Versus-Aspire Comparison` | Require controlled preserved-storage restart validation and relative bind-mount resolution checks when applicable. |

Intentionally unchanged:

- `SKILL.md`
- `references/failure-modes.md`

## Exact Proposed Wording

### `references/compose-inventory.md`

Add to `Baseline Freeze Checklist`:

```markdown
- Record the original Compose project directory used to resolve relative paths.
```

Add to `Compose Input Inventory`:

```markdown
| Application-visible runtime assumptions | Hostname, working directory, user or group identity, container identity values, environment-derived identity, and language or runtime flags that may affect startup or behavior. |
```

Revise the `Volumes` row to:

```markdown
| Volumes | Named volumes, bind mounts, relative bind-mount source paths and project-directory resolution, persistence expectations, and cleanup behavior. |
```

### `references/aspire-modeling.md`

Add to `AppHost Structure Guidance`:

```markdown
- Preserve application-visible runtime assumptions such as hostname, command and entrypoint behavior, working directory, user or group identity, container identity values, and language or runtime flags, or explicitly validate an approved difference.
```

### `references/validation-checklist.md`

Add to `Stateful Dependency Validation`:

```markdown
- When persistence is in scope, create current-run application data, stop the AppHost in a controlled manner while preserving configured durable storage, restart the AppHost, and verify the same application-level evidence after restart.
- Do not treat volume existence, seeded data, or container restart status alone as sufficient persistence evidence.
- Document full reset behavior separately from preserved-storage restart behavior.
```

Add to `Compose-Versus-Aspire Comparison`:

```markdown
- Relative bind-mount resolution when temporary Compose files, overrides, copied configurations, or concurrent comparison runs are used. Confirm relative bind mounts still resolve against the intended original Compose project directory or are replaced by explicitly equivalent paths.
```

## Evidence Mapping

| Proposed change | Knowledge Review support | Reusable benefit |
| --- | --- | --- |
| Runtime assumptions in inventory and modeling | Review candidate 1 identified hidden assumptions in hostname, command, working directory, user/group, identity values, environment-derived identity, and runtime flags. | Reduces rediscovery and prevents image-based migrations from dropping application-visible runtime assumptions. |
| Controlled stateful restart validation | Review candidate 2 identified the need to prove state survives controlled AppHost stop/start with configured storage preserved. | Prevents false confidence from seeded data, volume existence, or process/container state alone. |
| Relative bind-mount project-directory semantics | Review candidate 3 identified path-resolution risk when temporary Compose files, overrides, copied configs, or concurrent comparisons are used. | Prevents false passes or false failures caused by bind mounts resolving against the wrong directory. |

## Expected Reusable Benefit

The update keeps the existing skill concise while making three recurring migration checks explicit. The guidance should help future migrations preserve runtime-sensitive image behavior, prove durable state through application evidence, and avoid path-resolution mistakes during Compose/Aspire comparisons.

## Overfitting Analysis

Overfitting risk is low because the wording describes generic migration methodology and avoids source application names, service names, hostnames, credentials, image digests, seeded values, SQL, concrete volume names, temporary paths, commands, issue numbers, worker names, session keys, DevClaw labels, and OpenClaw Gateway mechanics.

The relative bind-mount wording is intentionally conditional on temporary Compose files, overrides, copied configurations, or concurrent comparison runs. It does not require every migration to use a specific comparison command or directory layout.

## Exclusions

Excluded from the proposed reusable skill wording:

- Source application service names.
- Application-specific hostnames.
- Credentials or seeded account values.
- SQL statements or transaction values.
- Image digests.
- Concrete database or volume names.
- Issue or pull-request numbers.
- Worker names or session keys.
- DevClaw labels or workflow transitions.
- GitHub token broker behavior.
- OpenClaw Gateway mechanics.
- One-time recovery commands.
- Temporary experiment paths or commands.
- Skill Workshop operating instructions.

## Unrelated Observations Excluded

- Existing failure-mode guidance could eventually mention runtime assumptions, but that would duplicate the targeted reference edits and is not required for this proposal.
- The main `SKILL.md` could add another validation bullet, but the reference files are the better location for detailed operational guidance.
- Future live reuse validation should be recorded after the skill is applied and used on a separate migration target; it is outside this pending proposal.

## Expected After-State

Expected affected files:

- `references/compose-inventory.md`
- `references/aspire-modeling.md`
- `references/validation-checklist.md`

Expected unchanged files:

- `SKILL.md`
- `references/failure-modes.md`

Expected checksums calculated from the private proposed-state copy:

| File | Expected SHA-256 |
| --- | --- |
| `SKILL.md` | `d4631c7a987092f9247a615d4917cbd55fb453f543ca93273b506c35ffb6469f` |
| `references/aspire-modeling.md` | `7efba9137e79800ce52544d0f4a2346dc2721384e3a30a7d916ebb95af57acda` |
| `references/compose-inventory.md` | `b06db062dfda05871f653df588ec142ad2f68df2a9c158d417c705d84861b6fc` |
| `references/failure-modes.md` | `0eca396d7834146c57c3651f6d433160ed2c15c8870753232f7adf18ad44ed77` |
| `references/validation-checklist.md` | `d5c9696448e243acfaa941a5eb274af80f730d4ae3b6ecf6216babe90f85ddb7` |

## Rollback Plan

Because this package is pending and non-applied, rollback before approval is a normal revert of the repository documentation commit.

If an operator later approves and applies the proposal, rollback should use the active skill governance process and restore the verified before-state checksums from `baseline-report.md`. Active skill files must not be edited ad hoc.
