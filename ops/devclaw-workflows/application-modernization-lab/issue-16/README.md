# Issue 16 Operator Artifacts

This directory contains persistent operator artifacts for the controlled
DevClaw workflow used on `DimitryZH/application-modernization-lab` issue #16.

The artifacts are retained for auditability and reuse of the workflow mechanics.
They are not implementation source for Experiment 08B.

## Contents

- `2026-07-31/`: dated workflow run for Experiment 08B.

## Public Repository Hygiene

The committed set keeps dispatch, inspection, recovery, rollback, and helper
scripts plus compact result snapshots. Raw oversized runtime dumps, extracted
local implementation worktrees, generated build output, and transient copied
source archives are intentionally omitted.

Do not rerun any script blindly against another issue. Review the target issue,
repository, VM, gateway URL, token-broker path, branch, session key, and approval
state before use.
