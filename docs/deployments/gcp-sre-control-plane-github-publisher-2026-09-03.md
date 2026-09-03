# GCP SRE Control-Plane GitHub Publisher Runtime Evidence - 2026-09-03

This document records sanitized evidence for Issue #53. It intentionally omits
account emails, service-account emails, principal IDs, billing account IDs,
credentials, token values, database URLs, Terraform state, raw Terraform plan
files, raw logs, endpoint data, raw GitHub comment bodies, and private operator
notes.

## Scope

- GitHub issue: #53
- Repository branch: `codex/issue-53-github-publisher-runtime`
- Target project: `ai-operations-platform-507220`
- Target region: `us-central1`
- Deployment phase: `runtime`
- Runtime executor mode: fake executor only
- Runtime evidence store: existing GCS evidence bucket
- Publisher mode: fake by default; GitHub is explicit opt-in only
- Cloud Run boundary: private internal ingress with authenticated invocation
- Scheduler boundary: remains `PAUSED`
- Integration boundary: no SRE Platform repository mutation and no cluster
  access

## Read-Only Preflight

Read-only checks before any Issue #53 cloud write confirmed:

- `main` was updated before the branch was created.
- The accepted bootstrap foundation and private runtime from prior issues exist
  in the target project and region.
- Cloud Run was Ready, internal-only, authenticated, and using an immutable
  image digest.
- Cloud Run retained the GCS evidence-store environment selection for the
  reviewed project and existing evidence bucket.
- Cloud Run did not yet expose GitHub publisher runtime environment variable
  names before this change was applied.
- Cloud Run service-level scaling remained automatic with zero minimum and zero
  manual instances.
- Cloud Run template-level scaling remained zero minimum and one maximum
  instance.
- Cloud Run IAM had no public invokers and one Scheduler service-account
  identity type with invocation authority.
- Cloud Scheduler existed and remained `PAUSED`.
- The GitHub token Secret Manager container existed with Terraform labels and
  automatic replication. No secret version value was read.
- The GitHub token secret had no listed versions during preflight, so a
  credential version still needs to be created through an approved out-of-band
  operator procedure before a GitHub-mode runtime apply.
- The GitHub token secret had no direct secret-level IAM binding before this
  issue's runtime opt-in.
- The existing evidence bucket had public-access prevention, versioning,
  retention, and uniform bucket-level access controls as previously reviewed.
- Evidence bucket public principals: zero `allUsers` or
  `allAuthenticatedUsers`.
- Evidence bucket IAM included the expected runtime service-account identity
  type plus existing project legacy principal types documented in prior
  evidence. No bucket IAM was changed during preflight.
- SRE Platform read-only context was checked; no files were modified there.

## Runtime Contract

- PostgreSQL remains the source of truth for task, attempt, result, evidence
  reference, publication intent, publication outcome, and review state.
- GitHub publication is behind the product-neutral publisher interface.
- Local development and tests keep `FakePublisher` as the default.
- Runtime GitHub publication requires explicit `github` publisher mode.
- Runtime GitHub publication requires an exact target repository and Issue
  number plus an exact matching allowlist repository and Issue number.
- Runtime credential delivery uses a Secret Manager secret reference and an
  explicit numeric existing version. Terraform does not create or store the
  token value.
- GitHub calls happen after durable publication claim and evidence persistence,
  outside database transactions and locks.
- Publication Markdown is deterministic, bounded, sanitized, and marked by a
  canonical idempotency marker.
- Reusing the same idempotency key and semantic payload reuses the existing
  comment; conflicting semantics fail closed.
- PostgreSQL records append-only publication outcomes and only validated
  publication references.
- Missing, malformed, unsafe, partial, or non-allowlisted runtime configuration
  fails closed during startup.

## Planned Runtime Change

The reviewed Terraform update is expected to:

- deploy a new immutable Cloud Run image that includes the stricter GitHub
  runtime configuration contract;
- set `SRE_CONTROL_PLANE_PUBLISHER=github` only when explicitly selected by
  runtime variables;
- set the allowlisted repository and Issue environment values only in GitHub
  mode;
- reference the existing GitHub credential secret container and exact numeric
  version from Cloud Run;
- grant the runtime service account `roles/secretmanager.secretAccessor` only
  on the GitHub credential secret when GitHub mode is selected;
- keep fake executor mode;
- keep the GCS evidence adapter and existing evidence bucket;
- keep Cloud Run private, internal, authenticated, automatic, zero-minimum, and
  bounded to one template instance;
- keep Scheduler paused;
- avoid creating secret versions, Scheduler activation, migration execution,
  live executor configuration, model calls, cluster access, or SRE Platform
  mutation.

## Approval Gates

Separate operator approval is required immediately before each cloud write:

- push the immutable runtime image to Artifact Registry;
- create or otherwise supply an out-of-band GitHub credential secret version,
  performed by an operator without exposing the token value to Terraform,
  documentation, logs, or chat;
- apply the exact saved Terraform plan;
- write one marked live GitHub smoke comment to the allowlisted Issue.

If an exact saved Terraform plan contains any unexpected resource, IAM,
Scheduler, secret-version, image, executor, evidence, ingress, scaling,
database, or runtime-boundary change, the apply must stop for review.

## Pre-Deployment Validation

- Targeted publisher, configuration, PostgreSQL publication, and deployment
  regression tests: 80 passed, 12 skipped. Skipped tests were opt-in
  PostgreSQL integration tests without local external configuration in this
  shell.
- Terraform static validation succeeded. The sandboxed run emitted a remote
  backend network error before reporting valid configuration; this was a local
  sandbox network limitation and not a Terraform validation failure.
- Terraform provider schema was inspected read-only for local provider support.

## Cost Estimate

Estimated incremental monthly cost for this publisher runtime binding in
`us-central1` is approximately **USD 0-5/month** at current low volume, excluding
the existing private runtime baseline.

Main incremental cost drivers and assumptions:

- one additional Artifact Registry image digest;
- a new Cloud Run revision with minimum instances kept at zero, so idle service
  cost should remain near zero;
- Secret Manager access operations for the existing GitHub credential version;
- one approved live GitHub smoke publication and idempotency-reuse check.

The existing private runtime baseline still carries the larger steady-state
cost, dominated by the running Cloud SQL instance. Cloud SQL continues to
create charges while the instance is running, even with no traffic.

## Explicit Non-Events

- No image was pushed during preflight or local implementation.
- No Terraform apply was run.
- No secret version was created, read, printed, or committed.
- No live GitHub comment was written.
- No Scheduler activation occurred.
- No migration job was executed.
- No live executor was configured or invoked.
- No HolmesGPT or model call was made.
- No Kubernetes cluster was accessed.
- No SRE Platform files were changed.
- No credentials, database URLs, Terraform state files, raw plan files, raw
  GitHub comment bodies, or private operator notes were committed.
