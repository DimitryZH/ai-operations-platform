Conduct a Knowledge Review of the completed Experiment 07A Bank of Anthos Kubernetes-to-Docker-Compose migration.

Authoritative evidence:

- repository: DimitryZH/application-modernization-lab
- issue: #8
- merged pull request: #9
- merge commit: 3de8845412853525aeb77d85db23f2d14b1bfc73
- corrective commit: 71d059bf5871d2bc5776a9a26688a3e410f78f62
- implementation directory:
  experiments/07-bank-of-anthos/01-kubernetes-to-compose/
- pinned upstream commit:
  1e40564f9ff572a28281198903e19da93e506770

Extract only reusable Kubernetes-to-Docker-Compose migration knowledge supported by the completed experiment.

The review should capture:

- Kubernetes manifest inventory methodology;
- service and dependency mapping;
- configuration and environment-variable translation;
- health, readiness, and dependency semantics;
- PostgreSQL initialization and persistent-volume translation;
- safe local secret and JWT handling;
- loopback-only exposure;
- optional workload profiles;
- immutable image pinning;
- native functional validation;
- service-identity and false-positive prevention;
- authentication and representative transaction validation;
- persistence validation across controlled restart;
- required-dependency negative testing;
- cleanup and repeatability;
- known limitations and conditions where the approach should not be reused.

Create one pending Skill Workshop proposal named:

kubernetes-to-compose-migration

The proposal should be reusable across projects and must not contain Bank of Anthos-specific credentials, generated keys, cookies, machine-specific paths, private endpoints, or local runtime evidence.

Do not apply the proposal.
Do not create or modify active skill files.
Do not modify GitHub, source repositories, infrastructure, or runtime configuration.
Do not begin any Compose-to-Aspire work.
Stop after the pending proposal has been created and report its proposal ID, status, generated files, and scanner result.
