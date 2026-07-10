# Stateful Agent Runtime Backup And Restore

**Status:** Imported backup and isolated restore operating model.
**Important:** Keep the runtime private, single-writer, and token-protected.
Do not print secret values in terminals, logs, tickets, commits, or chat.

## Backup Model

The authoritative OpenClaw state boundary is the preserved ext4 disk mounted at
`/var/lib/openclaw`.

Accepted daily backup model:

- standard crash-consistent scheduled snapshots of the authoritative state disk
- snapshot schedule managed by the reviewed state-disk resource policy

Accepted risky-upgrade or migration backup model:

- create a manual application-consistent snapshot
- stop `openclaw.service`
- flush filesystem buffers with `sync`
- create the manual snapshot only after the runtime is quiesced

This separates routine daily backup from higher-control maintenance backup.

## Restore Model

Accepted restore flow:

1. Select one snapshot.
2. Create one restored disk from that snapshot.
3. Create one temporary standalone recovery VM with no public IP.
4. Attach the restored disk only to the recovery VM.
5. Mount the restored disk at `/var/lib/openclaw`.
6. Start one isolated recovery runtime.
7. Validate locally before considering any optional external access.

The recovery VM is not the production stateful managed instance group and does
not replace the production authoritative disk automatically.

## Safety Model

The restore design depends on strict single-writer behavior.

Hard rules:

- only one active gateway writer may use an authoritative OpenClaw state disk
- never attach the production authoritative disk to the recovery VM
- never attach the restored disk to the production runtime
- do not expose the recovery gateway publicly
- do not add unapproved write capabilities to the recovery runtime

Default access posture:

- no public VM IP
- IAP SSH only
- no public gateway ingress

## Operator Approval Boundaries

Separate explicit approvals are expected for:

- selecting the snapshot recovery point
- creating the restored disk
- creating the temporary recovery VM
- granting temporary IAM
- starting the isolated recovery runtime
- opening any optional external validation path
- cleanup and IAM revocation

## Boundaries And Limitations

This pattern is not a full automated disaster-recovery pipeline.

Not included in this first import:

- formal RTO commitment
- formal RPO commitment
- cross-region restore
- production failover or cutover
- unattended recovery automation

## Cleanup Expectations

After a recovery drill:

1. Stop the recovery runtime.
2. Keep or unmount the restored disk according to the approved review outcome.
3. Revoke temporary IAM granted to the recovery service account.
4. Delete the temporary recovery VM when it is no longer needed.
5. Delete the restored disk only after explicit approval.

Never delete or detach the production authoritative disk as part of isolated
restore drill cleanup.
