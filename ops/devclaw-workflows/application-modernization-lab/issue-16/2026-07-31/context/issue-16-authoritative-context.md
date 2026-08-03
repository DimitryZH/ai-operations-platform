# Issue 16 Authoritative Developer Context

Generated: 2026-08-01T16:20:13Z

Source: GitHub API via DevClaw GitHub token broker.

## Current Issue #16

Title: Migrate the accepted AKS Store Demo Docker Compose baseline to .NET Aspire
State: open
Labels: Implementing, developer:senior, review:human, notify:openclaw:primary, owner:Josefina
URL: https://github.com/DimitryZH/application-modernization-lab/issues/16

### Body


## Objective

Migrate the accepted Experiment 08A AKS Store Demo Docker Compose baseline to a reproducible .NET Aspire orchestration model.

This issue is Experiment 08B of the Application Modernization Lab.

The migration must preserve the validated application behavior and runtime contracts established by Experiment 08A while replacing Docker Compose orchestration with .NET Aspire AppHost orchestration.

The accepted Compose baseline is authoritative input. This issue must not redesign the application, modernize individual services, or silently weaken the validation contract.

## Accepted Source Baseline

Source issue:

- #14 — Validate and freeze the official AKS Store Demo Docker Compose baseline

Source pull request:

- #15 — accepted and merged Experiment 08A implementation

Authoritative baseline directory:

`experiments/08-aks-store-demo/01-compose-baseline/`

Pinned upstream AKS Store Demo commit:

`7ce10c5110d6a52d3517dfb6d7a7b7b2edf2e5a5`

The Experiment 08A baseline is frozen for this migration.

Do not modify files under:

`experiments/08-aks-store-demo/01-compose-baseline/`

Any discovered defect in the accepted baseline must be reported separately and must not be silently corrected as part of the Aspire migration.

## Target Directory

Implement Experiment 08B only under:

`experiments/08-aks-store-demo/02-compose-to-aspire/`

Expected structure:

```text
experiments/08-aks-store-demo/
├── README.md
├── 01-compose-baseline/
└── 02-compose-to-aspire/
    ├── README.md
    ├── src/
    │   └── AppHost/
    ├── scripts/
    └── docs/
```

The architect may propose a different internal structure when it is justified, documented, and approved before implementation.

## Required Core Service Scope

The Aspire model must represent all nine accepted non-AI core services:

1. `documentdb`
2. `rabbitmq`
3. `order-service`
4. `makeline-service`
5. `product-service`
6. `store-front`
7. `store-admin`
8. `virtual-customer`
9. `virtual-worker`

No required core service may be silently removed, replaced, combined, or mocked.

The migration must preserve the application-visible service identities and internal DNS expectations unless an equivalent Aspire-specific mapping is explicitly documented and approved.

## Optional AI Service

The upstream `ai-service` remains optional.

The primary PASS criteria must not require:

- Azure OpenAI credentials;
- OpenAI credentials;
- paid external AI APIs;
- an Azure subscription;
- external model availability.

The architect must determine how the optional AI service should be represented in Aspire without making it a dependency of the default core validation.

No real API key or external credential may be committed.

## Stage 1 — Aspire Architecture Research

Before implementation, dispatch a fresh architecture session.

The architect must inspect:

- the accepted Experiment 08A Compose baseline;
- its runtime contract;
- its validation scripts;
- its persistence classification;
- the application Dockerfiles and build contexts;
- the current repository conventions;
- the active Compose-to-Aspire migration methodology.

The architect must produce a reviewable migration design covering:

- Aspire solution and AppHost structure;
- required .NET SDK and Aspire versions;
- representation of each containerized service;
- local image builds versus existing container images;
- Dockerfile and build-context handling;
- service names and application-visible hostnames;
- internal endpoint references;
- environment-variable mapping;
- RabbitMQ resource representation;
- DocumentDB container representation;
- container arguments and startup behavior;
- health and readiness checks;
- startup ordering and dependency references;
- loopback-only host exposure;
- endpoint naming and port allocation;
- automated workload behavior;
- optional AI behavior;
- secret and configuration boundaries;
- persistence semantics;
- cleanup and reset behavior;
- validation strategy;
- migration fidelity criteria;
- known gaps between Docker Compose and Aspire orchestration;
- rollback and repository boundaries.

For every service, the report must identify:

| Field | Required analysis |
| --- | --- |
| Service identity | Compose name and proposed Aspire resource name |
| Runtime type | Container, executable, project, or external resource |
| Source | Dockerfile/build context or image |
| Dependencies | Required service references and startup relationships |
| Environment | Existing values and Aspire reference expressions |
| Ports | Container port, host exposure, and endpoint purpose |
| Health | Existing checks and proposed Aspire behavior |
| State | Stateless, in-memory, container-local, or persistent |
| Validation | Evidence required to prove migration fidelity |

The architecture report must distinguish:

1. accepted Experiment 08A behavior that must be preserved;
2. Aspire-specific adaptations that are required;
3. optional improvements that are not necessary for migration fidelity;
4. unresolved decisions requiring human approval.

Post the complete architecture report to this issue and stop before implementation.

Do not create implementation branches, commits, pull requests, or AppHost code before explicit Human Aspire Architecture Approval.

## Human Aspire Architecture Approval

The operator must explicitly approve:

- Aspire and .NET versions;
- AppHost project structure;
- representation of all nine required services;
- image-build strategy;
- resource naming;
- endpoint and port model;
- environment-variable and service-reference mapping;
- RabbitMQ representation;
- DocumentDB representation;
- optional AI treatment;
- workload-control strategy;
- persistence interpretation;
- validation plan;
- any deliberate deviation from the accepted Compose baseline.

Architecture approval does not authorize unrelated application refactoring or active skill modification.

## Migration Fidelity Requirements

The Aspire implementation must preserve the accepted functional behavior of Experiment 08A.

At minimum, it must preserve:

- all nine required core services;
- application-visible dependency relationships;
- RabbitMQ queue name and connection behavior;
- DocumentDB connection path, database, collection, and approved TLS behavior;
- product availability;
- unique current-run order submission;
- order publication to RabbitMQ;
- makeline consumption and processing;
- DocumentDB-backed order state;
- admin-visible order evidence;
- automated workload services;
- optional AI exclusion from default PASS criteria;
- loopback-only exposure of user-facing endpoints;
- internal-only backend services;
- deterministic cleanup and repeatability.

Aspire dashboard visibility is useful operational evidence, but dashboard status alone is not sufficient functional validation.

## Container and Build Requirements

The migration should use the accepted application source and Dockerfiles from Experiment 08A as immutable input.

The implementation must document:

- how each Docker build context is resolved;
- how Dockerfiles are referenced;
- whether images are built by Aspire or prebuilt separately;
- how the pinned source relationship is preserved;
- how resource names map to container DNS names;
- whether Aspire-generated container names affect application behavior;
- how rebuild and restart behavior differs from Docker Compose.

Do not copy and modify the accepted application source unless a separately approved compatibility change is required.

Any compatibility change must be:

- minimal;
- isolated to Experiment 08B;
- documented;
- justified;
- validated;
- approved before implementation.

## Runtime Safety

All host-exposed endpoints must bind to loopback.

Required user-facing endpoints include:

- `store-front`;
- `store-admin`.

Backend APIs, RabbitMQ protocol ports, RabbitMQ management, and DocumentDB must remain internal unless temporary loopback access is explicitly required by the approved validator.

Do not create:

- public endpoints;
- firewall rules;
- cloud load balancers;
- AKS resources;
- Azure resources;
- GCP resources;
- external ingress.

The Aspire dashboard must not be exposed publicly.

## Deterministic Workload Behavior

The migration must include:

- `virtual-customer`;
- `virtual-worker`.

The Aspire validation model must prevent automated traffic from being confused with current-run evidence.

Use the approved Experiment 08A approach or an explicitly equivalent Aspire adaptation:

- controlled rates;
- temporary pause or stop during deterministic evidence collection;
- unique validation identifiers;
- explicit separation between generated workload and validator-created orders.

The validator must not accept an old, seeded, or automatically generated order as current-run evidence.

## Functional Acceptance Criteria

The Aspire implementation must prove:

1. AppHost starts successfully.
2. All nine required core resources are represented.
3. Required containers build or resolve from the approved source.
4. Required dependencies become ready.
5. `store-front` is reachable through its documented loopback endpoint.
6. `store-admin` is reachable through its documented loopback endpoint.
7. Product data is available through the application workflow.
8. A unique current-run order can be submitted.
9. `order-service` accepts the order.
10. The order enters the expected RabbitMQ workflow.
11. `makeline-service` consumes or observes the order.
12. The resulting state is written to DocumentDB.
13. The current-run order is visible through the admin or makeline workflow.
14. Runtime evidence belongs to the Experiment 08B Aspire instance.
15. Cleanup removes only Experiment 08B runtime resources.
16. A fresh repeat run passes.

A resource-state check, Aspire dashboard status, generic page content, or stale application data is insufficient.

## RabbitMQ Validation

Validation must prove more than RabbitMQ resource startup.

It must confirm:

- expected Aspire resource identity;
- expected broker container;
- expected `orders` queue;
- application connectivity;
- order publication;
- order consumption or processing;
- no false PASS from an unrelated broker;
- functional recovery after the approved negative test.

## DocumentDB Validation

Validation must prove more than DocumentDB container startup.

It must confirm:

- expected Aspire resource identity;
- expected connection path;
- approved TLS behavior;
- expected database and collection;
- current-run order data;
- application-level visibility through makeline or admin APIs.

The accepted Experiment 08A persistence limitation must not be overstated or silently reclassified.

If Aspire changes lifecycle behavior, the exact difference must be measured and documented.

## Persistence Classification

The architect and developer must compare Aspire lifecycle behavior with the accepted Experiment 08A classification:

| Scenario | Experiment 08A classification |
| --- | --- |
| Restart `makeline-service` | PASS |
| Full Compose stop/start with existing DocumentDB container | EXPECTED FAILURE caused by duplicate upstream seed data |
| DocumentDB container deletion or recreation | Durable persistence not supported or claimed |
| Clean reset and fresh startup | PASS |

Experiment 08B must determine the corresponding Aspire behavior for:

- application service restart;
- DocumentDB restart;
- AppHost stop and start;
- container recreation;
- Aspire resource deletion;
- full cleanup;
- fresh startup.

Do not add a named volume or claim improved durability without separate approval and explicit validation.

## Negative Validation

Include at least one deterministic negative test.

Preferred scenario:

- make the Experiment 08B RabbitMQ resource unavailable;
- execute the native Aspire validation path;
- require a non-zero result tied to the RabbitMQ-dependent order workflow;
- restore RabbitMQ;
- refresh or restart dependent services when required;
- submit a fresh unique order;
- prove makeline and DocumentDB-backed recovery;
- leave the environment clean.

The negative test must prove functional failure and functional recovery, not only container or resource state.

## Native Validation Entry Point

Provide a deterministic validation entry point for Experiment 08B.

The validator must:

- return zero only when the Aspire migration satisfies the approved contract;
- return non-zero when a required service or functional path is unavailable;
- use a fresh validation identifier;
- reject stale Experiment 08B resources;
- verify the expected resource set;
- verify loopback endpoint exposure;
- validate the product and order workflows;
- validate RabbitMQ and DocumentDB evidence;
- record concise local evidence;
- clean up reliably;
- support a fresh repeat run.

Do not depend exclusively on manual Aspire dashboard inspection.

## Developer Validation

Developer validation must include:

- repository preflight;
- accepted baseline integrity check;
- .NET and Aspire version check;
- AppHost build;
- Aspire startup;
- expected resource inventory;
- container/image build validation;
- health and readiness;
- loopback endpoint validation;
- product workflow;
- unique order workflow;
- RabbitMQ evidence;
- makeline evidence;
- DocumentDB evidence;
- persistence classification;
- negative validation;
- functional recovery;
- cleanup;
- fresh repeat run;
- Git hygiene;
- secret scan.

Record concise evidence under Experiment 08B.

Do not commit raw logs, tokens, cookies, local environment files, database dumps, or machine-specific paths.

## Independent Tester Validation

After developer validation, dispatch a fresh independent tester session.

The tester must:

- validate the exact PR head;
- begin from the documented Experiment 08B baseline;
- verify that Experiment 08A remains unchanged;
- build and start the Aspire AppHost independently;
- verify all nine required resources;
- use a fresh current-run identifier;
- exercise the functional workflow;
- inspect RabbitMQ evidence independently;
- inspect DocumentDB-backed evidence independently;
- execute the negative test;
- verify functional recovery;
- verify cleanup and repeatability;
- check repository hygiene and secret boundaries;
- report any deviation from the approved architecture.

The tester must not rely solely on developer-generated evidence.

## Required Deliverables

At minimum, deliver:

- Experiment 08B README;
- .NET Aspire solution and AppHost project;
- version and prerequisite documentation;
- service-to-resource mapping;
- Compose-to-Aspire migration assessment;
- runtime-contract mapping;
- endpoint and dependency documentation;
- optional AI treatment;
- persistence comparison;
- startup script or documented entry point;
- native positive validation;
- native negative validation;
- cleanup and full-reset procedure;
- developer validation report;
- independent tester report;
- final migration assessment;
- known limitations;
- rollback instructions.

## Repository and Workflow Boundaries

Do not:

- modify the accepted Experiment 08A baseline;
- modify completed experiments;
- deploy to AKS;
- create Azure or GCP resources;
- introduce Kubernetes manifests as the Aspire implementation;
- refactor application services without separate approval;
- upgrade application languages or frameworks;
- introduce production-hardening work unrelated to migration fidelity;
- require external AI credentials for PASS;
- commit secrets or local runtime artifacts;
- modify OpenClaw runtime configuration;
- modify DevClaw package configuration;
- enable heartbeat;
- enable parallel workflow execution;
- enable auto-merge;
- merge or close without explicit human approval.

The active Compose-to-Aspire migration skill may be used as methodology, but it must not be modified in this issue unless a separate Skill Workshop proposal is explicitly approved.

## Out of Scope

- AKS deployment;
- Kubernetes migration;
- Azure infrastructure;
- GCP infrastructure;
- CI/CD implementation;
- production observability platform integration;
- OpenTelemetry enhancement beyond what is already required by the application;
- application feature development;
- language or framework upgrades;
- optional external AI validation;
- durable storage redesign;
- active skill modification;
- changes to Experiment 08A.

## Completion Criteria

This issue is complete only when:

- the architecture report is approved;
- the Aspire implementation represents all nine core services;
- the accepted Experiment 08A baseline remains unchanged;
- positive validation passes;
- negative validation passes;
- functional RabbitMQ recovery passes;
- DocumentDB behavior is accurately classified;
- cleanup and repeatability pass;
- developer validation is complete;
- independent tester validation is complete;
- the pull request receives explicit human approval;
- the pull request is manually merged;
- the final issue closeout is posted;
- the issue is manually closed as completed.



## Current Issue #16 Comments

### Comment by DimitryZH at 2026-07-31T18:35:28Z

## Human Architecture Dispatch Approval

Approved to begin Stage 1 — Aspire Architecture Research.

Dispatch exactly one fresh senior architect session for Experiment 08B.

The architect must use the accepted Experiment 08A baseline as immutable input, inspect the active Compose-to-Aspire migration methodology in read-only mode, produce the complete migration architecture report requested by this issue, post it here, and stop for Human Aspire Architecture Approval.

Do not create an implementation branch, commits, pull request, AppHost code, application changes, or skill changes during this stage.

### Comment by devclaw-agent-devbox[bot] at 2026-07-31T19:02:39Z

🏗️ **ARCHITECT**: ## Stage 1 Aspire Architecture Research Report

Status: **ready for Human Aspire Architecture Approval**.

No repository files were modified. No implementation branch, commit, pull request, AppHost code, cloud resource, skill change, developer dispatch, tester dispatch, merge, or issue close was performed. The accepted Experiment 08A baseline remains immutable input for this design.

### Scope and Source Baseline

Authoritative input:

- Accepted baseline: `experiments/08-aks-store-demo/01-compose-baseline/`
- Target directory: `experiments/08-aks-store-demo/02-compose-to-aspire/`
- Accepted upstream source commit: `Azure-Samples/aks-store-demo` commit `7ce10c5110d6a52d3517dfb6d7a7b7b2edf2e5a5`
- Accepted baseline repository commit observed for this research: `38ab6b49868c8b4e490e2464d749f8b0fa92e905`
- Accepted PR: #15, merged after human review and targeted tester revalidation

Experiment 08B should preserve the accepted Compose behavior and runtime contracts, not redesign the application or modernize service internals. Any discovered defect in 08A should be reported separately and must not be corrected silently in the Aspire migration.

### Recommended Versions

Recommended implementation baseline, subject to approval:

- .NET SDK: latest installed .NET 10 SDK patch available to the developer environment at implementation time.
- Aspire: current stable Aspire AppHost package/tooling compatible with that SDK.
- Docker runtime: local Docker engine with BuildKit support for the existing Dockerfiles.

Rationale: Experiment 08B is a new Aspire migration and should use a current supported .NET/Aspire toolchain rather than older experiment-specific versions. The developer must document exact versions in the 08B README and validation report. If the approved SDK/Aspire version is unavailable, the developer must stop for human direction instead of downgrading silently.

### Compose Service Inventory and Responsibilities

| Service | Responsibility | Accepted source | Host exposure | State classification |
| --- | --- | --- | --- | --- |
| `documentdb` | Local DocumentDB-compatible MongoDB endpoint for orders | `ghcr.io/documentdb/documentdb/documentdb-local:pg17-0.112.0` | Internal only | Container-local runtime state; no durable persistence claim |
| `rabbitmq` | AMQP broker and `orders` queue | `rabbitmq:4.3.2-management-alpine` | Internal only | Container-local broker state |
| `order-service` | Accepts orders and publishes to RabbitMQ | Docker build `src/order-service` | Internal only | Stateless publisher |
| `makeline-service` | Consumes orders and writes order records to DocumentDB | Docker build `src/makeline-service` | Internal only | Depends on DocumentDB state |
| `product-service` | Seeded product catalog and optional AI proxy | Docker build `src/product-service` | Internal only | In-memory seeded catalog |
| `store-front` | Customer browse, cart, checkout UI | Docker build `src/store-front` | `127.0.0.1:8080` | Browser cart in localStorage; backend-driven checkout |
| `store-admin` | Admin product and order UI | Docker build `src/store-admin` | `127.0.0.1:8081` | Reads backend product and order state |
| `virtual-customer` | Low-rate background order generator | Docker build `src/virtual-customer` | None | Runtime workload only |
| `virtual-worker` | Low-rate background pending-order processor | Docker build `src/virtual-worker` | None | Runtime workload only |
| `ai-service` | Optional text/image AI backend | Docker build `src/ai-service` | Optional loopback only if enabled | Optional; excluded from default PASS criteria |

The nine non-AI services are required core resources. No required service should be removed, mocked, combined, or replaced.

### Dependencies and Startup Relationships

Accepted startup relationships to preserve or strengthen through Aspire references and readiness checks:

- `order-service` depends on healthy RabbitMQ.
- `makeline-service` depends on healthy RabbitMQ and healthy DocumentDB.
- `store-front` depends on `product-service` and `order-service`.
- `store-admin` depends on `product-service` and `makeline-service`.
- `virtual-customer` depends on healthy `order-service`.
- `virtual-worker` depends on healthy `makeline-service`.
- `product-service` has no default startup dependency on `ai-service`, even though `AI_SERVICE_URL` remains configured.
- `ai-service` remains optional and has no default dependency.

Recommended Aspire behavior:

- Use resource references and `WaitFor`-style startup sequencing where available.
- Do not treat process/container running state as application readiness.
- Keep the native validator responsible for final readiness by exercising health endpoints and downstream workflows.
- If a resource becomes ready according to Aspire but fails the product/order/RabbitMQ/DocumentDB workflow, validation must fail.

### Ports, Networking, Environment, Redis, and Health Behavior

Experiment 08A has no Redis component. Redis should not be introduced in 08B.

Accepted endpoint model:

- `store-front`: container port `8080`, host endpoint `http://127.0.0.1:8080`.
- `store-admin`: container port `8081`, host endpoint `http://127.0.0.1:8081`.
- `order-service`: internal port `3000`.
- `makeline-service`: internal port `3001`.
- `product-service`: internal port `3002`.
- `rabbitmq`: internal AMQP `5672`; management `15672` should remain internal unless validation explicitly needs temporary loopback access.
- `documentdb`: internal `10260`.
- `virtual-customer` and `virtual-worker`: no exposed ports.
- `ai-service`: optional `5001`, excluded from default PASS; if enabled, bind loopback only.

Accepted environment values to preserve:

- `rabbitmq`: `RABBITMQ_DEFAULT_USER=username`, `RABBITMQ_DEFAULT_PASS=password`.
- `order-service`: `ORDER_QUEUE_HOSTNAME=rabbitmq`, `ORDER_QUEUE_PORT=5672`, `ORDER_QUEUE_USERNAME=username`, `ORDER_QUEUE_PASSWORD=password`, `ORDER_QUEUE_NAME=orders`.
- `makeline-service`: `ORDER_QUEUE_URI=amqp://rabbitmq:5672`, `ORDER_QUEUE_USERNAME=username`, `ORDER_QUEUE_PASSWORD=password`, `ORDER_QUEUE_NAME=orders`, `ORDER_DB_URI=mongodb://documentdb:10260/?tls=true&tlsAllowInvalidCertificates=true`, `ORDER_DB_NAME=orderdb`, `ORDER_DB_COLLECTION_NAME=orders`, `ORDER_DB_USERNAME=username`, `ORDER_DB_PASSWORD=password`.
- `product-service`: `AI_SERVICE_URL=http://ai-service:5001/`.
- `virtual-customer`: `ORDER_SERVICE_URL=http://order-service:3000/`, `ORDERS_PER_HOUR=1`.
- `virtual-worker`: `MAKELINE_SERVICE_URL=http://makeline-service:3001`, `ORDERS_PER_HOUR=1`.
- `ai-service`: placeholders only; no real external AI credential in source or committed evidence.

Health behavior to map:

- `documentdb`: Compose uses an OpenSSL TLS connection check against `10260`. Aspire should model startup ordering with a container resource and validator-level TLS readiness. If a custom AppHost health check can verify TLS without exposing DocumentDB to the host, use it; otherwise document that native validation performs the authoritative DocumentDB readiness check through the application workflow.
- `rabbitmq`: Compose uses `rabbitmqctl status`. Aspire should model RabbitMQ as a container and validate readiness through broker health plus `orders` queue evidence and application publish/consume behavior.
- `order-service`: HTTP `/health` on `3000`.
- `makeline-service`: HTTP `/health` on `3001`; functional readiness also requires DocumentDB connectivity.
- `product-service`: product readiness is validated by `/health` and product data through UI proxies; no Compose container healthcheck exists in the accepted baseline.
- `store-front`: HTTP `/health` on `8080` plus product and order proxy workflows.
- `store-admin`: HTTP `/health` on `8081` plus product and makeline/order proxy workflows.
- `virtual-customer` and `virtual-worker`: no HTTP health endpoint; validate identity, running state, configured rates, and effect on workload only after deterministic evidence collection.
- `ai-service`: optional HTTP `/health` when enabled; excluded from default validation.

### .NET and Non-.NET Classification

The application services are polyglot and should be treated as containerized services, not .NET projects:

- Node.js: `order-service`, `store-front`, `store-admin` build stages.
- Go: `makeline-service`.
- Rust: `product-service`, `virtual-customer`, `virtual-worker`.
- Python: optional `ai-service`.
- Third-party/container infrastructure: `documentdb`, `rabbitmq`.
- .NET: AppHost only, plus optional validation helper only if approved. No application service is an in-scope .NET project.

### Project References Versus Container Resources

Recommendation: represent every required service as an Aspire container resource.

- Use **container resources from Dockerfiles** for `order-service`, `makeline-service`, `product-service`, `store-front`, `store-admin`, `virtual-customer`, `virtual-worker`, and optional `ai-service`.
- Use **container resources from pinned images** for `documentdb` and `rabbitmq`.
- Use **no Aspire project references** for the application services, because there are no buildable local .NET service projects and source rewrites are out of scope.
- Use **no external resources** for required core services, because the default PASS criteria must be local and reproducible.

ServiceDefaults is not appropriate for the application services. It requires source-level .NET service integration, and no service source change is approved or needed. The AppHost may use normal Aspire hosting packages, but 08B should not add ServiceDefaults to non-.NET containers or patch application source to fit ServiceDefaults.

### Proposed Aspire Solution and AppHost Structure

Recommended target structure:

```text
experiments/08-aks-store-demo/02-compose-to-aspire/
├── README.md
├── src/
│   └── AppHost/
│       ├── AppHost.csproj
│       └── Program.cs
├── scripts/
│   ├── start-aspire.sh
│   ├── validate-aspire.sh
│   ├── validate-negative.sh
│   └── cleanup-aspire.sh
└── docs/
    ├── resource-mapping.md
    ├── runtime-contract-mapping.md
    ├── persistence-comparison.md
    ├── validation-plan.md
    └── migration-assessment.md
```

A solution file is useful for repeatable build commands. The solution should include the AppHost only unless a separately approved validator project is added. The AppHost should reference Dockerfile build contexts outside 08B using read-only relative paths into `../01-compose-baseline/` from the experiment root, or `../../../01-compose-baseline/...` from the AppHost project directory. Do not copy or modify the accepted application source.

Recommended AppHost resource names should match Compose service names exactly:

- `documentdb`
- `rabbitmq`
- `order-service`
- `makeline-service`
- `product-service`
- `store-front`
- `store-admin`
- `virtual-customer`
- `virtual-worker`
- optional `ai-service`

If Aspire does not allow hyphenated resource names or produces different DNS aliases for containers, implementation must document the exact mapping and prove that application-visible hostnames still resolve as required.

### Resource Mapping by Service

| Service | Aspire resource | Runtime type | Source | Dependencies | Environment mapping | Ports/endpoints | Health/readiness | State | Validation evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `documentdb` | `documentdb` | Container image | `ghcr.io/documentdb/documentdb/documentdb-local:pg17-0.112.0` | None | Command args `--username username --password password` | internal `10260` | TLS readiness and application order persistence; no host exposure by default | Container-local state | Expected resource identity, TLS path, DB `orderdb`, collection `orders`, current-run order data |
| `rabbitmq` | `rabbitmq` | Container image | `rabbitmq:4.3.2-management-alpine` | None | Demo credentials | internal `5672`, internal `15672` | Broker ready, `orders` queue, publish/consume workflow | Container-local state | Expected resource identity, queue exists, order publication and recovery after negative test |
| `order-service` | `order-service` | Dockerfile container | `01-compose-baseline/src/order-service` | `rabbitmq` | Preserve queue host, port, credentials, name | internal `3000` | HTTP `/health`; order POST workflow | Stateless | Accepts unique current-run order and publishes to RabbitMQ |
| `makeline-service` | `makeline-service` | Dockerfile container | `01-compose-baseline/src/makeline-service` | `rabbitmq`, `documentdb` | Preserve AMQP URI and DocumentDB URI/database/collection/credentials | internal `3001` | HTTP `/health`; DB-backed order API | Uses DocumentDB | Consumes current-run order and writes/fetches it through admin/makeline API |
| `product-service` | `product-service` | Dockerfile container | `01-compose-baseline/src/product-service` | Optional AI only for AI routes | Preserve `AI_SERVICE_URL=http://ai-service:5001/` | internal `3002` | `/health` and product data workflow | In-memory seeded catalog | Product data available through storefront/admin proxies; AI unavailable classified as optional |
| `store-front` | `store-front` | Dockerfile container | `01-compose-baseline/src/store-front` | `product-service`, `order-service` | Nginx config already uses internal service names | loopback `8080` to target `8080` | `/health`, product proxy, checkout proxy | Browser cart localStorage | Browse products, create cart/order, submit unique checkout order |
| `store-admin` | `store-admin` | Dockerfile container | `01-compose-baseline/src/store-admin` | `product-service`, `makeline-service`, `order-service` | Nginx config already uses internal service names | loopback `8081` to target `8081` | `/health`, product proxy, makeline/order proxy | Reads backend state | Current-run order visible through admin/makeline workflow |
| `virtual-customer` | `virtual-customer` | Dockerfile container | `01-compose-baseline/src/virtual-customer` | `order-service` | `ORDER_SERVICE_URL=http://order-service:3000/`, `ORDERS_PER_HOUR=1` | none | Running state and controlled workload behavior | Runtime workload | Present in resource inventory; paused or controlled during deterministic evidence collection |
| `virtual-worker` | `virtual-worker` | Dockerfile container | `01-compose-baseline/src/virtual-worker` | `makeline-service` | `MAKELINE_SERVICE_URL=http://makeline-service:3001`, `ORDERS_PER_HOUR=1` | none | Running state and controlled workload behavior | Runtime workload | Present in resource inventory; restored after deterministic order evidence |
| `ai-service` | `ai-service` | Optional Dockerfile container | `01-compose-baseline/src/ai-service` | None | Placeholder-only AI configuration | optional loopback `5001` if enabled | `/health` only when enabled | Optional external API client | Excluded from default PASS; optional manual profile only |

### Image and Build Strategy

Recommended strategy:

- Preserve existing Dockerfiles and build contexts from 08A.
- Do not prebuild or retag application images unless validation proves Aspire Dockerfile builds are not sufficient.
- Use Dockerfile-based container resources so the AppHost builds from the accepted pinned source snapshot.
- Use pinned image references for `documentdb` and `rabbitmq`.
- Keep build arguments at Dockerfile defaults unless a version label is explicitly approved.
- Record exact image/build behavior in `docs/resource-mapping.md` and developer validation evidence.

The AppHost must document how relative paths resolve. It must not copy 08A source into 08B and modify it.

### Service Discovery and Configuration Mapping

Preferred mapping: preserve service names as DNS names inside the Aspire-managed container network. The existing Nginx and service configurations refer to `order-service`, `product-service`, `makeline-service`, `rabbitmq`, `documentdb`, and `ai-service` by name. Migration fidelity is strongest if Aspire resource names and network aliases match those names.

If Aspire-generated container names differ, that is acceptable only if application-visible DNS aliases and environment variables still resolve exactly as the accepted runtime requires. Validation must prove there is no false PASS from a Compose container or unrelated runtime resource.

Do not replace application configuration with host-loopback URLs for internal dependencies. Internal service references should remain network-local container addresses.

### Frontend Endpoint Behavior

`store-front` must remain the default customer entry point at the documented loopback endpoint. It must preserve:

- `/health` returning the Nginx health JSON.
- `/api/products` proxy to `product-service:3002`.
- `/api/orders` proxy to `order-service:3000`.
- browser cart behavior through localStorage.
- checkout submission to the backend order workflow.

`store-admin` must remain the admin entry point at the documented loopback endpoint. It must preserve:

- `/health` returning the Nginx health JSON.
- product proxy behavior through `product-service:3002`.
- makeline order APIs through `makeline-service:3001`.
- order submission proxy behavior through `order-service:3000`.
- optional AI proxy paths through product-service, with default AI unavailable classified rather than treated as migration failure.

### Optional Load Generator Handling

Both workload services must be present in the default Aspire topology with `ORDERS_PER_HOUR=1` to match the accepted Compose adaptation. Validation should control them during deterministic evidence collection:

- pause or stop `virtual-customer` and `virtual-worker` while submitting a validator-created unique order;
- use a fresh validation identifier such as `aml08b-<timestamp>-<nonce>`;
- find the resulting makeline-assigned `orderId` by the unique `customerId` marker;
- restore workload services after deterministic evidence is captured;
- verify the workload resources are represented and configured, but do not let their random orders satisfy current-run evidence.

If Aspire cannot pause individual container resources reliably, the developer should implement a documented validation phase that starts core services first, captures deterministic evidence, then starts workload resources. This is an Aspire-specific adaptation requiring approval because the default topology must still include both workload services.

### Aspire Dashboard and Observability Expectations

The Aspire dashboard should show all required resources, endpoints, logs, and health/readiness state for the AppHost run. It is useful operational evidence, especially for resource inventory and startup diagnostics.

Dashboard status is not sufficient acceptance evidence. Functional validation must still prove storefront browsing, checkout, RabbitMQ publication, makeline processing, DocumentDB-backed order visibility, negative failure, recovery, cleanup, and repeatability.

The dashboard must remain local only and must not be exposed publicly.

### Preservation of Functional Behavior

08B validation must prove these accepted behaviors are preserved:

- product browsing returns seeded product data through the storefront/admin path;
- storefront cart and checkout flow can submit a unique current-run order;
- order-service accepts the order and uses the expected RabbitMQ connection contract;
- RabbitMQ contains and uses queue `orders` for the application workflow;
- makeline consumes the order and writes current-run data to DocumentDB;
- admin or makeline APIs expose the current-run order from DocumentDB-backed state;
- optional AI is excluded from default PASS while normal product/order workflows continue;
- workload services exist without contaminating deterministic evidence;
- cleanup and fresh repeat execution pass.

There is no Redis-backed state in Experiment 08A. The preserved stateful component is DocumentDB; cart state remains browser-local.

### Persistence Classification for Aspire

Do not add named volumes by default. The accepted 08A behavior is container-local DocumentDB state with no durable persistence claim.

08B must measure and document corresponding Aspire lifecycle behavior:

| Scenario | Required 08B classification work |
| --- | --- |
| Restart `makeline-service` | Current-run order should remain visible while DocumentDB container is unchanged. |
| Restart `documentdb` | Measure exact behavior; do not assume it matches Compose stop/start. |
| AppHost stop/start with existing containers | Measure whether DocumentDB seed duplicate failure appears or whether Aspire recreates resources differently. |
| Container recreation/deletion | Durable persistence must remain not supported unless separate approval adds storage. |
| Aspire cleanup/reset | Must remove only 08B resources; full reset may remove 08B container-local state. |
| Fresh startup | Must pass positive validation with a fresh unique order. |

If Aspire lifecycle behavior differs from Compose, the migration assessment must document the difference without reclassifying durability as improved.

### Native Validation Strategy

Required scripts should be implemented under 08B, with names documented in README:

- `scripts/start-aspire.sh`: build/start the AppHost with the approved SDK/Aspire version.
- `scripts/validate-aspire.sh`: native positive validator.
- `scripts/validate-negative.sh`: native negative validator.
- `scripts/cleanup-aspire.sh`: stop/remove only 08B resources; full reset option removes 08B runtime state and local evidence.

Positive validation must include:

- repository preflight and clean target-scope assumptions;
- 08A baseline integrity check through `upstream-source.sha256` without modifying 08A;
- .NET SDK and Aspire version checks;
- AppHost build;
- AppHost startup and expected resource inventory;
- confirmation that all runtime resources belong to the current 08B Aspire run;
- image/build validation for Dockerfile-backed services;
- loopback-only exposure for `store-front` and `store-admin`;
- internal-only backend services;
- health/readiness polling plus functional readiness;
- product workflow through UI proxies;
- unique current-run order workflow;
- RabbitMQ `orders` queue and publish/consume evidence;
- DocumentDB path/database/collection/current-run order evidence;
- workload control and restoration;
- persistence classification;
- cleanup;
- fresh repeat run;
- Git hygiene and secret scan;
- concise local evidence under ignored 08B runtime output.

Negative validation should use RabbitMQ unavailability by default:

1. Start or confirm the 08B Aspire environment.
2. Stop only the current-run `rabbitmq` resource.
3. Run the native validation path or a targeted validation mode that must fail non-zero on the RabbitMQ-dependent order workflow.
4. Require the failure to identify RabbitMQ/order publication or queue connectivity.
5. Restore RabbitMQ.
6. Refresh/restart `order-service` and `makeline-service` if their connections do not recover automatically.
7. Submit a fresh unique order.
8. Prove makeline and DocumentDB-backed recovery.
9. Clean up.

Additional recommended negative tests:

- With only the 08A Compose baseline running, the 08B validator must fail because it cannot find the current 08B Aspire resource identity.
- With one required Aspire resource missing, validation must fail non-zero.
- With `127.0.0.1:8080` or `127.0.0.1:8081` already occupied, startup or validation must fail with documented port-conflict behavior.
- With stale 08B runtime resources from an earlier run, validation must fail and instruct cleanup rather than using stale evidence.

### Deterministic Equivalence Criteria

A PASS requires evidence from the current 08B run, not generic health or stale data. The validator should require:

- exact expected resource set;
- shared current AppHost/run identity for selected resources;
- expected resource names or approved aliases;
- fresh validation identifier in the order payload;
- RabbitMQ evidence from the current broker;
- DocumentDB-backed current-run order evidence;
- repeat run after cleanup.

Do not validate by image digest alone, dashboard state alone, endpoint reachability alone, or product page content alone.

### Required Source Changes

Preferred source changes: **none** to the accepted application source and none to 08A.

Expected implementation changes are limited to new 08B files:

- Aspire solution/AppHost project;
- README and docs;
- startup, validation, and cleanup scripts;
- local ignored evidence directory under 08B if needed;
- optional AppHost-only configuration placeholders for AI enablement.

Any application source compatibility change must stop for human approval before implementation. If approved later, it must be minimal, isolated to 08B, justified, validated, and documented.

### Cleanup and Reset

Cleanup must target only 08B resources. It must not stop or remove 08A Compose resources unless the user explicitly runs the 08A cleanup.

Recommended cleanup behavior:

- stop the AppHost process cleanly;
- remove containers/resources associated with the current 08B AppHost/run identity;
- leave unrelated containers, volumes, networks, and processes untouched;
- support a full reset mode that removes only 08B runtime state and local evidence;
- verify no 08B containers, bound ports, or unexpected resources remain;
- document manual cleanup fallback commands.

### Rollback Approach

Repository rollback before merge is removal of the 08B target directory changes. Runtime rollback is execution of the 08B cleanup script, followed by manual removal of only clearly identified 08B resources if cleanup fails.

Because 08A remains immutable, rollback does not require modifying the accepted Compose baseline. If implementation later discovers that 08A must change, stop and file/report that separately.

### Known Gaps and Risks

- Aspire container names may differ from Compose container names; application-visible DNS aliases must be proven.
- Aspire endpoint APIs may not bind fixed ports exactly like Compose. Loopback-only behavior and port conflicts must be validated explicitly.
- Dockerfile builds may use current upstream base images and package registries; build reproducibility depends on those sources remaining available.
- `documentdb` has accepted container-local persistence limitations and seed-data stop/start behavior; Aspire lifecycle may differ and must be measured.
- `product-service` has in-memory product state; product CRUD durability must not be claimed.
- Storefront cart state is browser-local and outside server persistence.
- Automated workload services can create unrelated orders; validation must isolate current-run evidence.
- Optional AI routes may fail in the default profile; that is accepted only when product/order workflows pass and the behavior is documented.
- RabbitMQ management access may be useful for validation but should remain internal unless a temporary loopback validation endpoint is approved.
- AppHost health/resource state is not enough to prove migration fidelity.

### Decisions Requiring Human Approval

Please approve or revise these before implementation starts:

1. Use latest available .NET 10 SDK patch and compatible stable Aspire package/tooling, with exact versions documented by the developer.
2. Create the proposed 08B structure under `experiments/08-aks-store-demo/02-compose-to-aspire/`.
3. Represent all nine required services as Aspire container resources; use no application project references.
4. Use generic container resources for `documentdb` and `rabbitmq` to preserve exact accepted images and behavior.
5. Build application containers from the accepted 08A Dockerfiles and build contexts by relative read-only references; do not copy or modify application source.
6. Preserve service/resource names matching Compose service names, or require explicit documented aliases if Aspire imposes constraints.
7. Preserve `store-front` and `store-admin` loopback endpoints on ports `8080` and `8081` if Aspire supports that safely; otherwise stop for approval of the exact endpoint adaptation.
8. Keep all backend endpoints internal by default, including RabbitMQ management and DocumentDB.
9. Exclude `ai-service` from default PASS and represent it only as optional, placeholder-configured behavior.
10. Keep workload services in the topology with rate `1`, while allowing validation to pause/control them for deterministic evidence.
11. Do not add named volumes or durable persistence without separate approval.
12. Use RabbitMQ-unavailable negative validation as the primary negative test.
13. Treat ServiceDefaults as not applicable to the non-.NET application containers.
14. Require developer validation, independent tester validation, human PR approval, manual merge, and final issue closeout before issue completion.
15. Include a genuine co-authorship attribution constraint in implementation planning: at least one meaningful Aspire migration implementation commit should include a valid `Co-authored-by: DimitryZH <verified GitHub-linked noreply email>` trailer. The implementer must not invent the email or create artificial commits. If that exact approach is technically unsuitable, use another official GitHub-supported method that preserves legitimate co-authorship and attribution, or stop for human direction. The selected approach should be documented and should survive the final pull request merge.

### Acceptance Criteria for Future Developer

- Work starts only after Human Aspire Architecture Approval.
- Changes stay inside `experiments/08-aks-store-demo/02-compose-to-aspire/` unless separately approved.
- 08A baseline files remain unchanged.
- AppHost builds with documented .NET/Aspire versions.
- All nine required core resources are represented.
- Dockerfile-backed services build from the accepted 08A source snapshot.
- `documentdb` and `rabbitmq` use accepted pinned images.
- Internal DNS/service-reference behavior preserves application-visible names or approved aliases.
- Storefront and admin are reachable only through loopback endpoints.
- Backend endpoints remain internal unless an approved validation exception is documented.
- Product workflow, unique order submission, RabbitMQ queue behavior, makeline consumption, DocumentDB-backed order visibility, and admin evidence pass.
- Workload services are present and do not contaminate deterministic evidence.
- Persistence behavior is measured and compared with 08A without overstating durability.
- Native positive and negative validators return correct exit codes.
- RabbitMQ negative recovery proves a fresh unique order after restoration.
- Cleanup removes only 08B resources and a fresh repeat run passes.
- No secrets, raw logs, local environment files, database dumps, or machine-specific artifacts are committed.
- Co-authorship attribution is handled through a genuine, verified GitHub-supported method and preserved through merge.

### Acceptance Criteria for Future Tester

- Validate the exact PR head after developer work.
- Verify 08A remains unchanged.
- Independently build and start the AppHost.
- Verify all nine required resources and current-run Aspire identity.
- Use a fresh validation identifier and exercise the functional workflow independently.
- Inspect RabbitMQ evidence for the expected `orders` queue and application publish/consume behavior.
- Inspect DocumentDB-backed evidence for the current-run order.
- Execute the negative test and verify functional recovery.
- Verify loopback-only UI exposure and internal backend behavior.
- Verify cleanup, full reset behavior, and fresh repeatability.
- Check repository hygiene and secret boundaries.
- Report any deviation from the approved architecture before human merge.

### Stage 1 Result

The recommended migration design is an all-container Aspire AppHost that preserves the accepted Compose runtime contracts, uses the 08A Dockerfiles/images as immutable input, keeps UI exposure loopback-only, leaves backends internal, excludes optional AI from default PASS, controls workload during deterministic validation, preserves the accepted DocumentDB persistence limitation, and relies on functional positive/negative validation rather than dashboard state alone.

This report is ready for Human Aspire Architecture Approval. Implementation should not begin until the approval decisions above are recorded.

### Comment by DimitryZH at 2026-07-31T19:34:39Z

## Human Aspire Architecture Approval

The Stage 1 Aspire architecture is approved with the following binding revisions.

1. Before implementation begins, the developer must determine and pin exact versions for:

   - .NET SDK;
   - Aspire AppHost package;
   - any required Aspire workload, CLI, or related tooling.

   The exact versions must be recorded in `global.json`, the AppHost project file, the Experiment 08B README, and developer validation evidence.

   Floating references such as “latest available” or “current stable” are not accepted as the reproducible implementation baseline.

2. Architecture decision 15 concerning mandatory `Co-authored-by` attribution is rejected and removed from scope.

   Do not add artificial attribution requirements or commits created for contribution counting. Git authorship and co-authorship must reflect genuine work performed by the named contributor.

3. The optional `ai-service` must be disabled or absent from the default runtime topology and enabled only through an explicit opt-in configuration. Default validation must require no external AI credentials.

4. Preserve loopback-only endpoints for `store-front` and `store-admin`. If the approved fixed ports or loopback binding cannot be implemented safely with the pinned Aspire version, stop for human approval rather than silently changing the endpoint model.

All other architecture decisions are approved, including:

- immutable use of the accepted Experiment 08A baseline;
- all nine required services represented as Aspire container resources;
- generic pinned-image resources for RabbitMQ and DocumentDB;
- Dockerfile builds from read-only Experiment 08A source;
- internal-only backend services;
- controlled workload services;
- no named volume or stronger persistence claim;
- RabbitMQ functional negative and recovery validation;
- native positive validation, cleanup, repeatability, developer validation, and independent tester validation.

Implementation may proceed only under:

`experiments/08-aks-store-demo/02-compose-to-aspire/`

Do not modify Experiment 08A, application source, the active skill, cloud infrastructure, or unrelated repository content.

### Comment by DimitryZH at 2026-07-31T19:35:16Z

## Human Implementation Approval

Approved to begin the Experiment 08B implementation stage under the binding Human Aspire Architecture Approval.

Dispatch exactly one fresh senior developer session.

The developer must:

- determine and pin exact .NET SDK and Aspire versions before implementation;
- implement only under `experiments/08-aks-store-demo/02-compose-to-aspire/`;
- keep Experiment 08A and application source unchanged;
- implement all nine required services as Aspire container resources;
- add the approved positive, negative, recovery, cleanup, persistence, and repeatability validation;
- create a draft pull request;
- post developer validation evidence to issue #16;
- stop for human review before tester dispatch.

Do not modify the active skill, create cloud resources, merge the pull request, close the issue, or dispatch a tester automatically.

### Comment by devclaw-agent-devbox[bot] at 2026-07-31T20:47:00Z

🔧 **DEVELOPER**: ## Developer recovery blocked

I verified the supplied authoritative context packet hashes before the environment stopped allowing local reads:

- Markdown SHA-256 matched: `3f08b6540ce310b078332cb66b1ebd7bb72764b0fafad3464663e1c5e12dc384`
- JSON SHA-256 matched: `331becf5f860937dd0deb423dae0bac45d951604814188f3cfcf75cb2107d46d`

I was able to read only the beginning of the Markdown packet. After that, every normal filesystem command failed before execution with:

```text
bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
```

Attempts to rerun required read-only inspection with escalation were rejected by the environment policy. Because I cannot read the full authoritative packet, inspect the repo checkout, verify branches/toolchain, or run validation, I stopped before repository changes. No branch, files, commits, PR, tester dispatch, merge, or issue closure were performed.



## Accepted Baseline Issue #14

Title: Validate and freeze the official AKS Store Demo Docker Compose baseline
State: closed
Labels: Done
URL: https://github.com/DimitryZH/application-modernization-lab/issues/14

### Body


## Objective

Validate, freeze, and document a reproducible Docker Compose baseline for the full core AKS Store Demo application.

This is Experiment 08A of the Application Modernization Lab.

The official upstream Docker Compose implementation already exists. This issue does not recreate it from scratch. Instead, it must:

- pin an exact upstream source commit;
- verify that the official Compose deployment builds and runs;
- define the required service scope;
- document runtime contracts and known limitations;
- validate a meaningful end-to-end order workflow;
- establish deterministic validation, negative testing, persistence semantics, cleanup, and repeatability;
- produce an accepted baseline that becomes the authoritative runtime input for a later Docker Compose to .NET Aspire migration.

The later Aspire migration will be tracked in a separate issue.

This issue must not implement .NET Aspire and must not modify the active `compose-to-aspire-migration` skill.

## Source and Target

Upstream repository:

`https://github.com/Azure-Samples/aks-store-demo`

Target repository:

`DimitryZH/application-modernization-lab`

Experiment root:

`experiments/08-aks-store-demo/`

Target baseline directory:

`experiments/08-aks-store-demo/01-compose-baseline/`

Reserved future Aspire directory:

`experiments/08-aks-store-demo/02-compose-to-aspire/`

Before architecture or implementation begins:

- select an exact upstream commit;
- record the full commit SHA;
- verify that the upstream working tree at that commit is clean;
- record the applicable upstream license;
- treat the pinned source state as immutable for this experiment.

Do not use a moving `main` branch as reproducibility evidence.

## Experiment Structure

This issue should establish:

```text
experiments/08-aks-store-demo/
├── README.md
├── 01-compose-baseline/
└── 02-compose-to-aspire/
```

The `02-compose-to-aspire/` directory must contain only a concise placeholder explaining that the Aspire migration will be tracked separately after the Compose baseline has been reviewed, merged, and accepted.

Do not implement AppHost code in this issue.

## Authoritative Source Model

The pinned upstream `docker-compose.yml` and the application source required by that file are the primary source for the local baseline.

The upstream Kubernetes manifests, including `aks-store-all-in-one.yaml`, may be inspected as supporting architecture evidence for:

- expected service completeness;
- service responsibilities;
- environment variables;
- ports;
- health behavior;
- external dependency assumptions;
- differences between Kubernetes and local Compose execution.

The Kubernetes manifests must not replace the official Compose model as the runtime source of truth for this issue.

Any deliberate difference from the pinned upstream Compose behavior must be:

- minimal;
- explicitly justified;
- documented;
- approved before implementation;
- validated as part of the baseline.

## Core Service Scope

The core non-AI baseline must evaluate these services:

1. `documentdb`
2. `rabbitmq`
3. `order-service`
4. `makeline-service`
5. `product-service`
6. `store-front`
7. `store-admin`
8. `virtual-customer`
9. `virtual-worker`

The architecture review must confirm the exact role, build source, dependencies, ports, health behavior, runtime assumptions, and validation requirements of every service.

No required core service may be silently omitted.

## Optional AI Service

The upstream `ai-service` is an optional extension.

The primary PASS criteria must not require:

- Azure OpenAI credentials;
- OpenAI credentials;
- paid external AI APIs;
- access to an Azure subscription;
- external model availability.

The architect must confirm how the application behaves without `ai-service` and whether any `product-service` endpoint, health check, user workflow, or admin workflow still assumes that the AI endpoint exists.

The baseline may exclude `ai-service` from the default core profile only when:

- the pinned upstream documentation supports running without it;
- required product, storefront, admin, order, queue, and persistence workflows remain functional;
- the exclusion is clearly documented;
- the validator does not produce a false PASS by ignoring a broken required path.

An optional AI profile may be documented, but external AI validation is not required for completion of this issue.

No real API key may be committed.

## Stage 1 — Architecture and Baseline Research

Before implementation, dispatch a fresh architecture session.

The architect must inspect the pinned upstream source and produce a reviewable baseline design covering:

- complete service inventory;
- language and build technology for each application service;
- Docker build contexts and Dockerfiles;
- container images and tags;
- commands and entrypoints;
- working directories;
- container users or groups;
- application-visible hostnames and identities;
- environment variables;
- internal DNS names;
- queue names and AMQP address formats;
- DocumentDB connection-string and TLS assumptions;
- database and collection names;
- service ports;
- host bindings;
- network behavior;
- health checks;
- startup dependencies;
- restart policies;
- source-relative build contexts;
- relative configuration paths;
- application state;
- persistence expectations;
- generated workload behavior;
- optional AI behavior;
- secret boundaries;
- cleanup and reset behavior;
- runtime resource requirements;
- known upstream limitations;
- differences between the upstream Kubernetes and Compose deployments.

The report must distinguish:

1. upstream behavior that must be preserved;
2. local validation adaptations that are proposed;
3. unresolved decisions requiring operator approval.

Post the complete architecture report to this issue and stop before implementation.

Do not create implementation branches, commits, pull requests, or application changes before explicit Human Baseline Approval.

## Human Baseline Approval

The operator must explicitly approve:

- the pinned upstream commit;
- required service scope;
- optional AI treatment;
- source import strategy;
- local port exposure;
- treatment of automated workload services;
- persistence interpretation;
- any local Compose override;
- any deviation from upstream behavior;
- functional and negative validation plan.

Architecture approval does not authorize unrelated application refactoring.

## Source Import and Provenance

Prefer a reproducible source snapshot under the Experiment 08 baseline directory.

The imported source must:

- correspond exactly to the approved upstream commit;
- exclude nested `.git` metadata;
- preserve the upstream license and required notices;
- include only the source and configuration required to build and validate the approved baseline;
- record file provenance;
- record the upstream repository and commit;
- remain unchanged except for separately approved local-runtime compatibility changes.

If a tracked source snapshot is not used, the architect must justify the alternative and provide a deterministic bootstrap process that retrieves and verifies the exact pinned source.

Do not depend on an unpinned external clone.

## Implementation Scope

After explicit architecture approval, validate and freeze the baseline only under:

`experiments/08-aks-store-demo/01-compose-baseline/`

Allowed implementation work includes:

- pinned upstream source or deterministic source bootstrap;
- the approved official Docker Compose baseline;
- minimal local Compose override when approved;
- non-secret configuration;
- `.env.example`;
- startup script;
- native validation script;
- negative validation script;
- cleanup and reset script;
- architecture and runtime documentation;
- developer validation evidence;
- independent tester evidence.

Do not modify other experiments.

Do not implement Aspire resources.

Do not modify the active skill.

## Local Runtime Safety

All host-exposed endpoints must bind to loopback.

Required user-facing endpoints should include:

- `store-front`;
- `store-admin`.

RabbitMQ management may be exposed on loopback when required for validation.

Backend APIs, RabbitMQ protocol ports, and DocumentDB must remain internal unless host access is specifically required by an approved deterministic validator.

Any required host binding must be:

- loopback-only;
- documented;
- collision-checked;
- scoped to Experiment 08;
- excluded from public exposure.

Do not add firewall rules, public IP exposure, cloud load balancers, or external ingress.

## Deterministic Workload Behavior

The upstream application includes automated order generation and processing services.

The baseline must preserve:

- `virtual-customer`;
- `virtual-worker`.

However, automated workload must not make deterministic validation ambiguous.

The architecture must define one of these controlled approaches:

- temporarily disable or pause automated generators during current-run evidence collection;
- set explicitly documented deterministic rates;
- separate deterministic core validation from a later workload-profile validation.

The validator must not mistake orders created by background workload for the current validation run.

The selected behavior must remain close to upstream semantics and be documented.

## Functional Acceptance Criteria

The baseline must demonstrate a meaningful end-to-end store workflow.

At minimum, validation must prove:

1. all required core services are represented with the expected identities;
2. required dependencies become ready;
3. `store-front` is reachable through the documented loopback endpoint;
4. `store-admin` is reachable through the documented loopback endpoint;
5. product data is available through an application workflow;
6. a unique current-run order can be created;
7. the order is accepted by `order-service`;
8. the order enters the expected RabbitMQ workflow;
9. `makeline-service` processes or observes the order as designed;
10. the order or resulting state is recorded in DocumentDB;
11. the current-run order is visible through an appropriate application or admin workflow;
12. cleanup is repeatable.

A process-state check, generic page text, or an old order is insufficient.

## Unique Current-Run Evidence

Every validation run must generate a unique run identifier.

The validator must capture enough evidence to distinguish the current run from:

- seeded data;
- virtual-customer traffic;
- previous manual orders;
- stale containers;
- an earlier validation run.

Current-run evidence should include, where supported:

- unique product, customer, order, or correlation value;
- pre-operation state;
- submitted request;
- queue or consumer evidence;
- resulting application state;
- DocumentDB evidence;
- admin-facing evidence.

Do not commit raw customer information, credentials, cookies, access tokens, database dumps, or excessive runtime logs.

## RabbitMQ Validation

Validation must prove more than RabbitMQ container health.

It must confirm:

- expected broker identity;
- expected queue configuration;
- application connectivity;
- order publication;
- order consumption or processing;
- no false PASS from an unrelated RabbitMQ container;
- recovery after the approved negative test.

RabbitMQ credentials must be treated as local demo configuration, not production credentials.

No real credential may be committed.

## DocumentDB Validation

Validation must prove more than DocumentDB process health.

It must confirm:

- expected service identity;
- expected connection path;
- approved TLS behavior;
- expected database and collection usage;
- current-run application data;
- application-level visibility of the resulting state.

The validator must not treat container existence or seeded data alone as sufficient evidence.

## Persistence Investigation

The pinned upstream Compose configuration does not automatically establish that state is durable across container recreation.

Before claiming persistence, determine and document:

- behavior across service restart;
- behavior across Compose stop and start without resource deletion;
- behavior across container recreation;
- behavior across `docker compose down`;
- whether DocumentDB uses internal writable container state;
- whether an explicitly configured named volume is supported;
- whether adding durable local storage changes upstream semantics;
- what cleanup or full reset removes.

Do not add a volume and describe it as equivalent without validation.

If durable storage is approved and supported, validation must:

1. create current-run application data;
2. stop the Compose application in a controlled manner;
3. preserve the configured durable storage;
4. start the same baseline again;
5. verify the same application-level evidence;
6. document full reset separately.

If durable storage is not supported or is outside the accepted baseline, classify the exact lifecycle guarantee and do not make a stronger persistence claim.

## Relative Paths and Project Directory

The official Compose file uses relative application build contexts.

Any copied Compose file, temporary override, generated configuration, or validation command must preserve the intended source project directory and relative path resolution.

The baseline must record:

- the original project directory;
- effective Compose files and their order;
- build-context resolution;
- any relative configuration or source path;
- any approved replacement with an explicitly equivalent path.

Do not allow a temporary Compose file in another directory to silently change build or mount semantics.

## Compose Runtime Isolation

Validation must prove that evidence comes from Experiment 08.

Use deterministic experiment-specific identities for:

- Compose project;
- containers where practical;
- network;
- volumes if approved;
- evidence files;
- validation run identifiers.

The validator must detect or reject:

- missing required services;
- stopped required services;
- duplicate required services;
- unexpected service identities;
- stale containers from earlier runs;
- unrelated RabbitMQ or DocumentDB instances;
- endpoints served by another experiment.

Do not rely only on default container names.

## Negative Validation

Include at least one deterministic negative test.

Preferred negative scenario:

- make RabbitMQ unavailable to the order workflow;
- execute the native validator;
- confirm a non-zero exit code;
- confirm the failed dependency or functional path is reported correctly;
- restore the baseline;
- rerun positive validation successfully.

An alternative DocumentDB dependency failure may be used when it produces a safer and more deterministic test.

The negative test must not corrupt persistent data or leave the environment broken.

## Developer Validation

Developer validation must include:

- source provenance verification;
- Compose configuration rendering;
- image build validation;
- expected service inventory;
- health and readiness checks;
- loopback endpoint checks;
- product workflow;
- unique order workflow;
- RabbitMQ workflow;
- DocumentDB evidence;
- persistence classification;
- negative validation;
- cleanup;
- fresh repeat run;
- Git hygiene;
- secret scan.

Record concise evidence in the experiment directory.

Do not commit large runtime logs or environment-specific paths when a concise evidence summary is sufficient.

## Independent Tester Validation

A fresh independent tester session is required after developer validation.

The tester must:

- begin from the documented baseline;
- verify the pinned source;
- use a fresh validation run identifier;
- independently start the baseline;
- verify the exact expected service set;
- exercise the functional workflow;
- inspect RabbitMQ and DocumentDB evidence independently;
- execute the negative test;
- verify recovery;
- verify cleanup and repeatability;
- check for tracked secrets and local runtime artifacts;
- report any deviation from the approved architecture.

The tester must not rely solely on the developer report.

## Required Deliverables

At minimum, deliver:

- Experiment 08 root README;
- `01-compose-baseline/README.md`;
- `02-compose-to-aspire/README.md` placeholder;
- pinned upstream source record;
- preserved upstream license;
- source and service inventory;
- Kubernetes-versus-Compose comparison;
- runtime-contract documentation;
- persistence assessment;
- accepted official Docker Compose baseline;
- approved local override, if required;
- `.env.example`;
- startup and shutdown instructions;
- validation entrypoint;
- negative validation entrypoint;
- cleanup and full-reset instructions;
- developer validation report;
- independent tester report;
- final Compose baseline assessment;
- known limitations;
- rollback instructions.

The native validation entrypoint must return non-zero when the baseline is incomplete or functionally invalid.

## Repository and Runtime Boundaries

Do not:

- modify completed experiments;
- copy AppHost code or validators from earlier experiments;
- implement .NET Aspire;
- create an Aspire solution or AppHost;
- update or create a migration skill;
- apply a Skill Workshop proposal;
- modify OpenClaw runtime configuration;
- modify DevClaw package configuration;
- enable heartbeat;
- enable parallel workflow execution;
- enable automatic merge;
- create GCP, Azure, or other cloud resources;
- add Terraform or Bicep deployment work;
- deploy to AKS;
- expose endpoints publicly;
- commit secrets, tokens, cookies, local environment files, raw dumps, or private endpoints;
- perform unrelated application modernization.

Reusable methodology may be referenced, but implementation artifacts from previous experiments must not be copied as the solution.

## Out of Scope

- Docker Compose to .NET Aspire migration;
- AKS deployment;
- Kubernetes migration;
- Azure infrastructure;
- production hardening;
- external AI integration as a completion requirement;
- application feature development;
- language or framework upgrades;
- source refactoring unrelated to local baseline compatibility;
- CI/CD platform work;
- active skill changes;
- final Experiment 08 Knowledge Review.

## Workflow and Approval Gates

Required sequence:

1. Source and Architecture Research
2. Human Baseline Approval
3. Compose Baseline Validation and Freeze
4. Developer Validation
5. Independent Tester Validation
6. Human Review
7. Human Merge
8. Issue Closeout

Execution must remain sequential.

The architect must stop before implementation.

The developer and tester must stop before human merge.

The pull request must not be merged automatically.

The issue must not be closed automatically.

## Pull Request Expectations

Create one focused implementation pull request for this issue.

Suggested branch:

`experiment-08/aks-store-compose-baseline`

Suggested pull request title:

`Validate and freeze the AKS Store Demo Compose baseline`

Suggested primary implementation commit:

`test(experiment-08): validate AKS Store Compose baseline`

The pull request must reference this issue without automatically closing it.

Use:

`Refs #<ISSUE_NUMBER>`

Do not use `Closes` or `Fixes`.

Final merge remains an operator decision.

## Completion Criteria

This issue is complete only when:

- the upstream commit is pinned;
- architecture research is complete;
- Human Baseline Approval is recorded;
- all required core services are accounted for;
- optional AI behavior is explicitly classified;
- the official Compose baseline builds and starts reproducibly;
- functional current-run order evidence passes;
- RabbitMQ workflow validation passes;
- DocumentDB application-state validation passes;
- persistence semantics are proven and accurately described;
- negative validation returns non-zero as expected;
- recovery after the negative test passes;
- independent tester validation passes;
- cleanup and fresh repeat startup pass;
- no secrets or runtime-only artifacts are committed;
- the implementation pull request is human-reviewed and merged;
- repository documentation records the accepted Compose baseline;
- the issue is closed manually as completed.



## Accepted Baseline Issue #14 Comments

### Comment by devclaw-agent-devbox[bot] at 2026-07-30T20:43:15Z

🏗️ **ARCHITECT**: ## Stage 1 Architecture and Baseline Research Report

Status: **ready for Human Baseline Approval**. No repository implementation changes, branch, commit, pull request, Aspire work, skill change, developer dispatch, or tester dispatch were performed in this stage.

### Source Provenance Recommendation

Recommended pinned upstream source:

- Repository: `https://github.com/Azure-Samples/aks-store-demo`
- Commit: `7ce10c5110d6a52d3517dfb6d7a7b7b2edf2e5a5`
- Upstream branch observed at selection time: `main`
- Upstream working tree check at the selected commit: clean in a detached checkout
- License: MIT License, upstream `LICENSE.md`

This commit should be treated as immutable input for Experiment 08A. Do not use moving `main` as implementation evidence.

Recommended import strategy: create a reproducible source snapshot under `experiments/08-aks-store-demo/01-compose-baseline/`, excluding nested `.git` metadata and preserving `LICENSE.md`, provenance, the approved Compose model, and only the source/configuration needed to build and validate the accepted baseline. A tracked snapshot is preferred over an unpinned bootstrap clone because it makes review, validation, and later Aspire input stable.

### Authoritative Runtime Model

The upstream `docker-compose.yml` is the primary local runtime source of truth. The upstream Kubernetes manifests are supporting architecture evidence only. They help confirm service completeness, image names, probes, resource expectations, and cloud-versus-local differences, but they should not replace the official Compose behavior for this issue.

The upstream repository also contains `docker-compose-quickstart.yml`, but that is a reduced four-service tutorial variant. It is not sufficient for Experiment 08A because the issue requires the full core non-AI service set.

### Required Core Service Inventory

| Service | Role | Technology | Compose source or image | Ports | Health behavior | State |
| --- | --- | --- | --- | --- | --- | --- |
| `documentdb` | Local DocumentDB-compatible MongoDB endpoint for order persistence | Prebuilt container | `ghcr.io/documentdb/documentdb/documentdb-local:pg17-0.112.0` | container `10260`; upstream host `10260` | TLS socket check with `openssl s_client` | Internal container writable state; no named volume in upstream Compose |
| `rabbitmq` | AMQP broker for `orders` queue | Prebuilt container | `rabbitmq:4.3.2-management-alpine` | container `5672`, `15672`; upstream host both ports | `rabbitmqctl status` | Broker state inside container unless explicit volume is added |
| `order-service` | Accepts order submissions and publishes to RabbitMQ | Node.js/Fastify | build `src/order-service`, Dockerfile based on `node:24.14-alpine` | container/host `3000` upstream | `GET /health` | Stateless publisher |
| `makeline-service` | Consumes orders, assigns random numeric order IDs, writes pending orders to DocumentDB, exposes order API | Go/Gin | build `src/makeline-service`, builder `golang:1.26-alpine`, runner `alpine:3.22` | container/host `3001` upstream | `GET /health`, returns 503 until DB is ready | Persists orders through DocumentDB |
| `product-service` | In-memory product CRUD and AI proxy endpoints | Rust/Actix Web | build `src/product-service`, Rust builder with cargo-chef, `debian:bookworm-slim` runner | container/host `3002` upstream | `GET` and `HEAD /health` | Seeded in-memory product catalog, resets on container restart |
| `store-front` | Customer UI for browse, cart, checkout | Vue app served by nginx | build `src/store-front`, Node builder and `nginx:stable-alpine-slim` runner | listens `8080`; upstream host `8080` | nginx `/health` JSON | Cart is browser `localStorage`; order state is backend-driven after checkout |
| `store-admin` | Employee/admin UI for products and order queue | Vue app served by nginx | build `src/store-admin`, Node builder and `nginx:stable-alpine-slim` runner | listens `8081`; upstream host `8081` | nginx `/health` JSON | Reads products from product-service and pending orders from makeline-service |
| `virtual-customer` | Automated order creation workload | Rust | build `src/virtual-customer`, Rust builder, `debian:bookworm-slim` runner | none | no Compose healthcheck | Generates random orders forever when rate is positive |
| `virtual-worker` | Automated pending-order processing workload | Rust | build `src/virtual-worker`, Rust builder, `debian:bookworm-slim` runner | none | no Compose healthcheck | Reads pending orders and updates them through makeline-service |

No `USER` directive is present in the application Dockerfiles. The baseline should document the image default user behavior rather than asserting non-root hardening.

### Optional AI Service Classification

| Service | Role | Technology | Default status recommendation |
| --- | --- | --- | --- |
| `ai-service` | Optional OpenAI-compatible text and image generation backend | Python/FastAPI | Exclude from the default PASS criteria; document as optional profile |

The upstream README explicitly supports running locally without `ai-service` when Azure OpenAI or OpenAI credentials are unavailable. The default Experiment 08A PASS criteria should not require any Azure subscription, paid model endpoint, external AI availability, or real API key.

Product-service still has `AI_SERVICE_URL=http://ai-service:5001/` and exposes `/ai/*` proxy routes. Store-admin checks `/api/ai/health` and has UI paths for AI-assisted product descriptions/images. Therefore, default validation must prove that product browsing, product administration without AI generation, storefront checkout, order queueing, makeline processing, DocumentDB evidence, and admin order visibility work without `ai-service`. AI endpoints should be classified as optional expected-unavailable behavior in the core profile, not as ignored breakage.

No real API key may be committed. If an optional AI profile is later approved, it should use `.env.example` placeholders and local untracked environment files.

### Dependencies and Startup Relationships

Upstream Compose startup relationships:

- `order-service` waits for healthy `rabbitmq`.
- `makeline-service` waits for healthy `rabbitmq` and healthy `documentdb`.
- `store-front` depends on `product-service` and `order-service`, but only with default Compose startup semantics.
- `store-admin` depends on `product-service` and `makeline-service`, but only with default Compose startup semantics.
- `virtual-customer` waits for healthy `order-service`.
- `virtual-worker` waits for healthy `makeline-service`.
- `product-service` has no Compose dependency on `ai-service`, even though it is configured with the AI URL.
- `ai-service` has no dependency.

Runtime dependencies:

- Storefront proxies `/api/products` to `product-service:3002` and `/api/orders` to `order-service:3000`.
- Store-admin proxies product APIs to `product-service:3002`, makeline order APIs to `makeline-service:3001`, order submission to `order-service:3000`, and AI endpoints through product-service.
- Order-service declares and publishes to RabbitMQ queue `orders` using host `rabbitmq`, port `5672`, username `username`, password `password`.
- Makeline-service consumes RabbitMQ using `ORDER_QUEUE_URI=amqp://rabbitmq:5672`, queue `orders`, AMQP 1.0 receiver address `/queues/orders`, and local demo credentials.
- Makeline-service stores orders in DocumentDB through `mongodb://documentdb:10260/?tls=true&tlsAllowInvalidCertificates=true`, database `orderdb`, collection `orders`, username `username`, password `password`, auth source `orderdb`, and TLS with invalid certificate allowed.

Validator implication: after Compose reports containers healthy, validation must still poll application-level readiness through frontend/admin and backend paths because Compose dependency order is not enough to prove functional readiness.

### Ports, Networking, and Local Runtime Safety

Upstream Compose publishes all backend and UI ports to the host without loopback qualification:

- `documentdb`: `10260:10260`
- `rabbitmq`: `15672:15672`, `5672:5672`
- `order-service`: `3000:3000`
- `makeline-service`: `3001:3001`
- `product-service`: `3002:3002`
- `store-front`: `8080:8080`
- `store-admin`: `8081:8081`
- `ai-service`: `5001:5001`

All services join one bridge network named `backend_services`. Internal DNS names are the Compose service names and must be preserved.

Recommended local adaptation requiring approval:

- Bind user-facing `store-front` and `store-admin` to loopback only.
- Expose RabbitMQ management on loopback only if the validator needs host-side management evidence.
- Keep RabbitMQ AMQP, DocumentDB, order-service, makeline-service, product-service, and AI service internal by default unless the approved validator needs a temporary loopback binding.
- Use an Experiment 08-specific Compose project name and resource labels.
- Avoid relying on upstream fixed `container_name` values for isolation. If implementation keeps them, validation must detect stale or duplicate containers. Prefer removing or replacing fixed `container_name` entries while preserving service names and internal DNS, because service DNS is application-visible and container names are operational identities.

This is a deliberate deviation from upstream Compose host exposure and fixed container names. It should be explicitly approved before implementation.

### Environment Variables and Runtime Contracts

Core environment values that must be preserved unless a local adaptation is approved:

- `rabbitmq`: `RABBITMQ_DEFAULT_USER=username`, `RABBITMQ_DEFAULT_PASS=password`.
- `order-service`: `ORDER_QUEUE_HOSTNAME=rabbitmq`, `ORDER_QUEUE_PORT=5672`, `ORDER_QUEUE_USERNAME=username`, `ORDER_QUEUE_PASSWORD=password`, `ORDER_QUEUE_NAME=orders`.
- `makeline-service`: `ORDER_QUEUE_URI=amqp://rabbitmq:5672`, `ORDER_QUEUE_USERNAME=username`, `ORDER_QUEUE_PASSWORD=password`, `ORDER_QUEUE_NAME=orders`, `ORDER_DB_URI=mongodb://documentdb:10260/?tls=true&tlsAllowInvalidCertificates=true`, `ORDER_DB_NAME=orderdb`, `ORDER_DB_COLLECTION_NAME=orders`, `ORDER_DB_USERNAME=username`, `ORDER_DB_PASSWORD=password`.
- `product-service`: `AI_SERVICE_URL=http://ai-service:5001/` in upstream Compose. For a no-AI core profile, either preserve this and document optional AI health failures, or approve a local profile-specific value only if product/admin workflows remain equivalent.
- `virtual-customer`: `ORDER_SERVICE_URL=http://order-service:3000/`, upstream Compose `ORDERS_PER_HOUR=30`.
- `virtual-worker`: `MAKELINE_SERVICE_URL=http://makeline-service:3001`, upstream Compose `ORDERS_PER_HOUR=20`.
- `ai-service`: Azure/OpenAI environment placeholders only; no real secrets.

The RabbitMQ and DocumentDB credentials are local demo configuration, not production secrets. They may appear in `.env.example` and documentation as sample values, but no real credentials or API keys should be committed.

### Commands, Entry Points, and Working Directories

- `documentdb`: image command `--username username --password password`.
- `rabbitmq`: image default command.
- `order-service`: `WORKDIR /app`, `CMD npm start`.
- `makeline-service`: runner starts `CMD ./main`; no explicit runner `WORKDIR`, binary copied to image root.
- `product-service`: `WORKDIR /app`, `CMD ./product-service`.
- `store-front`: nginx runner, generated `default.conf`, `CMD nginx -g 'daemon off;'`.
- `store-admin`: nginx runner, generated `default.conf`, `CMD nginx -g 'daemon off;'`.
- `virtual-customer`: `WORKDIR /app`, `CMD ./virtual-customer`.
- `virtual-worker`: `WORKDIR /app`, `CMD ./virtual-worker`.
- `ai-service`: `WORKDIR /app`, `CMD uvicorn main:app --host 0.0.0.0 --port 5001`.

Build contexts are source-relative paths from the upstream repository root. Any copied Compose file, wrapper script, or override must preserve project-directory semantics so `src/...` paths resolve exactly as intended.

### Application State and Persistence

Observed state model:

- Product catalog is seeded in product-service memory and resets on product-service restart or recreation.
- Storefront cart is browser `localStorage`; it is not server-side persisted.
- Orders are stored by makeline-service in DocumentDB database `orderdb`, collection `orders`.
- Makeline assigns a random numeric `orderId` during queue consumption and sets status `Pending`.
- Virtual-worker updates pending orders to `Processing`; the UI labels non-zero status as completed.
- Upstream Compose does not declare a named DocumentDB volume. Therefore, persistence beyond container lifetime must not be claimed until measured.

Persistence classification to validate after approval:

1. Service restart: verify whether current-run order remains visible after restarting makeline-service only.
2. Compose stop/start without deletion: verify whether current-run order remains visible if containers are stopped and started without removing the DocumentDB container.
3. Container recreation: verify whether current-run order survives `docker compose up --force-recreate` or DocumentDB container recreation.
4. Compose down: verify whether state is removed by `docker compose down` under the approved configuration.
5. Optional named volume: evaluate only if approved, because adding durable storage changes upstream semantics and must not be described as equivalent without evidence.

Expected initial assumption: the official Compose baseline likely provides runtime state while the DocumentDB container exists, not a durable-storage guarantee across container deletion.

### Deterministic Workload Handling

The required core baseline includes `virtual-customer` and `virtual-worker`, but their default random behavior can obscure deterministic evidence.

Recommended approval option:

- Preserve both services in the default service set.
- Use a controlled validation mode for deterministic evidence collection:
  - pause or scale `virtual-customer` during the unique current-run order assertion, then restore it for workload-profile validation; or
  - set a documented low fixed `ORDERS_PER_HOUR` and filter by a unique current-run `customerId`.
- Prefer an explicit deterministic validator-submitted order with a unique `customerId` such as `aml08-<runId>`.
- Discover the assigned order ID by querying makeline/admin/DocumentDB for that unique customer ID because makeline overwrites/assigns `orderId` randomly.
- Run `virtual-worker` deterministically after the pending-order evidence is captured, or temporarily set `ORDERS_PER_HOUR=0` for one-shot processing if approved. Note: upstream `virtual-customer` exits when `ORDERS_PER_HOUR=0`, so do not use zero for it if the service is expected to stay running.

The validator must not count old orders, seeded data, or random virtual-customer traffic as current-run evidence.

### Functional Validation Plan

Recommended positive validator sequence after Human Baseline Approval:

1. Verify pinned source provenance and license.
2. Render effective Compose configuration and confirm the approved service set, build contexts, images, ports, env vars, health checks, restart policies, and network.
3. Reject stale or duplicate Experiment 08 containers/resources before startup.
4. Build application images from the pinned source.
5. Start with an Experiment 08-specific Compose project identity.
6. Wait for health plus application readiness.
7. Confirm expected containers and labels belong to the current Compose project.
8. Confirm host exposure is loopback-only and limited to approved endpoints.
9. Fetch storefront health and product data through the storefront endpoint.
10. Fetch admin health and product data through the admin endpoint.
11. Capture pre-operation RabbitMQ queue state and DocumentDB/order state.
12. Submit a unique current-run order to the order workflow.
13. Confirm `order-service` accepts the request with expected success status.
14. Confirm RabbitMQ queue `orders` exists and that application publication/consumption behavior changes as expected.
15. Confirm makeline consumes the order and writes a DocumentDB record containing the unique customer marker.
16. Confirm the current-run order is visible through makeline/admin-facing workflow.
17. Process or observe order completion according to the approved virtual-worker behavior.
18. Run persistence classification checks without overstating durability.
19. Run negative validation.
20. Restore, rerun positive validation, clean up, and verify a fresh repeat run.

### Negative Validation Plan

Preferred negative scenario: make RabbitMQ unavailable to the order workflow.

Recommended behavior:

- Stop or isolate only the Experiment 08 RabbitMQ resource.
- Run the native validator against the running baseline.
- Expect non-zero exit.
- Require the failure message to identify RabbitMQ/order publication or queue connectivity, not a generic page or process failure.
- Restore RabbitMQ.
- Rerun positive validation successfully.
- Ensure no persistent data corruption or broken environment remains.

A DocumentDB negative test is acceptable if RabbitMQ failure proves unsafe in implementation, but the alternative must still demonstrate a dependency-specific non-zero failure and clean recovery.

### Kubernetes Versus Compose Differences

Supporting Kubernetes evidence at the pinned commit shows these notable differences:

- Kubernetes uses prebuilt images tagged `2.2.0` for application services, while Compose builds local images from source.
- Kubernetes exposes `store-front` and `store-admin` as `LoadBalancer` services on port 80 targeting container ports `8080` and `8081`. Compose binds local host ports directly.
- Kubernetes keeps backend services as `ClusterIP`; upstream Compose exposes backend ports to the host.
- Kubernetes includes init containers and probes for startup/readiness, especially RabbitMQ waits. Compose uses `depends_on` health checks for some dependencies and default depends-on semantics elsewhere.
- Kubernetes sets `FASTIFY_ADDRESS=0.0.0.0` for order-service; Compose does not set it explicitly. The Compose image still starts successfully by upstream design and should remain authoritative for local validation.
- Kubernetes workload rates are `ORDERS_PER_HOUR=100` for both virtual services; upstream Compose uses `30` for virtual-customer and `20` for virtual-worker.
- Kubernetes resources specify CPU and memory requests/limits; Compose does not. Local documentation should record practical resource needs but avoid treating Kubernetes limits as Compose constraints unless validated.
- Kubernetes full all-in-one deployment excludes `ai-service` by default, consistent with optional AI classification.

### Proposed Experiment Structure After Approval

Implementation should be limited to:

```text
experiments/08-aks-store-demo/
├── README.md
├── 01-compose-baseline/
│   ├── README.md
│   ├── upstream-source-record.md
│   ├── LICENSE.md
│   ├── source-and-service-inventory.md
│   ├── runtime-contract.md
│   ├── persistence-assessment.md
│   ├── docker-compose.yml or compose.yaml
│   ├── docker-compose.local.yml, if approved
│   ├── .env.example
│   ├── scripts/
│   └── validation reports
└── 02-compose-to-aspire/
    └── README.md
```

The `02-compose-to-aspire/README.md` should be a placeholder only. It should state that the Aspire migration is reserved for a later issue after the Compose baseline is reviewed, merged, and accepted.

### Required Source Changes

Preferred source changes: none to application source.

Likely approved local-runtime changes, if any, should be Compose/documentation/script changes only:

- loopback-only host bindings;
- optional AI profile handling;
- Experiment 08-specific project/resource identity;
- deterministic workload validation profile;
- optional port collision handling;
- validation and cleanup scripts.

Any application source patch should be treated as an unresolved decision requiring explicit approval because the issue asks to freeze the official Compose baseline rather than modernize application code.

### Rollback and Cleanup Approach

Implementation should provide:

- normal shutdown that stops only Experiment 08 containers;
- cleanup that removes Experiment 08 containers and networks;
- full reset that also removes any approved Experiment 08 volumes;
- stale-resource detection before startup;
- no interaction with other experiments;
- no firewall, public IP, cloud, AKS, Terraform, or Bicep changes.

If a tracked source snapshot is introduced and later rejected, rollback is a repository-level removal of `experiments/08-aks-store-demo/` changes before merge. Runtime rollback is `docker compose down` with the approved project name plus optional volume reset only when the operator requests a full reset.

### Risks and Limitations

- The official Compose file exposes backend ports and uses fixed `container_name` values; local safety and isolation require approved adaptation.
- Product-service has in-memory product state; product CRUD persistence should not be claimed.
- Storefront cart state is browser-local and outside server persistence.
- DocumentDB durability is not established by upstream Compose because no named volume is declared.
- Makeline randomizes `orderId`, so validation must correlate using a unique customer or payload marker.
- Automated workload can create background orders that obscure current-run evidence.
- Optional AI endpoints may return failures without credentials; this must be classified rather than hidden.
- Build uses current upstream base images and package ecosystems; image build timing and registry availability may affect repeatability.
- RabbitMQ AMQP 1.0 queue addressing uses `/queues/orders`; validation should exercise application behavior rather than only broker health.
- The upstream application is explicitly a demo, not production-hardened code.

### Decisions Required for Human Baseline Approval

Please approve or revise these decisions before implementation starts:

1. Pin upstream commit `7ce10c5110d6a52d3517dfb6d7a7b7b2edf2e5a5`.
2. Use MIT license provenance from upstream `LICENSE.md`.
3. Treat the nine non-AI services as required core scope.
4. Exclude `ai-service` from default PASS criteria and document it as an optional profile.
5. Use a tracked pinned source snapshot under the Experiment 08 baseline directory, excluding nested `.git` metadata.
6. Apply loopback-only host exposure and keep non-UI backends internal unless specifically needed by the approved validator.
7. Replace or remove fixed upstream `container_name` values if needed for Experiment 08 isolation while preserving service DNS names.
8. Use a deterministic validation mode for automated workload so current-run order evidence is unambiguous.
9. Classify persistence only after measured lifecycle checks; do not add a named volume unless explicitly approved.
10. Use RabbitMQ-unavailable negative validation by default, with DocumentDB failure as the fallback if safer.
11. Keep application source unchanged unless implementation proves a minimal compatibility patch is required and the operator approves it.
12. Preserve sequential execution: implementation waits for Human Baseline Approval, then developer validation, independent tester validation, human review, and human merge.

### Acceptance Criteria for Future Developer

- No work starts before Human Baseline Approval is recorded.
- Files are added only under `experiments/08-aks-store-demo/`.
- No Aspire implementation is added.
- No active skill changes are made.
- Pinned upstream provenance, license, service inventory, runtime contract, persistence assessment, validation scripts, negative validation, cleanup, and evidence reports are committed.
- Effective Compose configuration represents all approved core services.
- Host bindings are loopback-only and collision-checked.
- Positive validation proves current-run product, order, RabbitMQ, makeline, DocumentDB, admin visibility, cleanup, and repeatability.
- Negative validation returns non-zero for the approved dependency failure and recovery passes afterward.
- Git hygiene and secret scan pass.
- Pull request references the issue without auto-closing it.

### Acceptance Criteria for Future Tester

- Tester starts from the merged or proposed baseline documentation, not developer claims alone.
- Tester independently verifies upstream commit and service inventory.
- Tester uses a fresh run identifier and proves current-run order evidence.
- Tester verifies RabbitMQ and DocumentDB evidence independently.
- Tester runs negative validation and recovery.
- Tester confirms cleanup, repeatability, absence of tracked secrets/runtime artifacts, and no deviations from the approved architecture.
- Tester stops before human merge.

Architecture stage is complete and should now stop at the Human Baseline Approval gate.

### Comment by DimitryZH at 2026-07-30T21:15:25Z

## Human Baseline Approval

Approved.

I approve the proposed Experiment 08A architecture and baseline plan with the following decisions:

1. Pin AKS Store Demo upstream commit:
   `7ce10c5110d6a52d3517dfb6d7a7b7b2edf2e5a5`.

2. Preserve the upstream MIT license and provenance from `LICENSE.md`.

3. Treat the following nine non-AI services as the required core baseline:

   - `documentdb`
   - `rabbitmq`
   - `order-service`
   - `makeline-service`
   - `product-service`
   - `store-front`
   - `store-admin`
   - `virtual-customer`
   - `virtual-worker`

4. Exclude `ai-service` from the default PASS criteria and document it as an optional profile. No external AI credentials or paid AI service are required for Experiment 08A completion.

5. Use a tracked, pinned source snapshot under:

   `experiments/08-aks-store-demo/01-compose-baseline/`

   Exclude nested `.git` metadata and preserve required license and provenance files.

6. Apply loopback-only host exposure for `store-front` and `store-admin`.

   Keep backend services internal by default. RabbitMQ management or other backend endpoints may be temporarily exposed on loopback only when required by the approved deterministic validator.

7. Remove or replace fixed upstream `container_name` values where necessary for Experiment 08 isolation, while preserving Compose service names and application-visible internal DNS identities.

8. Use a deterministic validation mode for `virtual-customer` and `virtual-worker` so current-run evidence cannot be confused with background workload or previous orders.

9. Measure and document persistence behavior across the defined lifecycle scenarios.

   Do not add a named volume or claim durable persistence across container deletion without separate evidence and explicit approval.

10. Use RabbitMQ unavailability as the preferred negative-validation scenario. A DocumentDB dependency failure may be used as a fallback when it is safer or more deterministic.

11. Keep the upstream application source unchanged. Any minimal compatibility patch requires separate operator approval before implementation.

12. Preserve the sequential workflow:

    - implementation;
    - developer validation;
    - independent tester validation;
    - human review;
    - human merge.

Implementation is now authorized within the boundaries of issue #14.

Do not implement .NET Aspire, modify active skills, change unrelated experiments, expose services publicly, or merge automatically.

Any material deviation from the approved architecture—especially application-source changes, durable-storage additions, service-scope changes, or broader host exposure—must stop and return for human approval.

### Comment by devclaw-agent-devbox[bot] at 2026-07-30T22:55:13Z

🔧 **DEVELOPER**: ## Developer implementation report

Branch prepared locally: `experiment-08/aks-store-compose-baseline`

Local commits:

- `1a9bcbf` `test(experiment-08): add AKS Store Compose baseline`
- `15af474` `chore(experiment-08): keep runtime validation artifacts untracked`
- `5b50502` `chore(experiment-08): ignore local validation evidence`

Implemented the approved Experiment 08A Compose baseline under `experiments/08-aks-store-demo/01-compose-baseline/` using the pinned upstream AKS Store Demo provenance from commit `7ce10c5110d6a52d3517dfb6d7a7b7b2edf2e5a5`. The baseline keeps the approved nine default non-AI services, removes fixed container names, keeps backend services internal, binds `store-front` and `store-admin` to loopback, keeps `ai-service` optional behind a profile, adds provenance/service/runtime/persistence documentation, and adds start/cleanup/positive/negative validation scripts.

Static validation passed:

```text
bash -n scripts/validate-compose.sh
bash -n scripts/validate-negative.sh
sha256sum -c upstream-source.sha256
Docker Compose rendered the nine approved default services only.
```

Developer runtime validation is blocked at the approved stop/start persistence gate. The validator successfully reached source provenance, service identity, loopback exposure, product workflow, RabbitMQ queue presence, unique current-run order creation, DocumentDB-backed order visibility, and `makeline-service` restart persistence. It then failed during `docker compose stop` followed by `docker compose start` because the pinned upstream DocumentDB container reruns its bundled seed script and becomes unhealthy on duplicate `_id` seed data:

```text
container aks-store-demo-compose-documentdb-1 is unhealthy
MongoBulkWriteError: Duplicate key violation on the requested collection: Index '_id_'
Error: Failed to execute: 01-users.js
```

I did not weaken or remove that approved validation gate and did not patch upstream application/container behavior, because that would require separate human approval.

Publishing is also blocked in this checkout: normal branch push failed with:

```text
fatal: could not read Username for 'https://github.com': No such device or address
```

No tester/reviewer was dispatched, and no issue/PR was merged or closed.

### Comment by DimitryZH at 2026-07-31T00:49:10Z

## Human Persistence Classification Approval

Approved.

The observed DocumentDB failure during full Docker Compose stop/start is accepted as a measured upstream lifecycle limitation for Experiment 08A.

Proceed with the following classification:

- `makeline-service` restart with current-run order preservation: PASS.
- Docker Compose stop/start with the existing DocumentDB container: EXPECTED FAILURE due to the upstream DocumentDB seed script rerunning and failing on duplicate `_id` data.
- Persistence across container deletion or recreation: not supported and must not be claimed.
- A clean reset followed by fresh startup and full positive validation must still pass.

Do not patch the upstream application or DocumentDB image, add a named volume, remove the lifecycle evidence, or weaken the primary functional validation.

Update the validator and documentation so the stop/start scenario is recorded as a deterministic known limitation with its expected failure signature and recovery procedure.

After completing developer validation, publish the branch through the controlled GitHub authentication path and create a draft pull request for independent tester validation.

### Comment by devclaw-agent-devbox[bot] at 2026-07-31T00:56:36Z

🔧 **DEVELOPER**: ## Developer continuation blocked

I read the latest issue comments directly and confirmed the `Human Persistence Classification Approval` contract:

- `makeline-service` restart with current-run order preservation: PASS.
- Docker Compose stop/start with existing DocumentDB container: EXPECTED FAILURE with duplicate `_id` seed-data signature.
- Persistence across container deletion/recreation is not supported and must not be claimed.
- Clean reset followed by fresh startup/full positive validation must pass.

I began inspecting the existing branch `experiment-08/aks-store-compose-baseline` at `5b5050216f8912f7377ecf9b824588a1db9cabce`, but further repository operations are blocked by the execution environment. The repo checkout is outside the sandbox; non-escalated reads fail with:

```text
bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
```

Escalated repo reads are now rejected by the approval layer with:

```text
Automatic approval review failed: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at Aug 5th, 2026 4:35 AM.
```

Because of that, I could not safely update scripts/docs, run Docker validation, commit refinements, publish the branch, or create the draft PR in this continuation. No tester/reviewer was dispatched, and no PR/issue was merged or closed.

### Comment by devclaw-agent-devbox[bot] at 2026-07-31T01:11:20Z

🔧 **DEVELOPER**: ## Developer final recovery report

Status: **done** after Human Persistence Classification Approval.

Branch: `experiment-08/aks-store-compose-baseline`
Final head: `af05fa1cb4e0b50258f86b4ca75286535063397d`
Draft PR: https://github.com/DimitryZH/application-modernization-lab/pull/15

Validation:

- `./scripts/validate-compose.sh`: PASS.
- `./scripts/validate-negative.sh`: PASS.
- Cleanup completed after validation.

Applied persistence classification:

- `makeline-service` restart with current-run order preservation: PASS.
- Full Docker Compose stop/start with the existing DocumentDB container: EXPECTED FAILURE with the approved duplicate upstream seed-data signature.
- DocumentDB persistence across deletion/recreation: not claimed.
- Clean reset followed by fresh startup and full positive validation: PASS.

No tester was dispatched. No merge or issue closeout was performed.

### Comment by devclaw-agent-devbox[bot] at 2026-07-31T01:14:21Z

🔧 **DEVELOPER**: Follow-up formatting correction pushed after final recovery validation. Branch `experiment-08/aks-store-compose-baseline` now points to `9a12357a1174ba200a761d56010d57b358e01dae`; draft PR remains https://github.com/DimitryZH/application-modernization-lab/pull/15. No validation result changed: positive and negative validation remain PASS, and tester was not dispatched.

### Comment by DimitryZH at 2026-07-31T01:35:41Z

## Human Tester Dispatch Approval

Approved to proceed with independent tester validation of draft PR #15 at the current head.

Dispatch a fresh senior tester session.

The tester must independently evaluate the implementation against issue #14, the approved architecture, and the pull request. The tester may report defects or required changes but must not modify the implementation, merge the PR, or close the issue.

After testing, stop for human review.

### Comment by devclaw-agent-devbox[bot] at 2026-07-31T02:06:35Z

🔍 **TESTER**: ## Senior Tester Validation Report for PR #15

Status: **FAIL for merge readiness / tester validation complete**

Validated current PR head only: `9a12357a1174ba200a761d56010d57b358e01dae` on branch `experiment-08/aks-store-compose-baseline`.

### Contract Sources Read

- Issue #14 objective and acceptance criteria.
- Architecture report comment `5136067827`.
- Human Baseline Approval comment `5136343650`.
- Human Persistence Classification Approval comment `5137877544`.
- Developer reports/comments `5138013159` and `5138032825`.
- Human Tester Dispatch Approval comment `5138192369`.
- PR #15 metadata: draft, open, unmerged, head `9a12357a1174ba200a761d56010d57b358e01dae`, no PR reviews returned by the public reviews API.

### Independent Runtime Validation Evidence

Commands run from `experiments/08-aks-store-demo/01-compose-baseline/`:

```bash
./scripts/cleanup-compose.sh --volumes
./scripts/validate-compose.sh
./scripts/validate-negative.sh
./scripts/cleanup-compose.sh --volumes
./scripts/validate-compose.sh
```

Results:

- Initial cleanup found no existing resources for Compose project `aks-store-demo-compose`.
- Positive validation: **PASS**.
- Negative validation script: **PASS by its own checks**.
- Full positive validation after the RabbitMQ negative path: **PASS**, independently proving runtime recovery after the negative scenario.
- Final cleanup: no Docker containers or labeled volumes remained for `aks-store-demo-compose`.
- Final git status: clean.
- Runtime evidence directory `.local/` is ignored.

Final generated report evidence:

- Source manifest verified pinned upstream commit `7ce10c5110d6a52d3517dfb6d7a7b7b2edf2e5a5`.
- Rendered Compose config has the nine required non-AI services, no fixed container names, and loopback-only UI bindings.
- Storefront/admin health and product proxies reachable on `127.0.0.1:8080` and `127.0.0.1:8081`.
- Product workflow returned 10 seeded products.
- RabbitMQ queue `orders` exists in the Experiment 08 RabbitMQ container.
- Unique current-run order `aml08-20260731020134-156974` was accepted; makeline assigned order `76001` and stored it in DocumentDB.
- Makeline restart preserved access to that current-run order.
- Compose stop/start produced the approved DocumentDB duplicate seed-data expected-failure signature; durable persistence was not claimed.
- Fresh repeat run accepted and stored order `48088` for `aml08-repeat-20260731020341-156974`.

### Passing Gates

- PR checkout was exactly the requested head and clean before validation.
- Upstream source hash manifest passed.
- No nested `.git` metadata found in the imported baseline snapshot.
- Default Compose service set matched the required nine non-AI services.
- Default host exposure was limited to loopback UI ports `8080` and `8081`; backend ports remained internal in the rendered default config.
- Positive functional workflow passed with current-run evidence, RabbitMQ identity, DocumentDB-backed order visibility, makeline restart persistence, approved stop/start limitation, and repeat startup.
- AI remained optional and no real AI credential was required for PASS.
- Focused secret scan found placeholders/source references only, not real API keys or private key material.
- No runtime containers, labeled volumes, or tracked worktree residue remained after cleanup.

### Merge-Blocking Findings

1. **Tracked source scope includes cloud IaC that the approved source model said to exclude.**

   Evidence: `upstream-source-record.md` states that the snapshot excludes upstream cloud/devcontainer/test scaffolding not required to build or validate the local Compose baseline, but tracked PR files include `experiments/08-aks-store-demo/01-compose-baseline/infra/bicep/*` and `experiments/08-aks-store-demo/01-compose-baseline/infra/terraform/*`, including Terraform lock/config files. This conflicts with the issue requirement to include only source/configuration required to build and validate the approved baseline and the explicit out-of-scope boundary against Terraform/Bicep deployment work.

2. **The negative validation entrypoint does not itself prove full recovery after RabbitMQ restoration.**

   Evidence: `validate-negative.sh` stops RabbitMQ, runs `validate-compose.sh --identity-only`, restores RabbitMQ, then runs `validate-compose.sh --identity-only` again. The `--identity-only` path in `validate-compose.sh` exits immediately after Docker identity checks and does not verify health, product workflow, order publication, RabbitMQ queue behavior, makeline consumption, DocumentDB evidence, or admin visibility. I manually ran the full positive validator after the negative script and it passed, so the implementation can recover, but the required negative entrypoint under-proves the approved negative/recovery contract.

### Final Tester Assessment

Runtime behavior is strong and independently reproducible, but PR #15 should not merge as-is because the repository artifact scope/provenance claim and the native negative recovery gate deviate from the approved contract. No implementation changes were made by this tester session; no PR merge, issue close, ready-for-review change, or workflow advancement beyond tester reporting was performed.

### Comment by DimitryZH at 2026-07-31T02:45:28Z

## Human Correction Approval

Approved to return PR #15 to the developer for correction of the two tester findings:

1. Remove the tracked Terraform and Bicep infrastructure content that is outside the approved Compose baseline scope, and update provenance documentation if necessary.

2. Strengthen the native negative-validation entrypoint so that, after RabbitMQ restoration, it proves functional recovery through a fresh unique-order workflow and resulting makeline/DocumentDB evidence rather than container identity alone.

Keep the correction limited to these findings. Reuse the existing branch and PR.

After developer validation, dispatch a fresh targeted tester session to verify the corrections before human merge.

### Comment by devclaw-agent-devbox[bot] at 2026-07-31T03:59:03Z

**DEVELOPER**: ## Developer correction recovery report

Status: **done** after Human Correction Approval.

Fresh senior developer correction session was dispatched but failed in the worker runtime before changing the repository, so the approved two-finding correction was completed through controlled operator recovery.

Branch: `experiment-08/aks-store-compose-baseline`
Final head: `83f1f255f111ee0562cab154c7c4ddf312d848b9`
Draft PR: https://github.com/DimitryZH/application-modernization-lab/pull/15

Corrections:

- Removed tracked upstream `infra/bicep` and `infra/terraform` content from the Experiment 08A Compose baseline and updated provenance to state that upstream infrastructure-as-code content is intentionally excluded from the approved local Compose scope.
- Strengthened `scripts/validate-negative.sh` so RabbitMQ restoration waits for broker health, refreshes order/makeline service connections, then passes `validate-compose.sh --recovery-order-only` with a fresh unique order and makeline/DocumentDB evidence.

Validation:

- `sha256sum -c upstream-source.sha256`: PASS.
- `./scripts/validate-compose.sh`: PASS.
- `./scripts/validate-negative.sh`: PASS.
- Cleanup completed after validation.

Tester redispatch was not performed.

### Comment by DimitryZH at 2026-07-31T14:06:33Z

## Human Targeted Tester Redispatch Approval

Approved to dispatch a fresh senior tester for targeted revalidation of PR #15 at head:

`83f1f255f111ee0562cab154c7c4ddf312d848b9`

The tester should verify the two corrected findings:

1. Out-of-scope Terraform and Bicep content has been removed and source provenance remains accurate.
2. Negative validation now proves functional recovery after RabbitMQ restoration through a fresh unique-order workflow and makeline/DocumentDB evidence.

The tester may also confirm repository cleanliness and that the existing positive validation remains unaffected.

Do not merge the PR or close issue #14. Stop for human review after reporting the result.

### Comment by devclaw-agent-devbox[bot] at 2026-07-31T17:27:11Z

**TESTER**: ## Targeted Tester Recovery Validation Report for PR #15

Status: **PASS for targeted revalidation / tester validation complete**

Validated PR head: `83f1f255f111ee0562cab154c7c4ddf312d848b9`
Draft PR: https://github.com/DimitryZH/application-modernization-lab/pull/15

Scope:

- Revalidated removal of out-of-scope tracked Terraform/Bicep content and provenance accuracy.
- Revalidated RabbitMQ negative recovery through a fresh unique-order workflow and makeline/DocumentDB evidence.
- Confirmed the positive Compose baseline still passes.

Evidence:

- `git ls-files -- experiments/08-aks-store-demo/01-compose-baseline/infra/bicep experiments/08-aks-store-demo/01-compose-baseline/infra/terraform`: no tracked files.
- `upstream-source.sha256`: does not include Terraform/Bicep paths.
- `upstream-source-record.md` and `source-and-service-inventory.md`: document that upstream `infra/bicep` and `infra/terraform` are excluded from the approved Compose baseline scope.
- `sha256sum -c upstream-source.sha256`: PASS.
- `bash -n scripts/validate-compose.sh scripts/validate-negative.sh`: PASS.
- `./scripts/validate-compose.sh`: PASS.
- `./scripts/validate-negative.sh`: PASS; RabbitMQ restore refreshed order/makeline service connections and recovered a fresh unique-order makeline/DocumentDB workflow.
- Cleanup check: PASS; repository clean and no `aks-store-demo-compose` containers remained.

Result:

- No blocker remains from the two prior tester findings.
- No implementation changes were made during this validation.
- PR was not merged or marked ready.
- Issue was not closed.

### Comment by DimitryZH at 2026-07-31T18:05:23Z

## Human Closeout

PR #15 has been human-reviewed and merged.

Experiment 08A is accepted as the official AKS Store Demo Docker Compose baseline for the Application Modernization Lab.

Accepted results:

- upstream AKS Store Demo source pinned to commit `7ce10c5110d6a52d3517dfb6d7a7b7b2edf2e5a5`;
- upstream MIT license and source provenance preserved;
- nine required non-AI services validated;
- optional `ai-service` excluded from the default PASS criteria;
- UI endpoints restricted to loopback;
- backend services kept internal;
- deterministic current-run product and order workflow validated;
- RabbitMQ publication and processing validated;
- makeline and DocumentDB-backed order evidence validated;
- persistence behavior and the upstream DocumentDB stop/start limitation documented;
- RabbitMQ negative validation and functional recovery validated;
- cleanup and fresh repeat execution validated;
- developer and independent tester validation completed successfully.

The accepted baseline under:

`experiments/08-aks-store-demo/01-compose-baseline/`

is now the authoritative runtime input for the future Docker Compose to .NET Aspire migration tracked separately.

No Aspire implementation or active skill modification was included in this issue.

Issue #14 is complete and may be closed as completed.



## Accepted Baseline PR #15

Title: test(experiment-08a): add AKS Store Compose baseline
Merged: true
Merge commit: 38ab6b49868c8b4e490e2464d749f8b0fa92e905
Head SHA: 83f1f255f111ee0562cab154c7c4ddf312d848b9
URL: https://github.com/DimitryZH/application-modernization-lab/pull/15

### Body

## Summary

Implements the approved Experiment 08A AKS Store Demo Docker Compose baseline for issue #14.

## Changes made

- Adds the pinned AKS Store Demo source snapshot and provenance for commit `7ce10c5110d6a52d3517dfb6d7a7b7b2edf2e5a5`.
- Adds the approved nine-service non-AI Docker Compose baseline with loopback-only UI exposure.
- Adds source inventory, runtime contract, persistence classification, Kubernetes-vs-Compose notes, and validation documentation.
- Adds native positive and negative validation scripts.
- Applies the approved DocumentDB persistence classification: makeline restart PASS, full Compose stop/start EXPECTED FAILURE, clean reset/fresh run PASS, no durable deletion/recreation persistence claim.

## Validation performed

- `./scripts/validate-compose.sh`: PASS.
- `./scripts/validate-negative.sh`: PASS.
- Cleanup executed after validation.

## Risk / rollback notes

Draft PR only. No tester was dispatched, no merge was performed, and issue #14 remains open for the next human-controlled validation stage.

Refs #14


### PR #15 Files

- experiments/08-aks-store-demo/01-compose-baseline/.dockerignore (added, +1/-0)
- experiments/08-aks-store-demo/01-compose-baseline/.env.example (added, +16/-0)
- experiments/08-aks-store-demo/01-compose-baseline/.gitignore (added, +156/-0)
- experiments/08-aks-store-demo/01-compose-baseline/.prettierrc.json (added, +6/-0)
- experiments/08-aks-store-demo/01-compose-baseline/LICENSE.md (added, +21/-0)
- experiments/08-aks-store-demo/01-compose-baseline/README.md (added, +48/-0)
- experiments/08-aks-store-demo/01-compose-baseline/aks-store-all-in-one.yaml (added, +604/-0)
- experiments/08-aks-store-demo/01-compose-baseline/aks-store-quickstart.yaml (added, +281/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/.gitignore (added, +1/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/.helmignore (added, +23/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/Chart.yaml (added, +24/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/ai-service.yaml (added, +133/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/documentdb.yaml (added, +67/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/makeline-service.yaml (added, +110/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/order-service.yaml (added, +112/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/product-service.yaml (added, +58/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/rabbitmq.yaml (added, +79/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/service-account.yaml (added, +8/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/store-admin.yaml (added, +62/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/store-front.yaml (added, +62/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/virtual-customer.yaml (added, +49/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/templates/virtual-worker.yaml (added, +49/-0)
- experiments/08-aks-store-demo/01-compose-baseline/charts/aks-store-demo/values.yaml (added, +108/-0)
- experiments/08-aks-store-demo/01-compose-baseline/docker-compose-quickstart.yml (added, +74/-0)
- experiments/08-aks-store-demo/01-compose-baseline/docker-compose.yml (added, +181/-0)
- experiments/08-aks-store-demo/01-compose-baseline/kubernetes-vs-compose.md (added, +12/-0)
- experiments/08-aks-store-demo/01-compose-baseline/persistence-assessment.md (added, +14/-0)
- experiments/08-aks-store-demo/01-compose-baseline/runtime-contract.md (added, +28/-0)
- experiments/08-aks-store-demo/01-compose-baseline/sample-manifests/argocd/pets.yaml (added, +39/-0)
- experiments/08-aks-store-demo/01-compose-baseline/sample-manifests/docs/app-routing/aks-store-deployments-and-services.yaml (added, +204/-0)
- experiments/08-aks-store-demo/01-compose-baseline/sample-manifests/istio/gateway.yaml (added, +35/-0)
- experiments/08-aks-store-demo/01-compose-baseline/scripts/cleanup-compose.sh (added, +13/-0)
- experiments/08-aks-store-demo/01-compose-baseline/scripts/start-compose.sh (added, +9/-0)
- experiments/08-aks-store-demo/01-compose-baseline/scripts/validate-compose.sh (added, +323/-0)
- experiments/08-aks-store-demo/01-compose-baseline/scripts/validate-negative.sh (added, +53/-0)
- experiments/08-aks-store-demo/01-compose-baseline/source-and-service-inventory.md (added, +25/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/.dockerignore (added, +1/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/.env.example (added, +3/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/.gitignore (added, +160/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/.vscode/launch.json (added, +21/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/.vscode/tasks.json (added, +13/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/Dockerfile (added, +26/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/README.md (added, +55/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/main.py (added, +44/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/requirements.txt (added, +12/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/routers/__init__.py (added, +0/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/routers/description_generator.py (added, +195/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/routers/image_generator.py (added, +134/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/ai-service/test-ai-service.http (added, +23/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/.gitignore (added, +24/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/.vscode/launch.json (added, +15/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/.vscode/settings.json (added, +30/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/Dockerfile (added, +31/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/README.md (added, +311/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/consumer.go (added, +203/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/cosmosdb.go (added, +224/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/docker-compose.yml (added, +78/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/go.mod (added, +62/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/go.sum (added, +175/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/main.go (added, +271/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/mongodb.go (added, +261/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/orderqueue.go (added, +26/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/orders.go (added, +37/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/makeline-service/test-makeline-service.http (added, +34/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/.dockerignore (added, +3/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/.gitignore (added, +58/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/.vscode/launch.json (added, +15/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/Dockerfile (added, +26/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/README.md (added, +135/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/app.js (added, +29/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/docker-compose.yml (added, +22/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/package-lock.json (added, +6298/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/package.json (added, +32/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/plugins/README.md (added, +16/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/plugins/messagequeue.js (added, +140/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/plugins/sensible.js (added, +12/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/plugins/support.js (added, +12/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/routes/README.md (added, +27/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/routes/example/index.js (added, +7/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/routes/root.js (added, +18/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/test-order-service.http (added, +28/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/test/helper.js (added, +35/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/test/plugins/support.test.js (added, +26/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/test/routes/example.test.js (added, +27/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/order-service/test/routes/root.test.js (added, +27/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/.dockerignore (added, +1/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/.gitignore (added, +10/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/.vscode/launch.json (added, +102/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/Cargo.lock (added, +2365/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/Cargo.toml (added, +25/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/Dockerfile (added, +22/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/README.md (added, +46/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/docker-compose.yml (added, +36/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/src/app.rs (added, +70/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/src/config.rs (added, +70/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/src/lib.rs (added, +4/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/src/main.rs (added, +9/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/src/models.rs (added, +356/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/src/routes/ai.rs (added, +224/-0)
- experiments/08-aks-store-demo/01-compose-baseline/src/product-service/src/routes/health.rs (added, +8/-0)


### PR #15 Commits

- 1a9bcbfcfb2ae8146556a86aaad082ab90541639 test(experiment-08): add AKS Store Compose baseline
- 15af474aabce32f0970dd1ff2d3c4f497d657047 chore(experiment-08): keep runtime validation artifacts untracked
- 5b5050216f8912f7377ecf9b824588a1db9cabce chore(experiment-08): ignore local validation evidence
- af05fa1cb4e0b50258f86b4ca75286535063397d test(experiment-08a): apply persistence classification approval
- 9a12357a1174ba200a761d56010d57b358e01dae docs(experiment-08a): restore validation result formatting
- 83f1f255f111ee0562cab154c7c4ddf312d848b9 fix(experiment-08a): address tester validation findings
