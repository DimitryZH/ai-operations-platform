# SRE Control-Plane GCP Deployment Foundation

This directory is the minimum deployable foundation for the accepted ADR 0002
target. It defines a private Cloud Run service and migration job, private-IP
Cloud SQL PostgreSQL, a private evidence bucket, Secret Manager containers,
an IAM-authenticated Cloud Scheduler tick, dedicated service accounts, and
centralized logging and alert-policy configuration.

The bootstrap phase has been applied for `ai-operations-platform-507220` in
`us-central1`; see
`docs/deployments/gcp-sre-control-plane-bootstrap-2026-09-01.md`. The private
runtime phase has also been applied with fake adapters only; see
`docs/deployments/gcp-sre-control-plane-runtime-2026-09-01.md`. The runtime
deployment deliberately does **not** select a real executor, enable HolmesGPT,
enable GitHub publication, activate Scheduler, access a cluster, or mutate SRE
Platform. The application runs with its fake executor and fake publisher
defaults.

## Security Boundaries

- Cloud Run is `INGRESS_TRAFFIC_INTERNAL_ONLY`; Terraform grants `roles/run.invoker`
  only to the dedicated Scheduler service account. It does not grant
  `allUsers` or `allAuthenticatedUsers`.
- Cloud SQL has no public IPv4 address and uses private service access.
- Evidence bucket access is uniform, public-access prevention is enforced,
  versioning is enabled, and Terraform cannot destroy it.
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
