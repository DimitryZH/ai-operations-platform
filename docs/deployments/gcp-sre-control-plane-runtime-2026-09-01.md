# GCP SRE Control-Plane Runtime Deployment Evidence - 2026-09-01

This document records sanitized evidence for the private runtime deployment
from Issue #49. It intentionally omits account emails, service-account emails,
principal IDs, billing account IDs, credentials, secret values, Terraform state,
raw Terraform plan files, and raw logs.

## Scope

- GitHub issue: #49
- Repository branch: `codex/issue-49-gcp-runtime-deploy`
- Target project: `ai-operations-platform-507220`
- Target region: `us-central1`
- Deployment phase: `runtime`
- Runtime mode: fake executor and fake publisher only
- Cloud Run boundary: private internal ingress with authenticated invocation
- Scheduler boundary: created paused and not activated
- Integration boundary: no SRE Platform repository mutation and no cluster
  access

## Preconditions Verified

- PR #48 was merged and Issue #47 was closed before runtime work started.
- The accepted bootstrap foundation existed in the target project and region.
- The Terraform backend used the protected GCS state bucket from Issue #47.
- Bootstrap resources were present: private VPC/subnet, private-IP Cloud SQL,
  Artifact Registry repository, evidence/logging buckets, service accounts,
  IAM bindings, alert policy, and empty Secret Manager containers.
- Runtime resources were absent before the reviewed runtime apply: no Cloud Run
  service, no Cloud Run jobs, and no Cloud Scheduler jobs in the runtime scope.
- The database URL secret had zero versions before the approved credential
  delivery step.
- The reviewed bootstrap plan showed no drift before runtime work began.

## Approval Gates

The operator separately approved each cloud write gate before it occurred:

- container image push to Artifact Registry
- out-of-band database credential and one database URL secret version
- applying the exact saved runtime Terraform plan
- executing the controlled migration job once
- running the temporary same-project internal readiness verification job

No other Terraform apply was run after the exact saved runtime plan. The later
Terraform code change only stabilized provider/API default normalization and
was verified with a no-change plan.

## Image Evidence

- Source commit: `c78589123b9f276357a2bec9317db7b91d31c9a9`
- Local image smoke test: `/healthz` returned healthy before push.
- Runtime image: immutable Artifact Registry digest
  `sha256:3639f0c5d095e7a3bf0a8f87229f2a88f3bfc2c818fb5d10f4499e920bde401e`
- Container boundary: Python 3.13 slim base, non-root `controlplane` user,
  port 8080, FastAPI served by Uvicorn.
- Mutable tags were not used in Terraform runtime configuration.

## Secret And Database Evidence

- Terraform created only the Secret Manager container during bootstrap.
- The database credential was generated and delivered out of band after
  operator approval.
- Database URL secret version recorded in runtime configuration: `1`
- Secret values were not printed, read back, committed, or stored in Terraform.
- Runtime database user existed after the approved delivery step.
- Limitation: the first credential uses a Cloud SQL built-in PostgreSQL user.
  Google documents that Cloud SQL-created PostgreSQL users receive the
  `cloudsqlsuperuser` role, which is broader than the final least-privilege
  application database role desired for later hardening.

Reference used for this limitation:
[Cloud SQL PostgreSQL user management](https://docs.cloud.google.com/sql/docs/postgres/create-manage-users?hl=en).

## Runtime Plan And Apply

- Saved runtime plan SHA-256:
  `7d7ca1f2b590316d07188716e49108e5aab6dc900ac7e8a0cfb56f5a02f30bb9`
- Plan summary: 4 to add, 0 to change, 0 to destroy
- Planned resources:
  - private Cloud Run service
  - controlled Cloud Run migration job
  - service-level authenticated invoker binding for the Scheduler identity
  - paused Cloud Scheduler HTTP job
- Plan policy checks:
  - Cloud Run internal ingress only
  - no public invoker
  - immutable image digest
  - explicit numeric database secret version
  - migration image matched service image
  - migration max retries set to zero
  - Scheduler paused
  - Scheduler used OIDC
  - fake executor and fake publisher defaults remained enforced
- Apply result for the exact saved plan: 4 added, 0 changed, 0 destroyed

## Post-Apply Verification

Read-only checks after apply confirmed:

- Cloud Run service Ready condition: true
- Cloud Run ingress: internal
- Cloud Run image: immutable digest from this evidence
- Cloud Run database secret reference: explicit version `1`
- Cloud Run public invokers: zero
- Cloud Run invoker binding: one service-account identity type
- Migration job existed and used the same immutable image as the service
- Migration job database secret reference: explicit version `1`
- Migration job max retries: zero
- Scheduler job state: `PAUSED`
- Scheduler HTTP method: `POST`
- Scheduler OIDC configured
- Database URL secret versions: one enabled version
- Temporary readiness verification job: absent after cleanup
- Secret values read during verification: false

After adding provider/API default normalization ignores for Cloud Run top-level
scaling defaults and Scheduler zero-valued retry defaults, the final Terraform
plan returned no changes: infrastructure matches configuration.

## Migration Evidence

The controlled migration job was executed once after explicit approval.

- Migration execution count after run: 1
- Latest migration completion: succeeded
- Sanitized Alembic log markers observed:
  - `Context impl PostgresqlImpl`
  - `Will assume transactional DDL`
  - `Running upgrade`
  - migration `0007`
- Raw logs were not committed.
- Secret values were not read.

## Readiness Evidence

The authenticated internal readiness check used a temporary same-project Cloud
Run job under an identity type already allowed to invoke the private service.
The job used direct VPC egress, requested an OIDC identity token from the
metadata server with the private Cloud Run service URL as audience, and called
only:

- `GET /healthz`
- `GET /readyz`

The final check used an exit-code contract: the temporary job exited
successfully only after all of the following were true:

- OIDC token acquisition succeeded.
- `/healthz` returned HTTP 200 and JSON `status=ok`.
- `/readyz` returned HTTP 200 and JSON `status=ok`, `database=ok`, and
  `migrations=ok`.

The temporary job completed successfully and was deleted. Scheduler remained
paused.

## Cost Estimate

Estimated current monthly cost for the created bootstrap plus private runtime
resources in `us-central1`: approximately **USD 55-90/month** under low idle
usage.

Main cost drivers and assumptions:

- Cloud SQL PostgreSQL `db-custom-1-3840`, zonal, 20 GB storage, backups and
  point-in-time recovery enabled: the dominant steady-state cost.
- Cloud SQL charges continue while the instance is running, even when the
  application receives no traffic.
- Cloud Run service has minimum instances set to zero and default request-based
  billing, so idle service cost should be near zero; readiness and migration
  checks add small request, CPU, and memory charges.
- Cloud Run migration/readiness jobs add only one-off execution charges.
- Cloud Scheduler is paused, so no recurring invocation cost is expected.
- Artifact Registry stores one small image and is expected to remain within or
  near the low storage tier for this project.
- Cloud Storage state/evidence/log buckets, Secret Manager metadata, Cloud
  Logging, and Cloud Monitoring costs should be low at current volume.

Pricing references reviewed:

- [Cloud SQL pricing](https://cloud.google.com/sql/pricing)
- [Cloud Run pricing](https://cloud.google.com/run/pricing)
- [Artifact Registry pricing](https://cloud.google.com/artifact-registry/pricing)
- [Cloud Storage pricing](https://cloud.google.com/storage/pricing)

## Rollback Notes

- Scheduler is paused; no runtime tick needs disabling.
- Roll back the Cloud Run service by applying a separately reviewed Terraform
  plan that points `container_image` to the preceding approved immutable digest.
- Do not run Alembic downgrade automatically. Database rollback requires a
  separate data-impact review, backup verification, and explicit approval.
- Cloud SQL, evidence bucket, log bucket, secret containers, and Terraform
  state bucket retain deletion protection or recovery controls from bootstrap.

## Explicit Non-Events

- No Scheduler activation occurred.
- No Cloud Run public ingress or public invoker was configured.
- No live executor was configured or invoked.
- No live GitHub publisher was configured or invoked by the application.
- No HolmesGPT or model call was made.
- No Kubernetes cluster was accessed.
- No SRE Platform files were changed.
- No credentials, secret values, state files, or raw plan files were committed.
