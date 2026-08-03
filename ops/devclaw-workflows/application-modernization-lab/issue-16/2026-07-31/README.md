# Issue 16 DevClaw Workflow Artifacts

Persistent operator artifacts for the controlled DevClaw workflow on
Application Modernization Lab issue #16.

## Scope

- Repository: `DimitryZH/application-modernization-lab`
- Issue: `#16`
- Experiment: `08B`
- Stages covered: Aspire architecture research, developer dispatch/recovery,
  runtime sandbox diagnosis, targeted correction recovery, and direct Codex
  completion after the execution model changed.
- DevClaw project: `application-modernization-lab`
- Agent DevBox checkout: `/workspace/repos/application-modernization-lab`

## Layout

- `context/`: issue/PR context snapshots used to keep later recovery work bound
  to the authoritative GitHub contract.
- `scripts/`: dispatch, preflight, inspection, recovery, and helper scripts.
- `results/`: read-only snapshots and dispatch/preflight results copied from the
  Agent DevBox.
- `runtime-diagnostics/`: bounded evidence and recovery scripts for the
  Bubblewrap/AppArmor/userns worker runtime failure.
- `correction-recovery/`: preservation evidence for uncommitted PR #17
  correction work before continuation.

These files are audit and reusable operator artifacts. Do not rerun them blindly
for another issue.

## Cleanup Notes

Before committing this public artifact set, temporary local implementation
worktrees, generated build output, copied source tarballs, and large raw runtime
log dumps were removed. The retained files are sufficient to reconstruct the
workflow decisions, dispatches, runtime diagnosis, approved recovery operations,
and final direct completion trail without committing duplicate application
source or oversized transient logs.
