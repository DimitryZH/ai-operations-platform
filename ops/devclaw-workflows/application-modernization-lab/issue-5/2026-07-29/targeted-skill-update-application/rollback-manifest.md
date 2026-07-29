# Rollback Manifest

## Protected Snapshot

- Snapshot identifier: `compose-to-aspire-migration-before-compose-to-aspire-migration-targeted-update-20260729-20260729T192551Z`.
- Created at: `2026-07-29T19:25:51Z`.
- Protected snapshot location: `/home/devclaw-svc/.openclaw/skill-governance/rollback-snapshots/compose-to-aspire-migration-before-compose-to-aspire-migration-targeted-update-20260729-20260729T192551Z`.
- Protected operation directory: `/home/devclaw-svc/.openclaw/skill-governance/applications/compose-to-aspire-migration-targeted-update-20260729-application-20260729T192551Z`.
- Snapshot owner/mode: protected under `devclaw-svc` OpenClaw state, mode `700`.
- Full rollback file copies are not committed to this repository.

## Preserved Files

```text
SKILL.md
references/aspire-modeling.md
references/compose-inventory.md
references/failure-modes.md
references/validation-checklist.md
```

## Before-State Checksums

| File | SHA-256 |
| --- | --- |
| `SKILL.md` | `d4631c7a987092f9247a615d4917cbd55fb453f543ca93273b506c35ffb6469f` |
| `references/aspire-modeling.md` | `97f0077d386f5ecae055428fae9961a33e3e8f247a3ee346eb6606b1ea02fe03` |
| `references/compose-inventory.md` | `832c0ae2f89403d8e87a48753888c46a44f36b642246a19dc78fd5c35aedd11d` |
| `references/failure-modes.md` | `0eca396d7834146c57c3651f6d433160ed2c15c8870753232f7adf18ad44ed77` |
| `references/validation-checklist.md` | `e0e66de52684c02128414b2eb9544a6e25438324c0c04174326afafd20420fb3` |

## Ownership And Mode Summary

- Active skill directory: `devclaw-svc:devclaw-svc 700`.
- Active `references/` directory: `devclaw-svc:devclaw-svc 700`.
- Active files: `devclaw-svc:devclaw-svc 600`.

## Restoration Procedure

If operator-approved rollback is required, restore each preserved file from the protected snapshot with metadata preservation:

```bash
cp -p "$SNAPSHOT_DIR/files/SKILL.md" "$SKILL_DIR/SKILL.md"
cp -p "$SNAPSHOT_DIR/files/references/aspire-modeling.md" "$SKILL_DIR/references/aspire-modeling.md"
cp -p "$SNAPSHOT_DIR/files/references/compose-inventory.md" "$SKILL_DIR/references/compose-inventory.md"
cp -p "$SNAPSHOT_DIR/files/references/failure-modes.md" "$SKILL_DIR/references/failure-modes.md"
cp -p "$SNAPSHOT_DIR/files/references/validation-checklist.md" "$SKILL_DIR/references/validation-checklist.md"
```

## Verification Procedure

After restore, run `sha256sum` for all five active files and compare against the before-state checksum table above. Confirm owner/mode remains `devclaw-svc:devclaw-svc 600` for files and `700` for directories.

## Rollback Status

Rollback was not required for the final successful application operation. Earlier guarded attempts either stopped before active mutation or restored the before-state as designed while tuning the diff comparison mechanism.
