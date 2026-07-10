# Stateful Agent Runtime Operations Runbook

**Status:** Initial imported runtime foundation.
**Important:** Keep the runtime private, single-writer, and token-protected.
Do not print secret values in terminals, logs, tickets, commits, or chat.

## Operating Invariant

Exactly one gateway writer may use the authoritative OpenClaw state disk.

Before repair, restore, upgrade, rollback, or migration:

```text
prove the current writer is stopped
identify the authoritative disk
start only one replacement writer
```

## Runtime Shape

- private Compute Engine VM in a zonal stateful managed instance group
- managed instance group target size: `1`
- gateway container: `openclaw-gateway`
- systemd service: `openclaw.service`
- state mount: `/var/lib/openclaw`
- access model: IAP SSH and IAP TCP tunnel only
- public VM IP: none

The managed instance name can change after a recreate. Always query the
managed instance group before running instance-specific commands.

## Discover The Managed Instance

```bash
gcloud compute instance-groups managed list-instances MIG_NAME \
  --project=PROJECT_ID \
  --zone=ZONE
```

Record the current instance name before using later commands.

## Controlled Stop And Start

Use the stateful managed instance group control plane. Do not directly stop or
start the VM outside the group lifecycle.

Stop the current managed instance:

```bash
gcloud compute instance-groups managed stop-instances MIG_NAME \
  --instances=INSTANCE_NAME \
  --project=PROJECT_ID \
  --zone=ZONE
```

Start the same managed instance:

```bash
gcloud compute instance-groups managed start-instances MIG_NAME \
  --instances=INSTANCE_NAME \
  --project=PROJECT_ID \
  --zone=ZONE
```

Expected control-plane signals after start:

- exactly one managed instance is `RUNNING`
- managed instance group target size returns to `1`
- health check converges before operator traffic is trusted

## IAP Access

Port model:

- VM-local OpenClaw runtime port: `8080`
- operator laptop tunnel port: `18080`

Start a local tunnel:

```bash
gcloud compute start-iap-tunnel INSTANCE_NAME 8080 \
  --project=PROJECT_ID \
  --zone=ZONE \
  --local-host-port=127.0.0.1:18080
```

Then use:

```text
http://127.0.0.1:18080/
```

SSH through IAP:

```bash
gcloud compute ssh INSTANCE_NAME \
  --project=PROJECT_ID \
  --zone=ZONE \
  --tunnel-through-iap
```

## Service And Container Checks

Run on the Stateful VM over SSH:

```bash
sudo systemctl is-active openclaw.service
sudo systemctl is-enabled openclaw.service
sudo docker ps --filter name=openclaw-gateway
sudo docker inspect openclaw-gateway --format '{{.Config.Image}}'
```

Expected baseline:

- `openclaw.service` is active and enabled
- `openclaw-gateway` is running
- the image digest matches the approved immutable digest

## Health And Readiness Checks

Run on the Stateful VM over SSH:

```bash
curl -sS -i http://127.0.0.1:8080/health
curl -sS -i http://127.0.0.1:8080/readyz
```

Expected:

- `/health` returns a live status
- `/readyz` returns a ready status

## Gateway Token Handling

Use the approved operator secret retrieval procedure for browser access.
Never include the token value in repository files, tickets, logs, or records.

For VM-local checks:

```bash
TOKEN="$(sudo cat /run/openclaw/secrets/OPENCLAW_GATEWAY_TOKEN | tr -d '\r\n')"
```

Do not echo the token.

## State Disk Checks

Run on the Stateful VM over SSH:

```bash
findmnt /var/lib/openclaw
lsblk -f
sudo stat -c '%U:%G %a %n' \
  /var/lib/openclaw \
  /var/lib/openclaw/state \
  /var/lib/openclaw/workspace
df -h /var/lib/openclaw
```

Expected:

- ext4 filesystem
- preserved persistent disk device
- state and workspace owned by UID/GID `10001:10001`
- restrictive permissions
- adequate free space

## Manual Pre-Upgrade Snapshot

A manual pre-upgrade snapshot must be application-consistent:

1. Announce downtime.
2. Stop `openclaw.service`.
3. Confirm no OpenClaw container is running.
4. Flush filesystem buffers with `sync`.
5. Create a labeled manual snapshot through an approved identity.
6. Confirm snapshot creation was accepted.
7. Restart the gateway and validate health.

## Upgrade Outline

1. Build and validate a new image.
2. Record the immutable digest.
3. Test the image against a restored state copy.
4. Create an application-consistent pre-upgrade snapshot.
5. Confirm the managed instance group update uses recreate semantics with no
   overlapping writers.
6. Apply only after explicit approval.
7. Validate the single writer, disk mount, image digest, health, readiness,
   state, workspace, and approved capability posture.

## Rollback Outline

Image-only rollback:

1. Stop or fence the failed gateway.
2. Restore the previous instance template digest.
3. Start one gateway.
4. Run the full validation checklist.

State rollback:

1. Stop or fence the failed gateway.
2. Preserve the failed disk for investigation.
3. Restore the approved snapshot to a new disk.
4. Make the restored disk authoritative through a reviewed Terraform change.
5. Start the previous image with one writer.
6. Validate all persistent behavior.

State rollback loses writes after the selected snapshot. Record that decision
explicitly.

## Emergency Security Response

If secret or runtime compromise is suspected:

1. Stop the gateway.
2. Preserve diagnostics without exposing secret contents.
3. Revoke or rotate gateway, model, and GitHub secrets as appropriate.
4. Review IAP, Secret Manager, IAM, and Compute audit logs.
5. Restore from a trusted recovery point only after incident-owner approval.
