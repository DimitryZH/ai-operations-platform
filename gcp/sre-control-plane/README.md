# SRE Control-Plane GCP Deployment Foundation

This directory is the minimum deployable foundation for the accepted ADR 0002
target. It defines a private Cloud Run service and migration job, private-IP
Cloud SQL PostgreSQL, a private evidence bucket, Secret Manager containers,
an IAM-authenticated Cloud Scheduler tick, dedicated service accounts, and
centralized logging and alert-policy configuration.

It deliberately does **not** apply infrastructure, create secret versions,
select a real executor, enable HolmesGPT, or enable GitHub publication. The
application runs with its fake executor and fake publisher defaults.

## Security Boundaries

- Cloud Run is `INGRESS_TRAFFIC_INTERNAL_ONLY`; Terraform grants `roles/run.invoker`
  only to the dedicated Scheduler service account. It does not grant
  `allUsers` or `allAuthenticatedUsers`.
- Cloud SQL has no public IPv4 address and uses private service access.
- Evidence bucket access is uniform, public-access prevention is enforced,
  versioning is enabled, and Terraform cannot destroy it.
- Terraform creates only Secret Manager containers. Secret values and versions
  are supplied later through an approved out-of-band procedure and are never
  stored in Terraform configuration or state.
- Runtime IAM is limited to Cloud SQL client access, evidence object access,
  the database URL secret, structured logging, and custom metrics. The
  scheduler identity receives only Cloud Run invocation.
- Scheduler invokes the short `/internal/dispatch/tick` orchestration endpoint
  with OIDC. It is not a worker and must not run an investigation synchronously.

## Prerequisites For A Later Reviewed Plan

Do not run these commands until the project, billing, enabled APIs, VPC range,
Artifact Registry image digest, secret-delivery path, and operator invoker
identities have been reviewed. `terraform apply` is intentionally outside this
foundation.

1. Install Terraform `>= 1.5`, Docker, and authenticated Google Cloud CLI in a
   separately approved operator environment.
2. Copy `terraform/terraform.tfvars.example` to an ignored
   `terraform/terraform.tfvars`; replace only placeholder identifiers and the
   immutable image digest. Do not add secret values.
3. Run local static validation:

   ```powershell
   .\gcp\sre-control-plane\scripts\validate-foundation.ps1
   ```

4. In the reviewed operator environment, initialize the selected backend and
   run `terraform plan -out=tfplan`. Review all resource changes, IAM bindings,
   deletion-protection values, and the absence of public invokers before any
   separately authorized apply.

## Controlled Migration And Rollback

The `sre-control-plane-<environment>-migrate` Cloud Run Job runs
`alembic upgrade head` using the same immutable image as the service. It has
zero automatic retries. A later deployment runbook must execute it once,
inspect its logs and `/readyz`, then release the Cloud Run service revision.

Rollback means returning Cloud Run to the preceding reviewed image digest. Do
not run Alembic downgrade automatically: database downgrade requires a separate
data-impact review, backup verification, and explicit approval. Cloud SQL,
evidence bucket, and secret containers retain deletion protection.

## Smoke Test Boundary

After an approved deployment, an operator with a specifically granted
`roles/run.invoker` binding can call `/healthz`, `/readyz`, and a bounded
authenticated tick. No live executor or GitHub publication configuration may
be supplied during this foundation smoke test. It must not access an SRE
Platform cluster.
