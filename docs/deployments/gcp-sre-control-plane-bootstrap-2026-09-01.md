# GCP SRE Control-Plane Bootstrap Evidence - 2026-09-01

## Scope

This evidence records the reviewed bootstrap deployment for Issue #47.

- Repository: `DimitryZH/ai-operations-platform`
- Branch: `codex/issue-47-gcp-bootstrap-deploy`
- Target project: `ai-operations-platform-507220`
- Target region: `us-central1`
- Deployment phase: `bootstrap`
- Terraform backend: `gs://ai-operations-platform-507220-sre-control-plane-tfstate`
- SRE Platform context: read-only repository inspection only, no cluster access

No credentials, access tokens, secret values, Terraform state contents, saved
plan contents, certificate material, billing account identifiers, raw logs,
account emails, principal IDs, or private operator notes are included in this
evidence.

## Approval Gates

The operator explicitly approved each cloud write gate:

1. Creating the protected remote Terraform state bucket.
2. Applying the first saved bootstrap plan.
3. Applying the corrected saved bootstrap plan after provider validation found
   service-account ID, Cloud SQL tier, logging sink IAM, and bucket-name issues.
4. Applying the final saved plan for remaining Secret Manager containers.
5. Applying the Cloud SQL API-level deletion-protection hardening plan.

## Preflight Summary

- Operator identity verified.
- Project lifecycle: `ACTIVE`
- Billing status: enabled
- Project ancestors: project only, no folder or organization ancestor reported
- Effective project organization policies after enabling Org Policy API: none
- Selected region: `us-central1`
- `gcloud` ambient project was not trusted; commands used explicit
  `--project=ai-operations-platform-507220`.
- Application Default Credentials quota project was corrected to
  `ai-operations-platform-507220` before Terraform backend initialization.

## Remote State

The dedicated state bucket was created before Terraform initialization.

- Bucket: `ai-operations-platform-507220-sre-control-plane-tfstate`
- Location: `US-CENTRAL1`
- Uniform bucket-level access: enabled
- Public access prevention: enforced
- Versioning: enabled
- Soft delete: 30 days
- Local `terraform.tfstate`: absent

No bucket-level retention policy was configured on the Terraform backend bucket,
because Terraform's GCS backend uses lock objects and retention can block lock
cleanup.

## Terraform State IAM Review

A read-only IAM check was performed for the Terraform state bucket and
state-relevant project-level access before and after the separately approved
IAM hardening write. Account emails and principal IDs are omitted from this
evidence.

Before the approved hardening write, read-only checks confirmed:

- The default Compute Engine service account was not used by existing Compute
  Engine instances.
- No Cloud Run services or Cloud Run jobs existed in `us-central1`; therefore
  none used the default Compute Engine service account implicitly or
  explicitly.
- No Cloud Scheduler jobs existed in `us-central1`.
- No unexpected workload dependency on the default Compute Engine service
  account was found.
- The state bucket and project had no public principals.
- The state bucket had direct legacy pseudo-principal bindings for
  `projectOwner`, `projectEditor`, and `projectViewer`.
- The project had a broad default Compute Engine service account
  `roles/editor` binding.
- A human project Owner identity was preserved as the documented
  project-admin/break-glass path.
- Exact rollback commands were prepared before making changes; they are not
  published because they contain principal identifiers.

The approved hardening write then made only the scoped IAM changes authorized
for this project and state bucket:

- A temporary project-level Storage Admin grant was added for the active
  operator identity only to recover state-bucket IAM access, then removed after
  the scoped state-bucket binding was in place.
- The active operator identity received direct state-bucket `roles/storage.admin`
  access for Terraform backend and bucket IAM administration.
- The default Compute Engine service account project-level `roles/editor`
  binding was removed.
- Direct legacy state-bucket pseudo-principal bindings for `projectOwner`,
  `projectEditor`, and `projectViewer` were removed.
- No other project IAM bindings, service accounts, organization policies,
  Terraform resources, or runtime configuration were changed.

After hardening, read-only checks confirmed:

- Public principals: no `allUsers` or `allAuthenticatedUsers` bindings were
  found on the state bucket or project policy.
- State-bucket legacy pseudo-principals: absent.
- State-bucket direct IAM: one `user` principal type with
  `roles/storage.admin`; principal ID omitted.
- Project-level state-relevant IAM: one `user` principal type with
  `roles/owner`; principal ID omitted.
- Temporary project-level Storage Admin for the operator: absent.
- Default Compute Engine service account project-level Editor: absent.
- Terraform backend object list access: present.
- `terraform plan -input=false -detailed-exitcode`: no changes.

Effective Terraform state read and modification access is now held by the
operator through direct state-bucket Storage Admin and by the documented human
project Owner break-glass path. No public or legacy pseudo-principal access to
the Terraform state bucket remains.

## Monthly Cost Estimate

This is a sanitized estimate for the bootstrap resources actually created in
`us-central1`, based on public Google Cloud pricing pages checked on
2026-09-01. It does not use billing account IDs, negotiated discounts, credits,
private billing exports, or closed billing data.

- Estimated steady-state range: approximately USD 53-60/month while the Cloud
  SQL instance runs continuously.
- Main cost driver: Cloud SQL PostgreSQL Enterprise, zonal
  `db-custom-1-3840` (1 vCPU, 3.75 GiB memory). At public `us-central1`
  hourly rates, compute is approximately USD 49/month for 730 hours.
- Cloud SQL storage: 20 GiB SSD is approximately USD 3.40/month. Backup and
  point-in-time recovery usage depends on actual retained backup/WAL size; a
  small bootstrap database is estimated at roughly USD 0-2/month.
- Cloud Storage state and evidence buckets: expected to be near USD 0 at
  current small object volume, subject to account-level Free Tier eligibility,
  stored bytes, object versions, soft-deleted bytes, and operation counts.
- Artifact Registry: repository is empty after bootstrap; storage is expected
  to be USD 0 at current usage and then scales with stored artifact GiB.
- Secret Manager: only secret containers exist and no secret versions were
  created, so no active-version charge is expected for the bootstrap state.
- VPC, subnet, private service access configuration, IAM bindings, enabled APIs,
  logging sink definition, and alert policy definition do not add a material
  standalone monthly charge in this bootstrap-only state. Future runtime logs,
  metrics, image storage, Scheduler execution, Cloud Run, and secret versions
  can add costs.

Cloud SQL creates ongoing charges while the instance remains running, even
without Cloud Run or Scheduler runtime resources.

Public pricing references:

- <https://cloud.google.com/sql/pricing>
- <https://cloud.google.com/storage/pricing>
- <https://cloud.google.com/artifact-registry/pricing>
- <https://cloud.google.com/secret-manager/pricing>

## Applied Bootstrap Resources

Terraform completed with no remaining drift after the final hardening apply.

- Required APIs enabled:
  `artifactregistry.googleapis.com`, `cloudscheduler.googleapis.com`,
  `compute.googleapis.com`, `logging.googleapis.com`,
  `monitoring.googleapis.com`, `run.googleapis.com`,
  `secretmanager.googleapis.com`, `servicenetworking.googleapis.com`,
  `sqladmin.googleapis.com`
- VPC: `sre-control-plane-staging-network`
- Subnet: `sre-control-plane-staging-subnet`, `10.60.0.0/24`,
  private Google access enabled
- Private service access peering: `servicenetworking-googleapis-com`
- Artifact Registry repository: `sre-control-plane-staging`, Docker,
  empty after bootstrap
- Dedicated runtime service account: created; principal ID omitted.
- Dedicated Scheduler service account: created; principal ID omitted.
- Evidence bucket: `ai-operations-platform-507220-sre-cp-staging-evidence`
- Logging bucket: `sre-control-plane-staging-logs`
- Logging sink: `sre-control-plane-staging-logs`
- Monitoring alert policy: Cloud Run 5xx response policy, no notification
  channel configured
- Cloud SQL instance: `sre-control-plane-staging-postgres`
- Cloud SQL database: `sre_control_plane`
- Secret Manager containers:
  `sre-control-plane-staging-database-url`,
  `sre-control-plane-staging-github-token`,
  `sre-control-plane-staging-executor-config`

## Verification Summary

Terraform:

- `terraform plan -input=false -detailed-exitcode`: no changes
- `terraform output -json`: only non-sensitive IDs were returned
- Local state file: absent

Cloud SQL:

- State: `RUNNABLE`
- Database version: PostgreSQL 16
- Edition: Enterprise
- Tier: `db-custom-1-3840`
- Disk: 20 GB SSD, autoresize enabled
- Availability: zonal
- Backups: enabled
- Point-in-time recovery: enabled
- IPv4: disabled
- IP addresses: private only
- API-level deletion protection: enabled
- Terraform deletion protection: enabled

Storage:

- Terraform state bucket: uniform access enabled, public access prevention
  enforced, versioning enabled, 30-day soft delete.
- Evidence bucket: uniform access enabled, public access prevention enforced,
  versioning enabled, 30-day retention policy, 7-day soft delete.

Secrets:

- Three Secret Manager containers exist.
- Version lists for all three containers are empty.
- No secret values were created, read, printed, or committed.
- The dedicated runtime service account has
  `roles/secretmanager.secretAccessor` only on the database URL secret
  container.

Negative checks:

- Cloud Run services in `us-central1`: none.
- Cloud Run jobs in `us-central1`: none.
- Cloud Scheduler jobs in `us-central1`: none.
- No migration job was created.
- No runtime container image was configured.
- No database user was created by Terraform.
- No SRE Platform files were changed.
- No Kubernetes cluster was contacted.

## Validation

- `terraform fmt -check -recursive`: passed
- `terraform validate`: passed
- `.\gcp\sre-control-plane\scripts\validate-foundation.ps1`: passed
- `python -m pytest tests\deployment\test_gcp_deployment_foundation.py -q`:
  `9 passed`
- `python -m pytest -q`: `152 passed, 15 skipped`

## Follow-Up Boundary

The bootstrap phase is complete. Runtime deployment remains out of scope until
a later reviewed issue supplies and approves:

- immutable container image digest;
- out-of-band database credentials and database URL secret version;
- migration job execution plan;
- authenticated internal readiness verification;
- paused Scheduler runtime plan;
- separate activation approval.
