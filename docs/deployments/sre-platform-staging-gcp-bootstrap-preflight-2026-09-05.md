# SRE Platform Staging GCP Bootstrap Preflight Evidence

## Status

Sanitized read-only preflight for Issue #59.

This evidence supports the cost-bounded bootstrap plan for a future separate
SRE Platform staging GCP project. It records only safe facts needed for
planning and review. It does not include account emails, credential details,
billing account identifiers, raw identity identifiers, database connection
strings, private notes, raw Terraform state, raw saved plans, cluster
credential files, or secret values.

## Scope

Repositories:

- AI Operations Platform: `DimitryZH/ai-operations-platform`
- SRE Platform: `DimitryZH/sre-platform`, local read-only context only

Target context:

- current AI Operations project boundary: `ai-operations-platform-507220`
- proposed future SRE Platform project id: `sre-platform-staging-507220`
- proposed region: `us-central1`
- proposed zone: `us-central1-b`

## Read-Only Checks Performed

GCP account and project context:

- active local `gcloud` account configured: yes
- active account identity: omitted
- local default configured project: `ai-operations-platform-497515`
- target AI Operations project explicitly checked:
  `ai-operations-platform-507220`
- target AI Operations project lifecycle: active
- target AI Operations project billing enabled: yes

Risk:

- the local default configured project is not the current AI Operations target
  project;
- every future write command must explicitly set the intended target project
  and must re-check context before execution;
- no future command may rely on implicit local default project configuration.

Current AI Operations runtime boundary:

- Cloud Run service checked in `us-central1`: `sre-control-plane-staging`
- Cloud Run ingress annotation: internal
- Scheduler job checked in `us-central1`:
  `sre-control-plane-staging-dispatch-tick`
- Scheduler state: `PAUSED`
- storage buckets visible in the AI Operations project:
  - Terraform state bucket in `US-CENTRAL1`, public access prevention enforced
  - evidence bucket in `US-CENTRAL1`, public access prevention enforced
  - Cloud Build bucket in `US`, inherited public access prevention

Relevant enabled APIs observed in the AI Operations project include:

- Artifact Registry API
- Cloud Run API
- Cloud Scheduler API
- Compute Engine API
- Cloud Logging API
- Cloud Monitoring API
- Cloud SQL Admin API
- Cloud Storage API
- IAM API
- Secret Manager API
- Service Networking API
- Service Usage API

This API list is evidence for the current AI Operations project only. It does
not prove readiness in the future SRE Platform staging project.

Selected current-project `us-central1` quota snapshot:

| Metric | Limit | Usage |
| --- | ---: | ---: |
| CPUS | 200 | 0 |
| E2_CPUS | 24 | 0 |
| INSTANCES | 24 | 0 |
| DISKS_TOTAL_GB | 4096 | 0 |
| STATIC_ADDRESSES | 8 | 0 |
| IN_USE_ADDRESSES | 8 | 0 |
| INSTANCE_GROUPS | 100 | 0 |
| AUTOSCALERS | 50 | 0 |

Limitation:

- these quotas are from the current AI Operations project and do not guarantee
  quota in a future separate SRE Platform staging project;
- future preflight must re-run quota checks after the SRE project exists or is
  selected.

Proposed SRE Platform project visibility:

- proposed project id: `sre-platform-staging-507220`
- current account visibility for proposed project id: not visible

Limitation:

- not visible is not the same as globally available;
- availability, project-creation permission, billing linkage, organization
  policy, and budget alert permission must be verified immediately before the
  project creation gate.

SRE Platform repository context:

- local repository status: clean on `main` tracking `origin/main`
- files inspected as read-only context:
  - `environments/stage/argocd/apps/online-shop-stage.yaml`
  - `environments/stage/values/platform.yaml`
  - `environments/stage/values/kube-prometheus-stack-shared.yaml`
  - `charts/platform/templates/prometheus-rules.yaml`
  - `charts/platform/templates/frontend-slo-check-analysis-template.yaml`
  - `charts/platform/templates/break-ingress.yaml`
  - `temp-stage-baseline-live.yaml`
  - `Makefile`

Repository-derived staging facts:

- staging namespace: `online-shop-stage`
- stage GitOps application: `online-shop-stage`
- stage path prefix: `/stage`
- controlled failure path: `/stage/break`
- frontend replicas in stage overlay: `1`
- Argo Rollouts enabled in stage overlay: yes
- primary SLO signals:
  - `slo:error_ratio_5m`
  - `slo:burn_rate_5m`
- current Prometheus selector context includes `online-shop-stage` and also
  includes wider repository context that should be narrowed for the future
  cost-bounded staging project.

## Pricing References Reviewed

Public pricing references reviewed on 2026-09-05:

- [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)
- [Compute Engine general-purpose pricing](https://cloud.google.com/products/compute/pricing/general-purpose)
- [Cloud Load Balancing pricing](https://cloud.google.com/load-balancing/pricing)
- [Cloud NAT pricing](https://cloud.google.com/nat/pricing)
- [Google Cloud Observability pricing](https://cloud.google.com/products/observability/pricing)
- [Managed Service for Prometheus billing](https://docs.cloud.google.com/stackdriver/docs/managed-prometheus#billing_and_quotas)
- [Cloud Storage pricing](https://cloud.google.com/storage/pricing)
- [Artifact Registry pricing](https://cloud.google.com/artifact-registry/pricing)

Planning assumptions are recorded in the cost-bounded bootstrap plan. No
private billing data was used.

## Cost Risk Finding

Logging and monitoring must be treated as a first-class cost risk for the next
deployment issue.

The planning conclusion is that logging and monitoring must be treated as a
first-class cost risk before any future SRE Platform staging write.

Guard statement: logging and monitoring must be treated as a first-class cost risk before any future SRE Platform staging write.

Required controls before any deployment:

- log exclusions or filters must exist before noisy workloads run;
- log retention must be short and explicit for demo logs;
- duplicate log routing must be absent;
- VPC Flow Logs, Firewall Rules Logging, Cloud NAT logging, verbose ingress
  logs, and Data Access audit logs must remain disabled unless separately
  approved with an estimate;
- Prometheus retention time and size must be bounded;
- scrape targets must be limited to approved namespaces and workloads;
- managed Prometheus ingestion must be disabled unless active-series and
  samples estimates are approved;
- demo traffic and failure traffic must be time-boxed;
- idle resources and retained data must be listed before the environment is
  left running.

Stop condition:

- if observability cost is unbounded, unclear, or above the approved
  observability budget, the deployment must stop before creating or running
  staging workloads.

## Non-Events

- No GCP project was created.
- No billing linkage was changed.
- No API was enabled.
- No budget alert was created.
- No remote-state bucket was created.
- No IAM binding was changed.
- No Terraform plan or apply was performed.
- No Kubernetes cluster was accessed.
- No SRE Platform deployment was performed.
- No secret was created, read, or changed.
- No Scheduler state was changed.
- No live investigation, GitHub investigation publication, HolmesGPT call, or
  model call was performed.
- No `DimitryZH/sre-platform` file was modified.
