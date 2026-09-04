# SRE Platform Staging Deployment Readiness Boundary

## Status

Planning and readiness only for Issue #57.

This document defines the boundary for a future SRE Platform staging deployment
that can later supply live read-only evidence to the AI Operations Platform
first SRE investigation MVP. It does not create a GCP project, create remote
state, deploy SRE Platform, access Kubernetes, run Terraform, create secrets,
activate the AI Operations Platform Scheduler, or validate live staging.

## Current Baseline

AI Operations Platform has:

- private GCP control-plane runtime in project `ai-operations-platform-507220`
  and region `us-central1`;
- PostgreSQL-backed task, attempt, result, evidence, publication, and human
  review state;
- bounded GCS evidence storage;
- opt-in allowlisted GitHub publication;
- bounded `sre_replay` executor for sanitized fixture validation;
- fake executor as the local, test, and private-runtime default.

The `sre_replay` executor proves the control-plane adapter boundary and
fixture contract. It does not prove live SRE Platform staging, production,
recovery, current Prometheus values, cluster state, or incident resolution.

SRE Platform repository context inspected for this readiness package:

- repository: `DimitryZH/sre-platform`;
- branch: `main`;
- inspected commit: `aecd1ad`;
- mode: local repository read-only only.

## Future Project Purpose And Naming

The future SRE Platform staging deployment should use a separate GCP project
from the AI Operations Platform control-plane project.

Purpose:

- host the SRE-owned Kubernetes staging environment;
- run Online Boutique staging workloads;
- run GitOps, progressive delivery, ingress, and Prometheus/SLO monitoring;
- expose tightly scoped read-only evidence surfaces to the AI Operations
  Platform control plane;
- keep SRE Platform runtime cost, IAM, remote state, and cleanup independent
  from the AI Operations Platform control plane.

Naming convention:

- project id pattern: `sre-platform-staging-<reviewed-suffix>`;
- environment label: `staging`;
- resource prefix: `sre-platform-staging`;
- cluster name: `sre-platform-staging`;
- namespace under investigation: `online-shop-stage`;
- GitOps application: `online-shop-stage`.

The exact project id and suffix must be chosen in the future deployment issue,
after billing, quota, organization policy, and operator access are reviewed.
No SRE Platform GCP project has been created or verified by this issue.

## Region And Zonal Assumptions

Default planning assumption:

- primary region: `us-central1`;
- initial environment type: bounded staging only;
- single-region deployment unless the future issue explicitly justifies
  multi-region cost and complexity;
- zonal or single-zone node placement may be preferred for cost-bounded staging
  if it still satisfies the demo and recovery evidence requirements;
- regional GKE or higher availability must be justified by the future budget
  and acceptance criteria.

The future issue must run read-only preflight for enabled regions, quota,
billing, service availability, and expected monthly cost before any cloud
write.

## Required APIs

Minimum API group to review before deployment:

- Service Usage API for controlled API enablement;
- Cloud Resource Manager API for project metadata and IAM inspection;
- Cloud Billing API for billing linkage inspection, if available to the
  operator;
- Compute Engine API for VPC, subnet, load balancer, and node resources;
- Kubernetes Engine API for the staging cluster;
- IAM API for service accounts and role bindings;
- Secret Manager API for runtime secrets, if the SRE Platform deployment needs
  any;
- Cloud Logging API for audit and platform logs;
- Cloud Monitoring API for metrics, SLOs, alerting, and budget-visible
  operational signals;
- Artifact Registry API only if SRE Platform images are built or mirrored in
  the staging project.

The future issue must show which APIs are already enabled and which would be
enabled, then request explicit approval before enabling any API.

## Resource Groups

The future deployment should be reviewed as explicit resource groups:

1. Project bootstrap:
   billing linkage, labels, API enablement, IAM baseline, budget alerts, and
   audit logging.
2. Terraform remote state:
   dedicated state bucket, uniform bucket-level access, public-access
   prevention, versioning, soft-delete recovery, no committed local state, and
   no committed raw plan files.
3. Network:
   VPC, subnet, firewall rules, load balancer/ingress exposure, optional NAT,
   and private access requirements.
4. Kubernetes staging:
   GKE cluster or approved equivalent, node service accounts, node pools,
   workload identity, release channel, resource quotas, and namespace
   separation.
5. GitOps and progressive delivery:
   Argo CD, Argo Rollouts, application root, stage application, rollback or
   abort behavior, and sync policy.
6. Online Boutique staging workload:
   `online-shop-stage` namespace, frontend workload, services, ingress, and
   stage overlay values.
7. Observability:
   ingress metrics, kube-prometheus-stack, Prometheus rules, SLO recording
   rules, dashboards, alert rules, and analysis templates.
8. Controlled failure mechanism:
   bounded baseline traffic, bounded failure traffic, break backend, failure
   path, stop/cleanup procedure, and evidence capture.
9. Read-only investigation access:
   least-privilege Kubernetes RBAC, Prometheus query access, GitOps read
   access, optional logs read access, optional recovery observation, and
   identity federation or credential delivery.
10. Cleanup and rollback:
    documented workload cleanup, failure-source cleanup, GitOps restore,
    Terraform destroy boundaries, state retention, and cost shutdown steps.

## Terraform Remote State Boundary

Future remote state must be separate from the AI Operations Platform state
bucket.

Requirements:

- one dedicated SRE Platform staging state bucket in the SRE Platform staging
  project or another reviewed infrastructure-admin project;
- project and bucket names reviewed before creation;
- uniform bucket-level access enabled;
- public access prevention enforced;
- versioning enabled;
- soft-delete recovery enabled;
- no bucket retention policy unless Terraform lock behavior is reviewed;
- no local state committed to Git;
- no raw saved plans committed to Git;
- state readers and writers limited to documented Terraform operators and
  break-glass project administrators;
- state access evidence sanitized before publication.

Every future `plan` must be saved as an ignored local artifact, summarized in a
sanitized form, and applied only after direct operator approval for that exact
saved plan.

## IAM And Operator Model

Human operator model:

- one documented project-admin or break-glass identity for the SRE Platform
  staging project;
- one or more Terraform operator identities with only the permissions required
  for reviewed infrastructure changes;
- no broad default Compute Engine service-account Editor binding;
- no public bucket principals;
- no secrets or principal IDs published in public evidence.

Runtime identity model:

- dedicated GKE node service account with minimum node role set;
- workload identity enabled for in-cluster workloads where practical;
- separate service account for read-only investigation access;
- no shared broad admin service account for AI Operations Platform access;
- no write-capable Kubernetes, GitOps, or recovery credentials granted to the
  AI Operations Platform control plane.

AI Operations Platform may later authenticate to a read-only evidence boundary
only after a separate approval gate. It must not receive cluster-admin,
namespace write, rollout mutate, GitOps sync, secret read beyond approved
credential references, or remediation authority.

## Budget And Cost Guardrails

The future deployment issue must include a current, region-specific estimate
before any cloud write. This readiness document intentionally does not assert a
current price because GCP pricing and committed-use assumptions can change.

Minimum guardrails:

- define an operator-approved monthly budget ceiling before project creation;
- create budget alerts before or during project bootstrap;
- show expected cost drivers before apply: GKE control plane, node pools,
  persistent disks, load balancer, NAT if used, logging ingestion, monitoring,
  Artifact Registry storage, and any retained evidence storage;
- start with minimum staging capacity that can still run Online Boutique,
  Argo CD, Argo Rollouts, ingress, and Prometheus;
- prefer scale-to-zero or zero-minimum node pools only where safe for the
  component;
- document what remains billable while idle;
- include a shutdown path for traffic generators, failure pods/jobs, node
  pools, load balancers, and retained storage;
- stop and re-review if the plan exceeds the approved budget ceiling or creates
  unexpected always-on resources.

Cost evidence must omit billing account IDs and private billing details.

## Staging Components To Deploy Later

The next deployment issue must explicitly deploy or verify these SRE Platform
staging components:

- Kubernetes staging environment, likely GKE or an approved equivalent;
- namespace `online-shop-stage`;
- ingress-nginx or approved ingress controller;
- Argo CD controller and root application;
- Argo Rollouts controller;
- `online-shop-stage` GitOps application from `DimitryZH/sre-platform` `main`;
- Online Boutique staging workload with frontend, cart, checkout, payment, and
  required supporting services from the stage overlay;
- frontend Argo Rollout named `frontend`;
- frontend stable and canary services;
- stage ingress path `/stage`;
- controlled failure path `/stage/break`;
- break backend returning deterministic HTTP 500 responses;
- Prometheus/kube-prometheus-stack with service and rule selectors covering
  `online-shop-stage`;
- SLO recording rules for `slo:error_ratio_5m` and `slo:burn_rate_5m`;
- rollout AnalysisTemplate `frontend-slo-check`;
- bounded baseline traffic mechanism;
- bounded controlled failure mechanism;
- read-only investigation service account and RBAC;
- sanitized evidence capture path for the AI Operations Platform.

## Read-Only Evidence Surfaces

AI Operations Platform may later read only the approved evidence surfaces:

- Kubernetes workload, pod, service, ingress, event, rollout, and AnalysisRun
  status in `online-shop-stage`;
- Prometheus instant or range query results for the approved SLO and ingress
  metric allowlist;
- GitOps repository files and commit references for the approved staging paths;
- Argo CD application status for `online-shop-stage`;
- bounded application or ingress logs for the approved namespace, workload, and
  time range, if log access is separately approved;
- optional recovery observation status after the SRE Platform has performed or
  approved recovery steps;
- sanitized evidence artifacts and references.

The approved Prometheus query allowlist for the first live validation should
start from:

- `slo:error_ratio_5m`;
- `slo:burn_rate_5m`;
- `sum(rate(nginx_ingress_controller_requests{exported_namespace="online-shop-stage",status!=""}[5m]))`.

Any additional query, namespace, workload, log selector, GitOps path, or
recovery observation must be added through a reviewed contract update.

## Actions AI Operations Platform Must Not Perform

AI Operations Platform must not:

- create or modify the SRE Platform GCP project;
- create, delete, patch, scale, restart, or exec into Kubernetes resources;
- apply Kubernetes manifests;
- run Helm, Argo CD sync, Argo Rollouts promote, abort, retry, or undo actions;
- start or stop baseline traffic or controlled failure traffic;
- change GitOps configuration;
- merge pull requests or close SRE Platform issues;
- read Kubernetes secrets or secret values;
- call HolmesGPT, another model, or any live investigator without a separate
  approval gate;
- claim staging, production, rollback, or recovery validation without direct
  evidence from the later deployment issue.

## Approval Gates For Future Work

The next cloud/deployment issue must stop and request direct approval before:

1. creating the SRE Platform GCP project;
2. linking billing or setting budget alerts, if not already complete;
3. enabling APIs;
4. creating remote state;
5. applying any bootstrap Terraform plan;
6. creating or updating secrets;
7. creating the Kubernetes cluster or node pools;
8. installing or syncing GitOps/progressive-delivery components;
9. deploying Online Boutique staging workloads;
10. starting baseline traffic;
11. starting controlled failure traffic;
12. granting AI Operations Platform read-only investigation access;
13. running a live read-only investigation;
14. publishing live GitHub investigation output;
15. running cleanup or destructive rollback.

Every approval request must include sanitized project id, region, resource
summary, IAM changes, cost impact, rollback path, and exact saved plan or
command boundary where applicable.

## Rollback And Cleanup Expectations

Future rollback must distinguish three concerns:

- operational recovery of the SRE Platform staging workload;
- infrastructure rollback or teardown;
- AI Operations Platform investigation state.

Minimum expectations:

- stop controlled failure traffic first through the SRE-owned procedure;
- verify the SLO window returns to a clean state before claiming recovery;
- restore GitOps desired state before manual cluster changes are considered
  complete;
- use Terraform destroy only after state backup, cost, and data-retention
  review;
- keep remote state and sanitized evidence long enough for audit unless an
  explicit retention decision says otherwise;
- revoke temporary AI Operations Platform read-only access after validation if
  it is not needed for continued work;
- document any resource left running and why it is still billable.

## Next Implementation Issue Checklist

The next issue should require:

- selected SRE Platform staging project id and billing boundary;
- current cost estimate and budget alert plan;
- remote-state bucket design and IAM access list;
- read-only preflight for account, project, APIs, quota, and org policies;
- exact Terraform bootstrap plan and approval gate;
- exact Kubernetes/GitOps deployment plan and approval gate;
- read-only RBAC manifest or Terraform module for the investigation identity;
- approved Prometheus query allowlist;
- approved Kubernetes resources, namespaces, and verbs;
- approved GitOps paths and Argo CD read scope;
- controlled baseline/failure start and cleanup plan;
- sanitized evidence package format;
- explicit statement that Scheduler activation, live executor promotion,
  GitHub publication, HolmesGPT/model calls, and cluster mutations remain
  separate gates unless the issue explicitly approves them.

## Non-Events For Issue #57

- No GCP project was created.
- No cloud write was performed.
- No Terraform plan or apply was performed.
- No remote state was created.
- No secret was created, read, or changed.
- No Kubernetes cluster was accessed.
- No SRE Platform deployment was performed.
- No SRE Platform repository file was modified.
- No AI Operations Platform Scheduler activation occurred.
- No live SRE investigation, HolmesGPT call, model call, or GitHub
  investigation publication occurred.
