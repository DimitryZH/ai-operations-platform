# SRE Platform Staging GCP Foundation Evidence

## Status

Sanitized foundation evidence for Issue #61.

This evidence records the minimal GCP foundation created for a future
cost-bounded SRE Platform staging project. It contains only sanitized facts and
does not include account emails, service-account emails, principal IDs, billing
account IDs, credential values, secret values, database URLs, raw Terraform
state, raw Terraform plans, variable files, cluster credential files, or private
operator notes.

## Scope

Repository workstream:

- primary repository: `DimitryZH/ai-operations-platform`
- SRE repository: `DimitryZH/sre-platform`, local read-only context only
- issue: #61
- milestone: `First SRE Investigation MVP`

Foundation target:

- project id: `sre-platform-staging-507220`
- project display name: `sre-platform-staging`
- region: `us-central1`
- zone assumption for later work: `us-central1-b`
- foundation date: 2026-09-06

## Preflight Findings

Before the first cloud write:

- active `gcloud` account configured: yes
- active account identity: omitted
- default configured project initially differed from the intended target;
  future write commands must explicitly set and re-check the target project
- current configured project after operator correction:
  `sre-platform-staging-507220`
- intended target project:
  `sre-platform-staging-507220`
- current AI Operations project checked as separate context:
  `ai-operations-platform-507220`
- current AI Operations project state: active
- current AI Operations billing enabled: yes
- SRE Platform repository status: clean local `main` tracking `origin/main`

## Approved Writes Performed

The work was executed through separate approval gates.

### Project And Billing Boundary

Created or confirmed:

- project id: `sre-platform-staging-507220`
- display name: `sre-platform-staging`
- lifecycle state: active
- billing enabled: yes
- labels:
  - `environment=staging`
  - `scope=foundation`
  - `platform=sre-platform`
  - `cost-profile=demo`

No Kubernetes, workload, runtime, logging-ingestion, or monitoring-ingestion
resource was created in this gate.

### Budget Alert

Created:

- budget display name: `sre-platform-staging-507220-foundation-budget`
- amount: `100CAD`
- scope: target project only
- thresholds:
  - 25%
  - 50%
  - 75%
  - 90%
  - 100%
- basis: current spend default
- notifications: default billing recipients only

Currency note:

- the billing account currency is CAD, so the approved budget amount was
  changed from the initial USD proposal to `100CAD` before creation.

Budget-management IAM note:

- budget creation required budget-management permissions on the billing
  account;
- read-only verification confirmed that `roles/billing.costsManager` includes
  the required budget create, update, get, and list permissions;
- the broad `roles/billing.admin` exception was removed after the budget was
  created;
- the budget can still be listed after the removal;
- `roles/billing.costsManager` remains present for the active budget-management
  identity and should be reviewed before long-term multi-operator use.

### API Enablement

Operator-enabled:

- Cloud Billing Budget API: `billingbudgets.googleapis.com`

Observed as enabled in the new project after foundation setup:

- Cloud Billing Budget API
- Cloud Storage API
- Cloud Storage JSON API
- Service Usage API
- Cloud Logging API
- Cloud Monitoring API

Important boundary:

- Cloud Logging and Cloud Monitoring APIs are enabled, but this issue did not
  create log buckets, sinks, exclusions, alerting policies, managed Prometheus,
  scrape configuration, workloads, or any deliberate logging/monitoring
  ingestion source.

Cost-heavy APIs verified disabled:

- Compute Engine API: disabled
- Kubernetes Engine API: disabled
- Cloud Run API: disabled
- Cloud Scheduler API: disabled
- Cloud SQL Admin API: disabled
- Service Networking API: disabled
- Cloud Build API: disabled
- Artifact Registry API: disabled
- Secret Manager API: disabled

### Remote Terraform State Bucket

Created and configured:

- bucket: `sre-platform-staging-507220-tf-state`
- location: `US-CENTRAL1`
- storage class: Standard
- uniform bucket-level access: enabled
- public access prevention: enforced
- versioning: enabled
- soft delete duration: seven days
- lifecycle rule: delete noncurrent object versions after 14 days

IAM hardening:

- public bucket principals: zero
- direct legacy bucket IAM members: zero
- direct bucket `roles/storage.admin` member count: one
- bucket IAM readable after hardening: yes
- temporary project-level `roles/storage.admin` recovery grant: removed

The direct bucket-level storage admin binding is the current Terraform state
operator access for the active identity. It should be replaced or narrowed to a
reviewed Terraform operator group or service account before multi-operator use.

### Project IAM Baseline

Read-only verification after hardening:

- public project IAM bindings: zero
- project owner binding count: one
- active identity has project Owner: yes
- active identity has project-level Storage Admin: no
- active identity has billing account `roles/billing.admin`: no
- active identity has billing account `roles/billing.costsManager`: yes
- default Compute Engine service account Editor binding count: zero

Human project Owner is retained as the documented project-admin or break-glass
identity for this foundation step. No AI Operations live read-only access was
granted.

## Cost Boundary

Allowed cost categories created:

- project metadata: no direct service cost
- budget alert: no direct service cost
- API enablement without resource creation: no direct service cost expected
- Terraform state bucket: very small storage cost for state, versions, and
  soft-deleted state objects
- IAM bindings: no direct service cost

Cost-heavy categories not created:

- no GKE cluster management fee
- no node pools
- no persistent disks for workloads
- no load balancer or ingress
- no Cloud NAT
- no Prometheus
- no managed metrics ingestion source
- no application logging ingestion source
- no Online Boutique workloads
- no traffic generators

Observability cost control remains a gate for the next deployment issue:
logging and monitoring APIs may be enabled, but no ingestion-heavy logging or
monitoring resources may be created until log exclusions, retention, Prometheus
retention, scrape targets, demo windows, idle behavior, and stop conditions are
reviewed and approved.

## Rollback And Cleanup

Project:

- if no later resources are approved, delete project
  `sre-platform-staging-507220` after confirming state/evidence retention is
  not needed.

Budget:

- delete `sre-platform-staging-507220-foundation-budget` if the project is
  removed or the budget needs a new scope/amount.

Billing IAM:

- do not re-add `roles/billing.admin` without a separate approval gate and
  documented need.
- remove or narrow `roles/billing.costsManager` when the budget no longer needs
  direct operator administration.

State bucket:

- before deleting the bucket, confirm that no Terraform state has been written
  or export reviewed state history.
- then delete bucket `sre-platform-staging-507220-tf-state`.

State bucket IAM:

- replace the direct active-identity bucket admin binding with a reviewed
  Terraform operator identity before shared use.

## Non-Events

- No Terraform plan or apply was performed.
- No raw state, raw plan, or variable file was created or committed.
- No Kubernetes cluster or node pool was created.
- No GitOps controller was installed.
- No Prometheus instance or managed Prometheus ingestion was created.
- No Online Boutique workload was deployed.
- No controlled failure or baseline traffic was started.
- No logging sink, log bucket, log exclusion, metric export, dashboard, or
  alerting policy was created by this issue.
- No AI Operations live read-only SRE access was granted.
- No AI Operations Scheduler change was performed.
- No GitHub investigation publication was performed.
- No HolmesGPT call, model call, or live investigation was performed.
- No `DimitryZH/sre-platform` file was modified.
