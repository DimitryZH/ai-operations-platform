# SRE Control-Plane GCP Deployment Foundation

This directory is the minimum deployable foundation for the accepted ADR 0002
target. It defines a private Cloud Run service and migration job, private-IP
Cloud SQL PostgreSQL, a private evidence bucket, Secret Manager containers,
an IAM-authenticated Cloud Scheduler tick, dedicated service accounts, and
centralized logging and alert-policy configuration.

The bootstrap phase has been applied for `ai-operations-platform-507220` in
`us-central1`; see
`docs/deployments/gcp-sre-control-plane-bootstrap-2026-09-01.md`. The private
runtime phase has also been applied with fake executor defaults; see
`docs/deployments/gcp-sre-control-plane-runtime-2026-09-01.md`. The runtime
deployment deliberately does **not** enable HolmesGPT, activate Scheduler,
access a cluster, or mutate SRE Platform. The application keeps the fake
executor default. GitHub publication and the SRE replay executor are explicit
opt-in modes with bounded allowlists.

## Security Boundaries

- Cloud Run is `INGRESS_TRAFFIC_INTERNAL_ONLY`; Terraform grants `roles/run.invoker`
  only to the dedicated Scheduler service account. It does not grant
  `allUsers` or `allAuthenticatedUsers`.
- Cloud SQL has no public IPv4 address and uses private service access.
- Evidence bucket access is uniform, public-access prevention is enforced,
  versioning is enabled, and Terraform cannot destroy it.
- Reviewed GCP runtime stores sanitized evidence through the existing evidence
  bucket only. Artifact identity is deterministic SHA-256, Cloud Storage object
  creation uses generation preconditions, and the application verifies remote
  object size, exact `application/json` content type, exact metadata contract,
  bounded readback size, and SHA-256 integrity before recording the object
  reference in PostgreSQL.
- Cloud SQL has Terraform deletion protection and API-level deletion
  protection enabled.
- Terraform creates only Secret Manager containers. Secret values and versions
  are supplied later through an approved out-of-band procedure and are never
  stored in Terraform configuration or state.
- Runtime IAM is limited to Cloud SQL client access, evidence object access,
  the database URL secret, structured logging, and custom metrics. The
  scheduler identity receives only Cloud Run invocation.
- Scheduler invokes the short `/internal/dispatch/tick` orchestration endpoint
  with OIDC. It is not a worker and must not run an investigation synchronously.

## Staged Bootstrap For A Later Reviewed Apply

Do not run these commands until the project, billing, enabled APIs, VPC range,
Artifact Registry image digest, secret-delivery path, and operator invoker
identities have been reviewed. `terraform apply` is intentionally outside this
foundation.

Target project for the first reviewed bootstrap is
`ai-operations-platform-507220` in `us-central1`. Use explicit `--project` and
Terraform `project_id` values for this project; do not rely on a workstation's
ambient `gcloud` project.

1. Install Terraform `>= 1.5`, Docker, and authenticated Google Cloud CLI in a
   separately approved operator environment. Run local static validation:

   ```powershell
   .\gcp\sre-control-plane\scripts\validate-foundation.ps1
   ```

2. **Remote-state bucket phase:** after read-only preflight and explicit
   operator approval for the first cloud write, create the dedicated Terraform
   state bucket before Terraform initialization:

   ```powershell
   $PROJECT_ID = "ai-operations-platform-507220"
   $REGION = "us-central1"
   $STATE_BUCKET = "ai-operations-platform-507220-sre-control-plane-tfstate"

   gcloud storage buckets create "gs://$STATE_BUCKET" `
     --project="$PROJECT_ID" `
     --location="$REGION" `
     --uniform-bucket-level-access `
     --public-access-prevention

   gcloud storage buckets update "gs://$STATE_BUCKET" `
     --versioning `
     --soft-delete-duration=30d
   ```

   Do not set a bucket retention policy on this backend bucket. Terraform's GCS
   backend uses short-lived lock objects; bucket-level retention can prevent
   lock cleanup and block future plans. Versioning plus a 30-day soft-delete
   recovery window protects state object generations without committing local
   state or raw plan files.

3. **Bootstrap phase:** copy `terraform/terraform.tfvars.example` to ignored
   `terraform/terraform.tfvars`. This phase requires no image digest or secret
   version. Its reviewed plan and separately approved apply create only APIs,
   network, Artifact Registry, Cloud SQL, service accounts, evidence/logging
   resources, and Secret Manager containers.
4. **Out-of-band secret phase:** after bootstrap, an approved secret operator
   creates the database credential and writes a concrete database URL as one
   new version of the Terraform-created database secret. Terraform never
   receives that value. Record only its numeric version, such as `1`.
5. **Image phase:** build and push the container to the Terraform-created
   Artifact Registry repository, then record its immutable SHA-256 digest.
6. **Runtime phase:** copy `terraform/terraform.runtime.tfvars.example` to an
   ignored local file and provide the reviewed image digest and explicit numeric
   `database_secret_version`. The runtime plan creates Cloud Run, the migration
   job, its scheduler IAM binding, and a **paused** Scheduler job. Review all
   resource changes, IAM bindings, deletion-protection values, and the absence
   of public invokers before any separately authorized apply.
7. **Evidence adapter phase:** after the bounded GCS evidence adapter is
   reviewed, update Cloud Run to set `SRE_CONTROL_PLANE_EVIDENCE_STORE=gcs`,
   `SRE_CONTROL_PLANE_GCS_PROJECT_ID`, and
   `SRE_CONTROL_PLANE_EVIDENCE_BUCKET` for the existing evidence bucket. The
   runtime service account receives bucket-scoped `roles/storage.objectCreator`
   and `roles/storage.objectViewer`. This phase must not create another bucket,
   widen project IAM, activate Scheduler, select live adapters, or access SRE
   Platform.
8. **GitHub publisher phase:** after the bounded GitHub publisher runtime
   binding is reviewed, set `github_publisher_mode = "github"` only with an
   exact matching repository and Issue allowlist plus a numeric existing Secret
   Manager credential version. Terraform references the existing
   `github-token` secret container and grants the runtime service account
   `roles/secretmanager.secretAccessor` on that secret only. This phase must
   keep the fake executor, private Cloud Run ingress, authenticated invocation,
   GCS evidence adapter, and paused Scheduler boundaries.
9. **SRE replay executor phase:** after the bounded SRE replay executor is
   reviewed, `executor_mode = "sre_replay"` may be used only as an explicit
   fixture-backed read-only validation mode. Terraform injects the exact
   approved provider declaration JSON for Kubernetes, Prometheus, GitOps, and
   optional recovery observation. This mode must not contact a live cluster,
   Prometheus endpoint, Argo CD API, HolmesGPT, model, or SRE Platform runtime,
   and it must not change the paused Scheduler or publication allowlist
   boundaries.

## Controlled Migration And Rollback

The `sre-control-plane-<environment>-migrate` Cloud Run Job runs
`alembic upgrade head` using the same immutable image as the service. It has
zero automatic retries. A later deployment runbook must execute it once,
inspect its logs, then perform the authenticated internal readiness check below.
The Scheduler remains paused. It must not be enabled by the runtime apply.

After both migration and readiness succeed, activation remains a separate
reviewed Terraform change: set `scheduler_enabled = true` and
`scheduler_activation_confirmed = true`. The confirmation represents recorded
human evidence that the migration job succeeded and readiness was verified; it
does not bypass either gate.

Rollback means returning Cloud Run to the preceding reviewed image digest. Do
not run Alembic downgrade automatically: database downgrade requires a separate
data-impact review, backup verification, and explicit approval. Cloud SQL,
evidence bucket, and secret containers retain deletion protection.

## Smoke Test Boundary

`INGRESS_TRAFFIC_INTERNAL_ONLY` rejects requests that originate from an
external operator workstation even when that operator has `roles/run.invoker`.
The authenticated internal verification path is a same-project Cloud Scheduler
one-off request (or a separately reviewed same-project internal Cloud Run
verification job) using a dedicated service account with `roles/run.invoker`.
Cloud Scheduler is an internal Cloud Run source and presents an OIDC token.

Before activation, use that identity to call `/healthz` and `/readyz` through
the internal service URL, record the successful migration job and readiness
evidence, then make the separate Scheduler activation change above. No public
ingress, live executor, GitHub publication configuration, or SRE Platform
cluster access is permitted during this smoke test.

## Evidence Smoke Boundary

The evidence adapter smoke test is a separate approval gate after the reviewed
Cloud Run update is applied. It must write exactly one marked fake-investigation
evidence package through the private runtime, producing one deterministic object
under `evidence/sha256/` in the existing evidence bucket. The recorded evidence
must include only the object scheme, prefix, SHA-256 length, sanitization status,
retention policy, and idempotency result.

The smoke test must not activate Scheduler, configure a live executor, configure
GitHub publication, call a model, access a Kubernetes cluster, mutate SRE
Platform, print secret values, or publish raw object contents.

## GitHub Publication Smoke Boundary

Live GitHub publication is a separate approval gate. After the reviewed runtime
plan has been applied, the live smoke may write exactly one marked comment to
the allowlisted Issue and repeat the same idempotency key to verify reuse. The
recorded evidence must include only the target identity, marker/idempotency
status, receipt validation, retry classification, and PostgreSQL outcome shape.

The smoke test must not activate Scheduler, run a migration job, configure a
real executor, call HolmesGPT or another model, access a Kubernetes cluster,
mutate SRE Platform, print secret values, or publish raw evidence contents.

## SRE Replay Executor Smoke Boundary

The SRE replay executor smoke test is a local or separately reviewed private
runtime validation of the adapter boundary only. It may submit the approved
Issue #55 replay request, run one dispatcher tick, and publish the resulting
sanitized evidence through the configured evidence and publisher paths only
when those paths are separately enabled and allowlisted.

The recorded evidence must state that the result came from sanitized fixtures,
not live staging or production validation. The smoke must not activate
Scheduler, create or modify secrets, push a new image, apply Terraform, write a
GitHub comment, call HolmesGPT or a model, access Kubernetes or Prometheus, or
mutate SRE Platform without the relevant separate approval gate.
