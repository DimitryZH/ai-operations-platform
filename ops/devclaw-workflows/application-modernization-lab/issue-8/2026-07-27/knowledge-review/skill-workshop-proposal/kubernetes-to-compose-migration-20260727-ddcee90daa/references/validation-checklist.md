# Kubernetes To Compose Validation Checklist

Use this checklist to keep Kubernetes-to-Compose migrations auditable and repeatable.

## Inventory

- Record the upstream source ref and manifest directory.
- List every workload, service, ConfigMap, Secret, volume, probe, port, optional job, service account, annotation, and label.
- For each pod template, capture regular containers, initContainers, sidecars, images, command, args, working directory, ports, probes, lifecycle hooks, and startup dependencies.
- Capture pod and container securityContext values: runtime user/group, fsGroup, capabilities, privilege settings, read-only root filesystem, allowPrivilegeEscalation, and volume permission expectations.
- Capture resource requests/limits, replicas, and any intentional reduction to one local Compose instance.
- Capture PVC, emptyDir, secret, config, projected volume, subPath, mount path, read-only flag, ownership, and initialization semantics.
- Separate required services from optional load, test, debug, and mutating workloads.
- Confirm every Compose service maps back to an authoritative Kubernetes object or documented local-only helper.
- Confirm any local-only helper or extra service is documented in an approved Compose profile or validation allowlist.

## Compose Mapping

- Preserve service DNS names when application configuration depends on them.
- Use a dedicated Compose network and deterministic Compose project name.
- Keep non-entrypoint services unexposed to the host.
- Bind required host-facing ports to loopback.
- Put optional mutating workloads behind approved profiles.
- Reject unrelated or unexpected services unless they are explicitly allowed by profile or validation allowlist.
- Prevent containers from another Compose project from satisfying validation by checking Docker Compose project and service labels.
- Pin images by digest when available.
- Do not modify application source code for the initial Compose baseline unless there is documented technical justification and explicit human approval.

## Configuration And Secrets

- Translate `env`, `envFrom`, ConfigMaps, and downward API fields explicitly.
- Translate command, args, working directory, runtime user/group, read-only filesystem, and permissions when they affect startup or file access.
- Document cloud-only telemetry, metadata, identity, or service-mesh settings that are disabled or changed locally.
- Document resource-limit handling and any local difference from Kubernetes enforcement.
- Generate local-only keys or tokens outside tracked files.
- Mount secrets read-only and only into consumers that need them.
- Add ignore rules and validation checks for generated keys, cookies, logs, dumps, and scratch output.
- Do not include project-specific credentials, generated JWT signing keys, cookies, private endpoints, or machine-specific runtime evidence in reusable guidance.

## Health And Dependencies

- Translate database health to native checks such as readiness commands inside the container.
- Translate HTTP readiness/liveness probes to HTTP checks where practical.
- Use generous startup windows for slow services without hiding real dependency failures.
- Treat Compose `depends_on` as startup help, not proof of readiness.
- Validate readiness from inside the Compose network and through the public loopback entrypoint.
- Run a required-dependency negative test and require failure for the expected reason.

## PostgreSQL And Persistence

- Map stateful database data directories to named volumes when restart persistence matters.
- Confirm first-run schema and seed initialization from empty volumes.
- Remember that `docker compose down` preserves named volumes by default.
- Preserve volumes during persistence tests; never use `down --volumes` between transaction creation and restart verification.
- Submit a transaction marker unique to the current run through the application.
- Verify the same marker in the UI/API and durable store before restart.
- Restart with volumes preserved and verify the same marker is still present afterward.
- Use `docker compose down --volumes` only for full reset and clean-repeatability tests that intentionally remove volumes.
- Document both the preserved-volume restart path and the full reset command that removes volumes.

## Functional Validation

- Verify exact Compose service identity with Docker labels.
- Reject missing, extra, stopped, unrelated, or mislabeled services unless explicitly allowed by profile or validation allowlist.
- Exercise login or equivalent authentication through the public entrypoint.
- Use a cookie jar or token flow when the app requires session state.
- Execute a representative business transaction through the app using a marker unique to the current validation run.
- Assert the same marker through the UI/API response and durable store.
- Do not accept generic page text, seeded values, account numbers, routing numbers, or static fixture data as proof of current-run transaction success.
- Restart with volumes preserved and verify the same marker persists.
- Query durable storage as secondary evidence.
- Run a required-dependency negative test and require failure.
- Finish with normal cleanup, then separately document the full reset path using `docker compose down --volumes`.

## Limitations

- Do not claim Compose reproduces Kubernetes service accounts, service mesh, load balancers, ingress controllers, autoscaling, scheduling, admission policy, network policy, cloud metadata, multi-replica placement, resource-policy enforcement, security admission, or exact probe timing.
- Do not use this local baseline for production security conclusions.
- Do not reuse this approach when source-code changes are required but lack documented technical justification and explicit human approval.
- Do not include private endpoints, real credentials, generated key material, JWT signing keys, cookies, logs, dumps, or machine-specific paths in committed evidence.
