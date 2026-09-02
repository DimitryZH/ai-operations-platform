# GCP SRE Control-Plane GCS Evidence Adapter Evidence - 2026-09-02

This document records sanitized evidence for Issue #51. It intentionally omits
account emails, service-account emails, principal IDs, billing account IDs,
credentials, secret values, Terraform state, raw Terraform plan files, raw
object contents, and raw logs.

## Scope

- GitHub issue: #51
- Repository branch: `codex/issue-51-gcs-evidence-adapter`
- Target project: `ai-operations-platform-507220`
- Target region: `us-central1`
- Deployment phase: `runtime`
- Evidence bucket: existing `sre-cp-staging-evidence` bucket for this project
- Runtime mode: fake executor and fake publisher only
- Cloud Run boundary: private internal ingress with authenticated invocation
- Scheduler boundary: remains `PAUSED`
- Integration boundary: no SRE Platform repository mutation and no cluster
  access

## Preconditions Verified

- PR #50 was merged and Issue #49 was closed before this work started.
- The accepted bootstrap and private fake runtime existed in the target project
  and region.
- The Terraform backend used the protected GCS state bucket from Issue #47.
- A normal Terraform plan with explicit non-secret runtime variables returned
  no changes before this issue's code and Terraform changes.
- Cloud Run was Ready, internal-only, authenticated, configured for automatic
  zero-minimum service-level scaling, and bounded to one template instance.
- Cloud Scheduler existed in `PAUSED` state.
- The existing evidence bucket had uniform bucket-level access enabled, public
  access prevention enforced, and versioning enabled.
- Public principals on the evidence bucket: zero `allUsers` or
  `allAuthenticatedUsers`.
- Effective evidence-bucket IAM included the expected runtime service-account
  identity type and project legacy principal types. Those broad project-derived
  principal types were documented as an existing access limitation and were not
  changed before a reviewed Terraform plan.
- Live Cloud Run did not yet have the GCS evidence adapter environment
  variables before this change.
- A read-only Terraform plan against remote state, using the previously
  deployed immutable image digest and current non-secret runtime variables,
  returned: 2 to add, 1 to change, 1 to destroy.
- The planned pre-image-push changes were limited to the Cloud Run service
  configuration and replacement of the runtime evidence bucket IAM member from
  broad object access to bucket-scoped object creator and object viewer roles.
- SRE Platform read-only context was checked; no files were modified there.

## Adapter Contract

- PostgreSQL remains the source of truth for task, attempt, result, evidence
  reference, publication, and review state.
- The GCS adapter is behind the product-neutral evidence-store interface and
  stores only sanitized JSON packages.
- Cloud Storage calls happen after the publication intent is durably claimed
  and outside database transactions and database locks.
- Object identity is deterministic:
  `evidence/sha256/<package-sha256>.json`.
- Object creation uses Cloud Storage generation precondition `0`, so a repeated
  identical write is semantic idempotency and a conflicting object fails closed.
- The adapter verifies remote object size, exact content type, exact reviewed
  metadata contract, bounded readback size, and SHA-256 content integrity before
  returning artifact metadata to the workflow.
- The returned artifact contract accepts only bounded `gs://` evidence objects
  and local development evidence objects.
- Local filesystem evidence remains the default adapter for local development.

## Planned Runtime Change

The reviewed Terraform update is expected to:

- deploy a new immutable Cloud Run image that includes the GCS adapter code;
- configure Cloud Run environment variables for the GCS evidence adapter and
  the existing evidence bucket;
- replace broad runtime bucket object access with bucket-scoped
  `roles/storage.objectCreator` and `roles/storage.objectViewer`;
- keep fake executor and fake publisher defaults;
- keep private Cloud Run ingress and authenticated invocation;
- keep Scheduler paused;
- avoid creating new buckets, new secret versions, Cloud Run jobs, Scheduler
  activation, runtime adapter credentials, or cluster access.

## Image Evidence

- Source commit for the pushed runtime image:
  `f4b7953578d9ac49af79c826eadc460e70f675a0`
- Runtime image: immutable Artifact Registry digest
  `sha256:8e216ce378ba21d0f734aaffa7bf995e3f7a8ffa860a7e4df7a1a44a17ba2b6c`
- Local image build succeeded with the GCS storage client dependency.
- Local container smoke test started the image and `/healthz` returned `ok`.
- Mutable tags were not used in Terraform runtime configuration.

## Exact Saved Terraform Plan

- Saved plan file: ignored local artifact `issue51-gcs-evidence.tfplan`
- Saved plan SHA-256:
  `ea1b103d2984ffaabe30828ce8b104359716c7b398c5f7561203ef63ee3218d6`
- Plan summary: 2 to add, 2 to change, 1 to destroy
- Planned resource actions:
  - update Cloud Run service in place to use the immutable image digest and GCS
    evidence adapter environment variables;
  - update the existing migration job in place to the same immutable image
    digest without executing it;
  - add bucket-scoped runtime `roles/storage.objectCreator`;
  - add bucket-scoped runtime `roles/storage.objectViewer`;
  - remove the previous runtime `roles/storage.objectUser` bucket IAM member.
- Plan safety checks:
  - private internal Cloud Run ingress remains configured;
  - Cloud Run service-level scaling remains automatic with zero minimum and zero
    manual instances;
  - template-level maximum instances remains `1`;
  - Scheduler remains paused;
  - fake executor and fake publisher remain locked defaults;
  - no secret versions, Cloud Run public invokers, new buckets, Scheduler
    activation, real executor, or GitHub publisher configuration are planned.
- Apply result for the exact saved plan: 2 added, 2 changed, 1 destroyed.

## Post-Apply Verification

Read-only checks after apply confirmed:

- Cloud Run Ready condition: true
- Cloud Run ingress: internal
- Cloud Run image: immutable digest from this evidence
- Cloud Run GCS evidence environment:
  - store mode: `gcs`
  - project matched the reviewed project
  - bucket matched the existing evidence bucket
- Cloud Run service-level scaling: automatic
- Cloud Run template scaling: zero minimum instances and one maximum instance
- Scheduler job state: `PAUSED`
- Scheduler retry policy block: absent
- Evidence bucket public principals: zero `allUsers` or
  `allAuthenticatedUsers`
- Evidence bucket runtime object roles: `roles/storage.objectCreator` and
  `roles/storage.objectViewer`
- Evidence bucket runtime object member type: service account
- Existing broad evidence-bucket legacy principal types remained:
  `projectOwner`, `projectEditor`, and `projectViewer`
- Terraform no-change plan after apply: no changes

## Review Correction - Bounded GCS Readback

Draft PR review found that GCS object readback needed stronger fail-closed
validation before accepting an existing object or a newly-created object.

The correction adds these runtime guarantees:

- remote object metadata is refreshed before readback;
- missing, malformed, negative, oversized, or unexpected remote object size is
  terminal failure before content download;
- object content type must be exactly `application/json`;
- custom metadata must match the complete reviewed contract exactly, with no
  missing, incomplete, additional, unsafe, or conflicting entries;
- object bytes are fetched with a bounded range using the expected object size;
- downloaded byte count and SHA-256 are rechecked before returning an artifact
  reference;
- GCS exception details, raw metadata, endpoint details, and raw object contents
  are not returned in errors or durable publication state;
- retryable classification is preserved only for sanitized transport/storage
  availability failures.

Local regression tests were added for missing, incomplete, additional, unsafe,
and conflicting metadata; missing and wrong content type; missing, malformed,
negative, oversized, and unexpected remote size; oversized readback; integrity
mismatch; retryable transport failure; and durable-state sanitization.

Read-only verification before deployment of this correction confirmed:

- Cloud Run remained Ready with private internal ingress;
- Cloud Run still used the previously deployed immutable image digest;
- Cloud Run retained GCS evidence-store environment selection for the reviewed
  project and existing evidence bucket;
- Cloud Run service-level scaling remained automatic;
- Cloud Run template-level scaling remained zero minimum and one maximum
  instance;
- the migration job still used the same previously deployed immutable image
  digest and zero retries;
- Scheduler remained `PAUSED`;
- the evidence bucket retained uniform bucket-level access, public-access
  prevention, retention, soft delete, and versioning;
- evidence prefix listing showed exactly the previously recorded smoke object;
- a Terraform plan with the current deployed image digest returned no changes.

No new smoke object was created or modified for this correction.

Correction deployment evidence:

- Source commit for the corrected runtime image:
  `246eb62b8f1d2b14dd6e1a0fb04347ab5489f23f`
- Corrected runtime image: immutable Artifact Registry digest
  `sha256:685d0726e80a1e43c77086bf615c66256dc21202532b799f06fb25dee0d2b9a6`
- Cloud Build API was not enabled for this correction, and no API enablement
  was performed. The approved image push used the local Docker Desktop build
  and Docker push path with the configured Artifact Registry credential helper.
- Saved correction plan file: ignored local artifact
  `issue51-bounded-readback.tfplan`
- Saved correction plan SHA-256:
  `6d1d6d7fe993b25d968fc64c78623ca30550e2888dd4dac5199c6db2e3bde770`
- Correction plan summary: 0 to add, 2 to change, 0 to destroy
- Correction plan resource actions:
  - update the Cloud Run service image digest in place;
  - update the Cloud Run migration job image digest in place without executing
    it.
- Correction plan safety checks:
  - no IAM changes;
  - no Scheduler activation or retry-policy change;
  - no secret versions;
  - no bucket or object changes;
  - no executor, publisher, ingress, scaling, or database changes.
- Apply result for the exact saved correction plan: 0 added, 2 changed, 0
  destroyed.

Read-only verification after the correction apply confirmed:

- Cloud Run Ready condition: true
- Cloud Run ingress: internal
- Cloud Run image: corrected immutable digest from this section
- Cloud Run retained GCS evidence environment selection for the reviewed
  project and existing evidence bucket
- Cloud Run service-level scaling: automatic
- Cloud Run template scaling: zero minimum instances and one maximum instance
- migration job image: corrected immutable digest from this section
- migration job execution count did not increase
- migration job max retries: zero
- Scheduler job state: `PAUSED`
- evidence prefix listing showed exactly the previously recorded smoke object
- Terraform no-change plan after apply: no changes

## Smoke Attempt Troubleshooting

Three approved temporary-job attempts did not create an evidence object:

- The first attempt completed without running the smoke script because the
  Cloud Run job argument list split the Python runner at commas. The temporary
  job was deleted.
- The second attempt executed the smoke script but received HTTP 404 before the
  request reached the application routes. Read-only service logs showed only
  health probes, and bucket metadata showed zero objects under
  `evidence/sha256/` after the failed attempt. The likely cause is that the
  temporary job did not use direct VPC egress for the internal-only service.
- The third attempt used direct VPC egress and reached the private application,
  but the request contract rejected the smoke payload with HTTP 422 because the
  source system was not the accepted `sre-platform` value. A corrected smoke
  payload was validated locally before requesting another write attempt.

No raw response bodies, object contents, credentials, or secret values were
recorded. No Scheduler activation, migration execution, live executor, GitHub
publisher, cluster access, or SRE Platform mutation occurred.

## Smoke Evidence

The final approved smoke used a corrected payload with the accepted
`source.system` value and direct VPC egress. Read-only checks after the smoke
confirmed:

- temporary smoke job: deleted after execution
- submitted marked fake investigation request: HTTP 201
- internal dispatch tick: HTTP 200
- evidence publication call: HTTP 200
- repeated evidence publication call with the same idempotency key: HTTP 200
- smoke objects under `evidence/sha256/`: exactly one
- artifact scheme: `gs`
- object name SHA-256 length: 64
- object content type: `application/json`
- object size: 6298 bytes
- object retention expiration: present
- custom metadata SHA-256 length: 64
- custom metadata SHA-256 matched object identity
- custom metadata sanitization status: `SANITIZED`
- custom metadata identity prefix: `sha256`
- readback content SHA-256 matched object identity
- raw object contents were not committed or published
- Cloud Run remained Ready and internal-only
- Scheduler remained `PAUSED`
- Terraform plan after the smoke: no changes

## Approval Gates

Separate operator approval is required immediately before each cloud write:

- push the immutable container image to Artifact Registry;
- apply the exact saved Terraform plan;
- write one marked fake-investigation smoke object through the private runtime.

If an exact saved Terraform plan contains any unexpected resource, IAM,
Scheduler, secret, image, executor, publisher, or public-ingress change, the
apply must stop for review.

## Pre-Deployment Validation

- Evidence publication regression tests after the bounded readback correction:
  42 passed.
- Deployment regression and configuration tests after the correction: 27
  passed.
- Full local test suite after the correction: 190 passed, 16 skipped. The
  skipped tests were
  opt-in live or PostgreSQL-integration tests requiring external configuration
  unavailable in the local shell.
- Terraform static validation succeeded. The sandboxed run also attempted a
  remote backend read and was blocked by local network sandboxing, so the
  remote-state plan was executed separately as an escalated read-only command.
- Local Docker image build for the corrected runtime succeeded and `/healthz`
  returned `ok`.

## Cost Estimate

Estimated incremental monthly cost for this adapter change in `us-central1` is
approximately **USD 0-5/month** at current low volume.

Main incremental cost drivers and assumptions:

- one additional Artifact Registry image digest, expected to be low storage
  cost for a small image;
- small Cloud Storage object storage, readback, and metadata operations in the
  existing evidence bucket;
- a new Cloud Run revision with minimum instances kept at zero, so idle service
  cost should remain near zero;
- one approved smoke write and related readback operations only.

The existing private runtime baseline still carries the larger steady-state
cost, dominated by the running Cloud SQL instance. Cloud SQL continues to create
charges while the instance is running, even with no traffic.

## Explicit Non-Events

- No Scheduler activation occurred.
- No public Cloud Run ingress or public invoker was configured.
- No live executor was configured or invoked.
- No live GitHub publisher was configured or invoked by the application.
- No HolmesGPT or model call was made.
- No Kubernetes cluster was accessed.
- No SRE Platform files were changed.
- No credentials, secret values, state files, raw object contents, or raw plan
  files were committed.
