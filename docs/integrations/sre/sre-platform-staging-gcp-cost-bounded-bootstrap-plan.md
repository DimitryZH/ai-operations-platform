# SRE Platform Staging GCP Cost-Bounded Bootstrap Plan

## Status

Planning and preflight package for Issue #59.

This document prepares the next SRE Platform staging GCP bootstrap boundary. It
does not create a GCP project, link billing, enable APIs, create budget alerts,
create remote state, change IAM, create Kubernetes resources, deploy
SRE Platform, create secrets, run Terraform, access a cluster, activate
Scheduler, run a live investigation, publish GitHub investigation output, or
modify `DimitryZH/sre-platform`.

The previous SRE Platform deployment cost risk is treated as a first-class
design constraint: cluster cost and logging/monitoring ingestion or retention
can be comparable. The next staging design must bound both before any cloud
write.

## Current Read-Only Preflight Summary

Read-only preflight evidence is recorded in
[SRE Platform staging GCP bootstrap preflight evidence](../../deployments/sre-platform-staging-gcp-bootstrap-preflight-2026-09-05.md).

Sanitized findings:

- an active local `gcloud` account is configured, but the account identity is
  intentionally omitted;
- the local default configured project is not the current AI Operations target
  project, so every future write command must explicitly set and re-verify the
  intended project;
- the current AI Operations Platform project `ai-operations-platform-507220`
  was verified as active and billing-enabled;
- current AI Operations private runtime boundaries remain unchanged:
  Cloud Run ingress is internal, Scheduler is paused, and storage buckets use
  public access prevention;
- selected `us-central1` quota in the current AI Operations project has unused
  capacity for small compute and disk experiments, but those quotas do not
  prove quota in a future separate SRE Platform staging project;
- proposed SRE Platform project id `sre-platform-staging-507220` is not visible
  to the current account, but global availability and creation permission must
  be verified at the project-creation gate;
- `DimitryZH/sre-platform` was inspected only as a local read-only repository
  context and was not changed.

## Proposed Project Boundary

Purpose:

- host a portfolio/demo-oriented SRE Platform staging environment;
- run only the staging components needed to prove live read-only evidence for
  the first SRE investigation MVP;
- keep SRE Platform cost, IAM, state, cleanup, and failure ownership separate
  from the AI Operations Platform control plane;
- allow AI Operations Platform to read only explicitly approved evidence
  surfaces after a later approval gate.

Proposed identity:

- project id candidate: `sre-platform-staging-507220`;
- display name candidate: `sre-platform-staging`;
- environment label: `staging`;
- resource prefix: `sre-platform-staging`;
- cluster name candidate: `sre-platform-staging`;
- namespace under investigation: `online-shop-stage`;
- GitOps application: `online-shop-stage`.

The project id remains only a proposal. A future write gate must verify global
project-id availability, project-creation permissions, billing linkage,
organization policies, and budget controls before creation.

## Region And Zone Assumptions

Default proposal:

- region: `us-central1`;
- preferred initial zone: `us-central1-b`;
- cluster topology: zonal Standard GKE for the first cost-bounded demo unless
  Autopilot produces a lower verified estimate;
- regional GKE is not the default because it raises availability and cost
  beyond the portfolio/demo objective;
- multi-region deployment is out of scope.

Rationale:

- `us-central1` aligns with the current AI Operations Platform runtime and
  keeps cross-region data movement simple;
- a zonal Standard cluster can use the GKE monthly management-fee credit if
  the billing account is eligible, while regional cluster management fees are
  not the cost-bounded default;
- the stage workload should be run only during controlled demo windows and
  shut down or destroyed when idle.

## Required Permissions

Before the first write, the operator must prove, without publishing sensitive
identity details, that the acting identity can perform only the approved write
category.

Project and billing gate:

- create the selected project or confirm it already exists;
- link or verify billing;
- create or verify budget alerts;
- set labels and basic project metadata.

Bootstrap gate:

- enable approved APIs;
- create a dedicated Terraform state bucket;
- create baseline IAM bindings;
- create network bootstrap resources only if explicitly included.

Kubernetes gate:

- create the cluster or node pool only after a saved plan is reviewed;
- create only the approved node service account and Workload Identity boundary;
- avoid broad default service account roles.

Observability gate:

- create or update log buckets, sinks, exclusions, retention, Prometheus
  retention, and scrape configuration only after cost controls are explicit.

AI Operations read-only gate:

- grant only read-only Kubernetes, Prometheus, GitOps, and optional log
  evidence access;
- no cluster-admin, write, rollout mutation, secret read, GitOps sync, or
  remediation authority.

## Required APIs

The initial API set should stay minimal:

- Cloud Resource Manager API;
- Cloud Billing API, if the operator has billing visibility;
- Cloud Billing Budget API;
- Service Usage API;
- IAM API;
- Compute Engine API;
- Kubernetes Engine API;
- Cloud Logging API;
- Cloud Monitoring API;
- Cloud Storage API;
- Artifact Registry API only if images are built or mirrored in this project;
- Secret Manager API only if later SRE Platform deployment requires secret
  containers.

API enablement is a separate write category. The future request must list the
exact APIs to enable, show already-enabled APIs where available, and request
direct approval before enabling them.

## Terraform Remote-State Design

State must be separate from the AI Operations Platform state bucket.

Proposed bucket:

- bucket name candidate: `sre-platform-staging-507220-tf-state`;
- location: `us-central1`;
- storage class: Standard;
- uniform bucket-level access: enabled;
- public access prevention: enforced;
- object versioning: enabled;
- soft-delete recovery: short bounded window, initially seven days;
- lifecycle cleanup for noncurrent versions after a reviewed short window;
- no retention lock unless separately approved;
- no committed local state files;
- no committed raw saved plan files.

Access model:

- read/write: documented Terraform operator identities and break-glass
  project administrators only;
- read-only audit: only if explicitly approved;
- no public principals;
- no direct legacy bucket roles;
- no shared default service account state access.

Every future Terraform plan must be saved as an ignored local artifact,
summarized in sanitized form, and applied only after direct approval for that
exact saved plan.

## IAM And Operator Model

Project-level model:

- one documented human project-admin or break-glass identity;
- one Terraform operator identity or group with bounded infrastructure roles;
- no broad default Compute Engine service-account Editor binding;
- no public bucket principals;
- no published emails, credential details, or raw identity identifiers in
  public evidence.

Runtime model:

- dedicated GKE node service account;
- Workload Identity enabled where practical;
- separate read-only investigation service account for AI Operations Platform;
- namespace-scoped Kubernetes read permissions for `online-shop-stage`;
- Prometheus read access restricted to approved query surfaces;
- GitOps read access restricted to approved repository paths and commit refs;
- optional log read access only for approved namespace/workload/time windows.

Denied by default:

- Kubernetes create, update, patch, delete, scale, restart, exec, or port
  forwarding;
- Argo CD sync, refresh, terminate, delete, rollback, or application mutation;
- Argo Rollouts promote, abort, retry, undo, pause, resume, or set-image;
- Secret Manager value access except specifically approved credential
  references;
- Git write permissions;
- broad project roles for runtime identities.

## Resource Groups

The future bootstrap should be split into separately approved groups:

1. Project and billing:
   project creation, billing linkage, labels, budget alerts, and spend
   notifications.
2. APIs:
   exact API allowlist only.
3. Remote state:
   dedicated state bucket and state IAM.
4. IAM baseline:
   human admin, Terraform operator, node identity, read-only investigation
   identity, and no broad default bindings.
5. Network:
   VPC, subnet, firewall, private access, optional Cloud NAT, and ingress
   exposure.
6. Kubernetes:
   zonal Standard GKE or separately justified alternative, bounded node pool,
   Workload Identity, release channel, quotas, and maintenance windows.
7. Observability:
   log routing, exclusions, retention, Prometheus scrape limits, retention,
   alert rules, dashboards, and ingestion guardrails.
8. GitOps and progressive delivery:
   Argo CD, Argo Rollouts, root application, stage application, and rollback
   behavior.
9. Online Boutique staging:
   `online-shop-stage` namespace, stage values, frontend rollout, services,
   ingress paths, and supporting services.
10. Controlled demo traffic:
    baseline traffic, failure traffic, bounded windows, and cleanup.
11. AI Operations read-only evidence access:
    approved evidence surfaces, read-only RBAC, and sanitized evidence
    contract.
12. Cleanup:
    failure stop, workload teardown, node-pool scale-down or deletion, log and
    metric retention review, and state/evidence retention.

## Observability Cost Controls

Observability is a cost-critical part of the design, not an afterthought.

### Logging Strategy

Default position:

- keep the `_Required` bucket unchanged for mandatory audit logs;
- disable storage of high-volume application, request, and platform logs in
  the default bucket unless they match an approved evidence filter;
- create a short-retention user log bucket only if the later issue requires
  log evidence;
- configure log sinks and exclusions before deploying noisy workloads;
- do not enable VPC Flow Logs, Firewall Rules Logging, Cloud NAT logging,
  Data Access audit logs, or verbose ingress logs unless separately approved
  with an estimate;
- never route the same logs to multiple billable buckets.

Initial evidence filters should prefer:

- warnings and errors for `online-shop-stage`;
- Argo CD and Argo Rollouts reconciliation failures;
- ingress controller errors for `/stage` and `/stage/break`;
- explicitly marked demo-window logs;
- no raw request-body capture.

Retention:

- keep custom demo log retention at seven days by default;
- keep only mandatory audit logs in the required bucket;
- require re-approval for retention longer than seven days on demo logs;
- stop if the proposed design cannot show the retained bucket, retention days,
  exclusions, and expected GiB per demo window.

### Metrics And Prometheus Strategy

Default position:

- use self-managed kube-prometheus-stack inside the cluster for the first
  staging demo unless Managed Service for Prometheus has an explicitly bounded
  sample estimate;
- avoid unbounded managed Prometheus ingestion;
- keep Prometheus retention time short, initially 24 hours or less;
- set Prometheus retention size, initially no more than 2 GiB;
- scrape only namespaces required for the demo:
  `online-shop-stage`, `ingress-nginx`, `monitoring`, `argocd`, and
  `argo-rollouts`;
- remove `online-shop-dev` from staging scrape selectors unless a future issue
  explicitly needs it;
- prefer explicit ServiceMonitor selectors over namespace-wide discovery;
- drop high-cardinality labels and metrics that are not needed for the
  approved SLO or controller health checks.

Approved first metrics:

- `slo:error_ratio_5m`;
- `slo:burn_rate_5m`;
- ingress request rate for `online-shop-stage`;
- minimal Argo Rollouts and Argo CD health signals;
- Prometheus self-health and scrape error signals.

Stop if the Prometheus design cannot estimate active series, scrape interval,
samples per second, retention size, and whether any samples are exported to
Managed Service for Prometheus.

### Demo Window Controls

The future demo should be time-boxed:

- create infrastructure only for an approved window;
- run baseline and failure traffic only for the approved duration;
- stop or delete traffic generators immediately after evidence capture;
- scale down or delete node pools after the demo if further validation is not
  scheduled;
- delete load balancers and NAT when not needed;
- retain only bounded sanitized evidence and the minimum Terraform state
  history needed for audit.

### Idle Behavior

Billable while idle:

- GKE cluster management fee unless covered by eligible credit;
- any running nodes;
- persistent disks and snapshots;
- load balancer forwarding rules;
- Cloud NAT gateway, IP address, and processed traffic if NAT exists;
- stored logs beyond free allotments or duplicated log routing;
- Managed Service for Prometheus samples if export remains enabled;
- Artifact Registry storage above free tier;
- Cloud Storage state and evidence objects, including noncurrent versions and
  soft-deleted data.

Idle target:

- no traffic generators;
- no controlled failure source;
- no unnecessary public ingress;
- node pool scaled to zero only if supported and operationally safe, otherwise
  cluster destroyed when the demo window closes;
- Prometheus and logging ingestion reduced to mandatory audit and minimal
  health signals;
- explicit owner decision for every resource left running.

## Category-Level Cost Estimate

Estimate basis:

- public Google Cloud pricing pages reviewed on 2026-09-05;
- USD list pricing, no private discounts or commitments assumed;
- `us-central1` where region-specific pricing matters;
- one bounded staging environment, not production;
- no billing account IDs or private billing data used.

Public references:

- [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)
- [Compute Engine general-purpose pricing](https://cloud.google.com/products/compute/pricing/general-purpose)
- [Cloud Load Balancing pricing](https://cloud.google.com/load-balancing/pricing)
- [Cloud NAT pricing](https://cloud.google.com/nat/pricing)
- [Google Cloud Observability pricing](https://cloud.google.com/products/observability/pricing)
- [Managed Service for Prometheus billing](https://docs.cloud.google.com/stackdriver/docs/managed-prometheus#billing_and_quotas)
- [Cloud Storage pricing](https://cloud.google.com/storage/pricing)
- [Artifact Registry pricing](https://cloud.google.com/artifact-registry/pricing)

Full-month envelope if left running:

| Category | Expected monthly range | Cost control |
| --- | ---: | --- |
| Project, labels, API enablement, budget alerts | USD 0 direct service cost | APIs must not imply resource creation. |
| Terraform state bucket | USD 0-2 | Keep state small; versioning and soft delete bounded by lifecycle rules. |
| GKE cluster management | USD 0-75 | Prefer zonal Standard or Autopilot only if credit eligibility is verified; avoid regional GKE by default. |
| Node pools | USD 50-180 | Start with one or two modest E2 nodes; require approval if Online Boutique plus observability needs more. |
| Persistent disks | USD 5-30 | Bound boot disks and Prometheus storage; no orphaned disks. |
| Load balancer / ingress | USD 18-30 plus traffic | One forwarding rule; low demo traffic; delete after demo if not needed. |
| Cloud NAT | USD 0 preferred, USD 10-45 if required | Avoid NAT first; if needed, one small NAT with logging disabled. |
| Cloud Logging ingestion and retention | USD 0-50 target, stop above target | Exclusions before noisy workloads; seven-day custom retention; avoid duplicate routing. |
| Cloud Monitoring and Prometheus | USD 0-30 target, stop above target | Self-managed Prometheus first; managed sample export disabled unless bounded. |
| Artifact Registry | USD 0-2 | Reuse small image set; lifecycle cleanup old images. |
| Evidence storage | USD 0-2 | Store only sanitized bounded evidence. |

Proposed full-month guardrail: stop and re-review if the planned always-on
range exceeds USD 250/month or if observability alone is projected above
USD 80/month.

Portfolio/demo operating target:

- run the environment only during approved demo windows;
- target less than USD 25-60 for a one-to-five-day demo window with low log and
  metric volume;
- destroy or scale down immediately after evidence capture unless a follow-up
  issue explicitly approves continued operation.

These are planning estimates, not billing commitments. The future issue must
rerun the pricing calculator or equivalent current public estimate immediately
before any write.

## Observability Stop Conditions

Stop before deployment if any of these are true:

- if observability cost is unbounded, unclear, or above the approved
  observability budget, deployment stops;
- log exclusions or filters must exist before noisy workloads run;
- log retention must be short and explicit;
- duplicate log routing must be absent;
- Prometheus retention time and size must be bounded;
- scrape targets must be limited;
- managed Prometheus ingestion must be disabled unless active-series and
  samples estimates are approved;
- demo traffic and failure traffic must be time-boxed;
- log storage destination, exclusions, or retention are undefined;
- estimated log ingestion is unknown for the demo window;
- duplicate log routing is present;
- VPC Flow Logs, Firewall Rules Logging, Cloud NAT logging, Data Access audit
  logs, or verbose ingress logs are enabled without a separate estimate;
- Managed Service for Prometheus is enabled without active-series and samples
  estimates;
- Prometheus retention time or size is unbounded;
- scrape discovery includes namespaces or workloads outside the approved demo;
- monitoring or logging estimate exceeds the approved observability budget;
- the design cannot identify what remains billable while idle;
- cleanup cannot prove that traffic generators, failure mechanisms, node
  pools, load balancers, NAT, and retained data are bounded.

## Approval Gates

The next issue must stop and request direct approval before each write
category:

1. project creation or billing linkage;
2. API enablement;
3. budget alert creation;
4. remote-state bucket creation;
5. IAM changes;
6. exact saved Terraform plan apply;
7. Kubernetes cluster or node-pool creation;
8. logging or monitoring configuration;
9. SRE Platform workload or GitOps deployment.

Before the first cloud write, the approval packet must show:

- active account configured, without identity details;
- current configured project and explicit target project;
- proposed SRE Platform project id and display name;
- region and zone;
- required permissions for the specific write;
- expected resources;
- category-level cost estimate;
- logging and monitoring cost-control plan;
- remote-state design;
- IAM changes;
- rollback and cleanup path.

Exact first-write approval question for the future issue:

```text
Do you approve the first cloud write category for project creation and billing
boundary setup for proposed project sre-platform-staging-507220 in us-central1,
with no APIs, remote state, IAM, Kubernetes, logging/monitoring configuration,
or SRE Platform deployment created in the same step?
```

Each later write category must use its own exact approval question and must not
piggyback on an earlier approval.

## Rollback And Cleanup Path

Project and billing:

- remove billing only after verifying there are no retained resources that
  require cleanup;
- keep budget alerts until teardown is complete;
- delete the project only after state and evidence retention are explicitly
  resolved.

Remote state:

- preserve final state and sanitized evidence until the retention decision is
  documented;
- remove temporary operator IAM after teardown;
- delete noncurrent versions according to the approved lifecycle.

Kubernetes and workloads:

- stop failure traffic first;
- stop baseline traffic after evidence capture;
- allow SRE Platform GitOps to converge back to healthy desired state;
- delete or scale down node pools;
- delete load balancer and NAT resources when not needed;
- verify no orphaned disks, IP addresses, or forwarding rules remain.

Observability:

- verify no high-volume log sinks remain active;
- verify custom demo log bucket retention and lifecycle;
- stop managed metric export if it was enabled;
- remove dashboards or alert policies only after evidence is retained;
- record final cost-risk notes without private billing data.

AI Operations Platform:

- do not change Scheduler state;
- do not promote `sre_replay` to live access without a separate issue;
- revoke temporary read-only evidence access when validation ends unless
  explicitly retained.

## Non-Events For Issue #59

- No GCP project was created.
- No project billing linkage was changed.
- No API was enabled.
- No budget alert was created.
- No remote-state bucket was created.
- No IAM binding was changed.
- No Terraform plan or apply was performed.
- No Kubernetes cluster, node pool, GitOps controller, Prometheus instance,
  workload, secret, Scheduler change, live investigation, GitHub publication,
  HolmesGPT call, or model call was created or executed.
- No `DimitryZH/sre-platform` file was modified.
