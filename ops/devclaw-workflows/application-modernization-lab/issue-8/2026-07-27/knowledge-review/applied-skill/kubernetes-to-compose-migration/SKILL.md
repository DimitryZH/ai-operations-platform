---
name: "kubernetes-to-compose-migration"
description: "Reusable Kubernetes-to-Docker-Compose migration procedure."
---

# Kubernetes To Compose Migration

Use this skill when converting an existing Kubernetes manifest set into a local Docker Compose baseline for development, experiments, validation, or modernization prep. Keep the first baseline close to the deployed artifact: prefer pinned existing images and configuration translation before changing application behavior.

## Core Workflow

1. Fix the source of truth.
   - Record the upstream repository, commit, tag, or release used for the migration.
   - Treat Kubernetes manifests as the deployment reference for inventory, image selection, environment, ports, probes, dependencies, secrets, security settings, and volumes.
   - Copy or reference only the manifests and licenses needed to audit the baseline.

2. Keep the initial baseline source-neutral.
   - Do not modify application source code for the first Compose baseline by default.
   - Use manifest-backed image references and configuration translation before considering source changes.
   - Any application source change requires documented technical justification and explicit human approval before implementation.
   - Keep approved source changes outside the reusable baseline guidance unless they are required by the target application and clearly documented as an application-specific adaptation.

3. Inventory the Kubernetes manifests.
   - Enumerate Deployments, StatefulSets, DaemonSets, Jobs/CronJobs, Services, ConfigMaps, Secrets, PersistentVolumeClaims, service accounts, annotations, labels, probes, ports, and volume mounts.
   - For every pod template, capture regular containers, initContainers, sidecars, images, command, args, working directory, exposed/container ports, probes, lifecycle hooks, and dependencies implied by startup behavior.
   - Capture securityContext at pod and container scope, including runtime user/group, fsGroup, capabilities, privilege settings, read-only root filesystem, allowPrivilegeEscalation, and volume permission expectations.
   - Capture resource requests and limits, replicas, affinity/tolerations when relevant, and any intentional reduction to one local Compose instance.
   - Capture volume details including PVCs, config/secret/projected volumes, emptyDir, subPath mounts, mount paths, read-only flags, ownership expectations, and initialization requirements.
   - Separate required runtime services from optional test/load/debug workloads.
   - Build a table with Kubernetes object, Compose service name, image, role, ports, config sources, secrets, volumes, security/runtime notes, replica handling, and required dependencies.

4. Map services and dependencies.
   - Preserve Kubernetes Service DNS names as Compose service names when application config expects those names.
   - Use one dedicated Compose network unless the Kubernetes topology requires isolation that matters locally.
   - Translate service-to-service addresses to `service:port` values on the Compose network.
   - Use `depends_on` only for startup ordering and coarse health gates; keep functional readiness checks in validation.
   - Document any reduction from multiple Kubernetes replicas to a single local Compose instance and the behavior this prevents from being validated.

5. Translate configuration deliberately.
   - Flatten ConfigMaps, `env`, and `envFrom` values into Compose `environment` blocks or shared YAML anchors.
   - Convert downward API values such as namespace, pod name, and host name into stable local equivalents only when the application needs them.
   - Translate command, args, working directory, runtime user/group, and read-only filesystem expectations when they affect container startup or file access.
   - Translate resource limits only when they are meaningful for local validation; otherwise document that Kubernetes scheduling and enforcement are not reproduced.
   - Disable or replace cloud-provider-only tracing, metrics, metadata, or workload identity settings when they block local startup; document each difference as a local runtime adaptation.
   - Do not silently invent dependencies that are not present in the source manifests.

6. Translate secrets safely.
   - Never commit generated private keys, tokens, cookies, database dumps, logs, or local validation artifacts.
   - Generate local-only cryptographic material at startup or through a helper script, write it under an ignored local directory, and mount it read-only.
   - Mount private material only into the service that needs to sign or decrypt; mount public material into verification consumers only.
   - Treat demo credentials from upstream manifests as local-only defaults, never production guidance.
   - Avoid carrying project-specific credentials, generated JWT signing keys, session cookies, private endpoints, or machine-specific runtime evidence into reusable guidance.

7. Translate storage.
   - Identify database and stateful mounts from StatefulSets, PVCs, `emptyDir`, projected volumes, subPath mounts, and container entrypoint expectations.
   - Use named volumes for database data when the Compose baseline must validate persistence across `docker compose down` and restart.
   - Remember that `docker compose down` preserves named volumes by default.
   - Preserve volumes during persistence tests; do not use `down --volumes` between the write and restart verification steps.
   - Use `docker compose down --volumes` only for full reset or clean-repeatability tests that intentionally prove initialization from empty storage.
   - Document when Compose intentionally differs from ephemeral Kubernetes development storage.
   - Preserve entrypoint initialization semantics: many database images initialize schema and seed data only when the data directory is empty.

8. Expose ports conservatively.
   - Publish only the user-facing entrypoint required for local validation.
   - Bind published ports to loopback, for example `127.0.0.1:HOST_PORT:CONTAINER_PORT`.
   - Keep backend and database ports internal by default; use a separate debug override if direct host access is needed.

9. Handle optional workloads with profiles or allowlists.
   - Put load generators, synthetic workers, test clients, continuous mutators, or local-only helpers behind approved Compose profiles when they are not part of the required runtime path.
   - Allow extra services only when they are explicitly documented through an approved Compose profile or validation allowlist.
   - Reject unrelated, unexpected, stopped, or mislabeled services during validation.
   - Prevent containers from another Compose project from satisfying validation by checking Compose labels and project identity.
   - Keep optional state-mutating workloads disabled during deterministic validation unless the user explicitly asks to test them.

10. Pin images immutably.
   - Prefer the exact image references from the Kubernetes manifests, including digest pins when available.
   - Avoid local rebuilds during the first migration baseline unless source changes are explicitly required and approved.
   - Document any image pull access assumptions, especially private registries or cloud artifact registries.

11. Validate natively.
   - Add a project-local validation script that uses Docker Compose, HTTP clients, database clients available inside containers, and standard shell tools.
   - Validate exact Compose project identity using Docker labels, not just container names or `docker compose ps` summaries.
   - Validate the expected service set and allow only explicitly documented profile or allowlist additions.
   - Wait for service readiness from inside the Compose network and the externally published loopback endpoint.
   - Exercise authentication through the public entrypoint when the application has auth.
   - Perform a representative business transaction through the application UI/API using a marker unique to the current validation run.
   - Submit the unique marker through the application, verify the same marker in the UI or API response, verify the same marker in the durable store, then verify the marker still exists after restart with volumes preserved.
   - Do not accept generic text, seeded values, account numbers, routing numbers, or other static identifiers as proof of a successful transaction.
   - Query durable stores as secondary evidence for initialization and persistence.
   - Stop or omit a required dependency and assert validation fails for the right reason.
   - Shut down with normal cleanup and document the full reset path with volume deletion.

12. Prevent false positives.
   - Use a deterministic Compose project name or pass `-p` consistently.
   - Validate the exact required service set under `com.docker.compose.project` and `com.docker.compose.service` labels.
   - Reject missing, extra, stopped, unrelated, or mislabeled required services unless an extra service is documented in an approved profile or validation allowlist.
   - Ensure negative tests cannot pass by reading stale containers, seeded data, unrelated projects, or containers from a different Compose project.
   - Generate validation markers per run so previous data cannot satisfy current tests.

13. Document cleanup and repeatability.
   - Use normal cleanup that preserves named volumes when persistence must be tested across restart.
   - Document that `docker compose down` preserves named volumes by default.
   - Document a separate full reset path using `docker compose down --volumes` when the goal is to prove clean initialization from empty storage.
   - Make repeatability checks explicit: one path must prove preserved-volume restart, and another path must prove clean startup after volume removal.

14. Document limitations.
   - State that Compose does not emulate Kubernetes service accounts, cloud metadata, load balancers, ingress controllers, service mesh behavior, scheduling, resource policy, security admission, network policy, horizontal scaling, replica placement, or exact probe timing.
   - List every local runtime adaptation and why it was required.
   - State when the baseline is not suitable for production, security validation, high-availability validation, autoscaling validation, cloud-integration validation, multi-replica behavior validation, or Kubernetes policy validation.

## Reuse Conditions

Use this approach when:

- The goal is a local functional baseline for a manifest-defined application.
- Existing images can run locally with configuration changes only.
- The application can tolerate single-host Compose networking and storage semantics.
- Representative end-to-end workflows can be validated without production systems.
- Any local-only helper, optional workload, or extra service can be documented through an approved profile or validation allowlist.

Do not reuse this approach as-is when:

- The migration target must preserve Kubernetes control-plane semantics exactly.
- Workload identity, service mesh policy, cloud metadata, admission controls, node scheduling, network policy, autoscaling, multi-replica behavior, or strict securityContext enforcement are core requirements.
- Images require production-only credentials or private network access that cannot be safely mocked locally.
- The application requires multi-node behavior, persistent volume classes, or storage semantics that Compose cannot approximate.
- Validation would require real customer data, real credentials, irreversible external transactions, or static seeded data that cannot prove current-run behavior.
- The initial local baseline would require application source code changes that lack documented technical justification and explicit human approval.

## Reference

For a compact migration checklist, read `references/validation-checklist.md` before implementing or reviewing a Compose baseline.
