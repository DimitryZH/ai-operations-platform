from __future__ import annotations

import re
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TERRAFORM_ROOT = REPOSITORY_ROOT / "gcp" / "sre-control-plane" / "terraform"


def terraform_source() -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in TERRAFORM_ROOT.glob("*.tf"))


def test_container_runs_as_non_root_and_has_a_health_port() -> None:
    dockerfile = (REPOSITORY_ROOT / "Dockerfile").read_text(encoding="utf-8")

    assert "FROM python:3.13-slim" in dockerfile
    assert "USER controlplane" in dockerfile
    assert "EXPOSE 8080" in dockerfile
    assert "uvicorn sre_control_plane.app:app" in dockerfile


def test_terraform_keeps_runtime_private_and_scheduler_authenticated() -> None:
    source = terraform_source()

    assert 'ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"' in source
    assert "google_cloud_run_v2_service_iam_member" in source
    assert "roles/run.invoker" in source
    assert "oidc_token" in source
    assert 'uri         = "${google_cloud_run_v2_service.control_plane[0].uri}/internal/dispatch/tick"' in source
    assert "allUsers" not in source
    assert "allAuthenticatedUsers" not in source


def test_gcs_evidence_adapter_is_bound_to_existing_bucket_with_scoped_iam() -> None:
    source = terraform_source()

    assert 'name  = "SRE_CONTROL_PLANE_EVIDENCE_STORE"' in source
    assert 'value = "gcs"' in source
    assert 'name  = "SRE_CONTROL_PLANE_GCS_PROJECT_ID"' in source
    assert "value = var.project_id" in source
    assert 'name  = "SRE_CONTROL_PLANE_EVIDENCE_BUCKET"' in source
    assert "value = google_storage_bucket.evidence.name" in source
    assert 'role   = "roles/storage.objectCreator"' in source
    assert 'role   = "roles/storage.objectViewer"' in source
    assert 'role   = "roles/storage.objectUser"' not in source
    assert "google_storage_bucket_iam_member.control_plane_evidence_creator" in source
    assert "google_storage_bucket_iam_member.control_plane_evidence_viewer" in source


def test_runtime_requires_explicit_database_secret_version_and_pauses_scheduler() -> None:
    source = terraform_source()

    assert 'variable "database_secret_version"' in source
    assert 'version = var.database_secret_version' in source
    assert 'version = "latest"' not in source
    assert 'paused      = !var.scheduler_enabled' in source
    assert "scheduler_activation_confirmed" in source


def test_github_publisher_runtime_is_secret_backed_and_allowlisted() -> None:
    source = terraform_source()
    cloud_run = (TERRAFORM_ROOT / "cloud_run.tf").read_text(encoding="utf-8")
    secrets = (TERRAFORM_ROOT / "secrets.tf").read_text(encoding="utf-8")
    variables = (TERRAFORM_ROOT / "variables.tf").read_text(encoding="utf-8")

    assert 'contains(["fake", "github"], var.github_publisher_mode)' in variables
    assert "floor(var.github_publication_issue_number) == var.github_publication_issue_number" in variables
    assert "floor(var.github_publication_allowed_issue_number) == var.github_publication_allowed_issue_number" in variables
    assert "github_publication_repository == var.github_publication_allowed_repository" in cloud_run
    assert "github_publication_issue_number == var.github_publication_allowed_issue_number" in cloud_run
    assert "github_publication_credential_secret_version != null" in cloud_run
    assert 'name  = "SRE_CONTROL_PLANE_PUBLISHER"' in cloud_run
    assert 'name  = "SRE_CONTROL_PLANE_GITHUB_ALLOWED_REPOSITORY"' in cloud_run
    assert 'name  = "SRE_CONTROL_PLANE_GITHUB_ALLOWED_ISSUE_NUMBER"' in cloud_run
    assert 'name  = "SRE_CONTROL_PLANE_GITHUB_CREDENTIAL_SECRET_NAME"' in cloud_run
    assert 'name  = "SRE_CONTROL_PLANE_GITHUB_CREDENTIAL_SECRET_VERSION"' in cloud_run
    assert 'name = "SRE_CONTROL_PLANE_GITHUB_TOKEN"' in cloud_run
    assert "value_source" in cloud_run
    assert "google_secret_manager_secret.github_token.secret_id" in cloud_run
    assert "version = var.github_publication_credential_secret_version" in cloud_run
    assert 'resource "google_secret_manager_secret_iam_member" "control_plane_github_token"' in secrets
    assert "secret_data" not in source
    assert "google_secret_manager_secret_version" not in source


def test_broad_runtime_ignore_changes_are_not_used() -> None:
    source = terraform_source()

    assert "ignore_changes" not in source
    assert "ignore_changes = [\n      scaling,\n    ]" not in source
    assert "ignore_changes = [\n      retry_config,\n    ]" not in source


def test_scheduler_retry_policy_is_owned_as_api_normalized_zero_retries() -> None:
    scheduler = (TERRAFORM_ROOT / "scheduler.tf").read_text(encoding="utf-8")

    assert "retry_config {" not in scheduler
    assert "condition     = length(self.retry_config) == 0" in scheduler
    assert "API-normalized zero retries" in scheduler
    assert 'paused      = !var.scheduler_enabled' in scheduler
    assert "scheduler_activation_confirmed" in scheduler


def test_cloud_run_scaling_is_owned_and_bounded_without_broad_ignore() -> None:
    cloud_run = (TERRAFORM_ROOT / "cloud_run.tf").read_text(encoding="utf-8")
    variables = (TERRAFORM_ROOT / "variables.tf").read_text(encoding="utf-8")

    assert re.search(
        r'resource "google_cloud_run_v2_service" "control_plane" \{[\s\S]*?'
        r'\n  scaling \{\n    min_instance_count = 0\n    scaling_mode       = "AUTOMATIC"\n  \}',
        cloud_run,
    )
    assert 'scaling_mode       = "MANUAL"' not in cloud_run
    assert "max_instance_count = var.service_max_instances" in cloud_run
    assert 'self.scaling[0].scaling_mode == "AUTOMATIC"' in cloud_run
    assert "self.scaling[0].min_instance_count == 0" in cloud_run
    assert "self.scaling[0].manual_instance_count == 0" in cloud_run
    assert "ignore_changes" not in cloud_run
    assert "var.service_max_instances == 1" in variables


def test_unsafe_scaling_and_retry_drift_remain_detectable() -> None:
    source = terraform_source()

    assert "ignore_changes" not in source
    assert "Cloud Run service-level scaling must remain automatic" in source
    assert "Cloud Scheduler retry policy must remain API-normalized zero retries" in source
    assert 'scaling_mode       = "AUTOMATIC"' in source
    assert '"MANUAL"' not in source
    assert "manual_instance_count == 0" in source
    assert "length(self.retry_config) == 0" in source


def test_terraform_uses_private_durable_resources_without_secret_values() -> None:
    source = terraform_source()

    assert "google_sql_database_instance" in source
    assert 'edition                     = "ENTERPRISE"' in source
    assert "deletion_protection_enabled = var.deletion_protection" in source
    assert "google_artifact_registry_repository" in source
    assert "google_project_service" in source
    assert "ipv4_enabled    = false" in source
    assert "google_storage_bucket" in source
    assert 'name                        = "${var.project_id}-sre-cp-${var.environment}-evidence"' in source
    assert 'public_access_prevention    = "enforced"' in source
    assert "google_secret_manager_secret" in source
    assert "google_secret_manager_secret_version" not in source
    assert "secret_data" not in source
    assert 'depends_on = [google_project_service.required["secretmanager.googleapis.com"]]' in source
    assert "prevent_destroy = true" in source


def test_service_account_ids_fit_gcp_limits() -> None:
    source = terraform_source()

    assert 'control_plane_service_account_id = "sre-cp-${local.service_account_environment}-run"' in source
    assert 'scheduler_service_account_id     = "sre-cp-${local.service_account_environment}-sched"' in source
    assert "substr(var.environment, 0, 15)" in source
    assert 'account_id   = local.control_plane_service_account_id' in source
    assert 'account_id   = local.scheduler_service_account_id' in source
    assert len("sre-cp-" + ("x" * 15) + "-sched") <= 30


def test_fake_adapter_defaults_and_controlled_migration_job_are_present() -> None:
    source = terraform_source()
    cloud_run = (TERRAFORM_ROOT / "cloud_run.tf").read_text(encoding="utf-8")
    variables = (TERRAFORM_ROOT / "variables.tf").read_text(encoding="utf-8")
    locals_tf = (TERRAFORM_ROOT / "locals.tf").read_text(encoding="utf-8")

    assert 'default     = "fake"' in source
    assert 'contains(["fake", "sre_replay"], var.executor_mode)' in variables
    assert 'name  = "SRE_CONTROL_PLANE_EXECUTOR"' in cloud_run
    assert "value = var.executor_mode" in cloud_run
    assert 'var.executor_mode == "sre_replay"' in cloud_run
    assert 'name  = "SRE_CONTROL_PLANE_SRE_REPLAY_SCENARIO_ID"' in cloud_run
    assert 'name  = "SRE_CONTROL_PLANE_SRE_REPLAY_PROVIDERS_JSON"' in cloud_run
    assert "jsonencode(local.sre_replay_provider_declarations)" in cloud_run
    assert "approved-stage-frontend-slo-v1" in locals_tf
    assert "online-shop-stage" in locals_tf
    assert "slo:error_ratio_5m" in locals_tf
    assert "slo:burn_rate_5m" in locals_tf
    assert "read_file" in locals_tf
    assert "observe_status" in locals_tf
    assert "patch" not in locals_tf
    assert "delete" not in locals_tf
    assert "kubectl" not in cloud_run
    assert "prometheus-address" not in cloud_run
    assert "google_cloud_run_v2_job" in source
    assert 'command = ["alembic"]' in source
    assert 'args    = ["upgrade", "head"]' in source
    assert 'value = var.github_publisher_mode' in source
    assert "Runtime executor mode must be fake or the bounded fixture-backed SRE replay adapter." in source


def test_terraform_example_contains_only_placeholders() -> None:
    example = (TERRAFORM_ROOT / "terraform.tfvars.example").read_text(encoding="utf-8")
    runtime_example = (TERRAFORM_ROOT / "terraform.runtime.tfvars.example").read_text(
        encoding="utf-8"
    )

    assert "replace-with-reviewed-project-id" in example
    assert "sre-control-plane-staging/sre-control-plane@sha256:" in runtime_example
    assert "password" not in example.lower()
    assert "password" not in runtime_example.lower()
    assert "secret_data" not in runtime_example
    assert "SRE_CONTROL_PLANE_GITHUB_TOKEN" not in runtime_example
    assert "github_publisher_mode          = \"fake\"" in runtime_example
    assert "github_publication_credential_secret_version = null" in runtime_example


def test_remote_backend_targets_reviewed_state_bucket() -> None:
    backend = (TERRAFORM_ROOT / "backend.tf").read_text(encoding="utf-8")

    assert 'backend "gcs"' in backend
    assert 'bucket = "ai-operations-platform-507220-sre-control-plane-tfstate"' in backend
    assert 'prefix = "sre-control-plane/staging"' in backend
    assert "credentials" not in backend.lower()


def test_bootstrap_evidence_is_sanitized() -> None:
    evidence = (
        REPOSITORY_ROOT / "docs" / "deployments" / "gcp-sre-control-plane-bootstrap-2026-09-01.md"
    ).read_text(encoding="utf-8")
    forbidden_terms = [
        "@" + "gmail.com",
        ".iam." + "gserviceaccount.com",
        "gho" + "_",
        "ya29" + ".",
        "-----" + "BEGIN",
        "private" + "_key",
        "client" + "_secret",
        "bootstrap.tfplan",
    ]

    for term in forbidden_terms:
        assert term not in evidence

    assert "Operator identity verified" in evidence
    assert "Public principals: no `allUsers` or `allAuthenticatedUsers`" in evidence
    assert "Estimated steady-state range" in evidence


def test_runtime_evidence_is_sanitized_and_records_private_fake_runtime() -> None:
    evidence = (
        REPOSITORY_ROOT / "docs" / "deployments" / "gcp-sre-control-plane-runtime-2026-09-01.md"
    ).read_text(encoding="utf-8")
    forbidden_terms = [
        "@" + "gmail.com",
        ".iam." + "gserviceaccount.com",
        "gho" + "_",
        "ya29" + ".",
        "-----" + "BEGIN",
        "private" + "_key",
        "client" + "_secret",
        "runtime" + ".tfplan",
        "postgresql" + "://",
    ]

    for term in forbidden_terms:
        assert term not in evidence

    assert "Target project: `ai-operations-platform-507220`" in evidence
    assert "Target region: `us-central1`" in evidence
    assert "Runtime mode: fake executor and fake publisher only" in evidence
    assert "Cloud Run public invokers: zero" in evidence
    assert "Scheduler job state: `PAUSED`" in evidence
    assert "Database URL secret version recorded in runtime configuration: `1`" in evidence
    assert "secret values" in evidence.lower()
    assert "No Kubernetes cluster was accessed." in evidence


def test_gcs_evidence_adapter_evidence_is_sanitized_and_gated() -> None:
    evidence = (
        REPOSITORY_ROOT
        / "docs"
        / "deployments"
        / "gcp-sre-control-plane-gcs-evidence-adapter-2026-09-02.md"
    ).read_text(encoding="utf-8")
    forbidden_terms = [
        "@" + "gmail.com",
        ".iam." + "gserviceaccount.com",
        "gho" + "_",
        "ya29" + ".",
        "-----" + "BEGIN",
        "private" + "_key",
        "client" + "_secret",
        "postgresql" + "://",
    ]

    for term in forbidden_terms:
        assert term not in evidence

    assert "GitHub issue: #51" in evidence
    assert "Target project: `ai-operations-platform-507220`" in evidence
    assert "Target region: `us-central1`" in evidence
    assert "PostgreSQL remains the source of truth" in evidence
    assert "generation precondition `0`" in evidence
    assert "roles/storage.objectCreator" in evidence
    assert "roles/storage.objectViewer" in evidence
    assert "Cloud SQL continues" in evidence
    assert "charges while the instance is running" in evidence
    assert "No Kubernetes cluster was accessed." in evidence


def test_sre_replay_executor_evidence_is_sanitized_and_honest() -> None:
    evidence = (
        REPOSITORY_ROOT
        / "docs"
        / "deployments"
        / "gcp-sre-control-plane-sre-replay-executor-2026-09-04.md"
    ).read_text(encoding="utf-8")
    forbidden_terms = [
        "@" + "gmail.com",
        ".iam." + "gserviceaccount.com",
        "gho" + "_",
        "ya29" + ".",
        "-----" + "BEGIN",
        "private" + "_key",
        "client" + "_secret",
        "postgresql" + "://",
        ".tfplan",
        ".tfstate",
    ]

    for term in forbidden_terms:
        assert term not in evidence

    assert "GitHub issue: #55" in evidence
    assert "Target project context: `ai-operations-platform-507220`" in evidence
    assert "Runtime executor default: fake executor" in evidence
    assert "New executor mode: `sre_replay`, explicit opt-in only" in evidence
    assert "fixture-only limitations" in evidence
    assert "No live Kubernetes, Prometheus, Argo CD, recovery, HolmesGPT, or model call" in evidence
    assert "No SRE Platform repository file was modified." in evidence


def test_sre_platform_staging_readiness_boundary_is_bounded_and_complete() -> None:
    readiness = (
        REPOSITORY_ROOT
        / "docs"
        / "integrations"
        / "sre"
        / "sre-platform-staging-deployment-readiness.md"
    ).read_text(encoding="utf-8")

    required_terms = [
        "Planning and readiness only for Issue #57",
        "No SRE Platform GCP project has been created",
        "project id pattern: `sre-platform-staging-<reviewed-suffix>`",
        "primary region: `us-central1`",
        "Required APIs",
        "Terraform Remote State Boundary",
        "IAM And Operator Model",
        "Budget And Cost Guardrails",
        "Approval Gates For Future Work",
        "Rollback And Cleanup Expectations",
        "Kubernetes staging environment",
        "Argo CD controller and root application",
        "Argo Rollouts controller",
        "Online Boutique staging workload",
        "Prometheus/kube-prometheus-stack",
        "controlled failure path `/stage/break`",
        "read-only investigation service account and RBAC",
        "Kubernetes workload, pod, service, ingress, event, rollout, and AnalysisRun",
        "Prometheus instant or range query results",
        "GitOps repository files and commit references",
        "Argo CD application status for `online-shop-stage`",
        "No GCP project was created.",
        "No cloud write was performed.",
        "No Terraform plan or apply was performed.",
        "No Kubernetes cluster was accessed.",
        "No SRE Platform repository file was modified.",
    ]

    for term in required_terms:
        assert term in readiness

    forbidden_actions = [
        "create, delete, patch, scale, restart, or exec into Kubernetes resources",
        "apply Kubernetes manifests",
        "run Helm, Argo CD sync, Argo Rollouts promote, abort, retry, or undo actions",
        "start or stop baseline traffic or controlled failure traffic",
        "change GitOps configuration",
        "read Kubernetes secrets or secret values",
    ]
    for action in forbidden_actions:
        assert action in readiness

    forbidden_sensitive_markers = [
        "@" + "gmail.com",
        ".iam." + "gserviceaccount.com",
        "gho" + "_",
        "ghp" + "_",
        "ya29" + ".",
        "-----" + "BEGIN",
        "private" + "_key",
        "client" + "_secret",
        "postgresql" + "://",
        ".tfstate",
        ".tfplan",
    ]
    for marker in forbidden_sensitive_markers:
        assert marker not in readiness


def test_roadmap_records_sre_readiness_without_claiming_live_validation() -> None:
    roadmap = (REPOSITORY_ROOT / "docs" / "roadmap.md").read_text(encoding="utf-8")

    assert "Bounded SRE replay executor" in roadmap
    assert "SRE Platform staging readiness and cost bootstrap boundary" in roadmap
    assert "logging/monitoring as a first-class cost risk" in roadmap
    assert "`sre_replay` is explicit opt-in and fixture-backed only" in roadmap
    assert "No SRE Platform GCP project has been created" in roadmap
    assert "no cloud write or Terraform apply was performed" in roadmap
    assert "no cluster was accessed" in roadmap
    assert "no live staging validation is claimed" in roadmap
    assert "**Create the SRE Platform staging deployment issue**" in roadmap
    assert "budget ceiling, remote-state design" in roadmap
    assert "read-only preflight, exact approval gates" in roadmap
    assert "creating an SRE Platform GCP project or live staging deployment before a" in roadmap


def test_sre_platform_cost_bounded_bootstrap_plan_controls_observability_cost() -> None:
    plan = (
        REPOSITORY_ROOT
        / "docs"
        / "integrations"
        / "sre"
        / "sre-platform-staging-gcp-cost-bounded-bootstrap-plan.md"
    ).read_text(encoding="utf-8")

    required_terms = [
        "Planning and preflight package for Issue #59",
        "previous SRE Platform deployment cost risk",
        "cluster cost and logging/monitoring ingestion or retention",
        "project id candidate: `sre-platform-staging-507220`",
        "display name candidate: `sre-platform-staging`",
        "region: `us-central1`",
        "preferred initial zone: `us-central1-b`",
        "Cloud Billing Budget API",
        "Terraform Remote-State Design",
        "IAM And Operator Model",
        "Resource Groups",
        "Observability Cost Controls",
        "Logging Strategy",
        "Metrics And Prometheus Strategy",
        "Demo Window Controls",
        "Idle Behavior",
        "Category-Level Cost Estimate",
        "Observability Stop Conditions",
        "Approval Gates",
        "Rollback And Cleanup Path",
        "No GCP project was created.",
        "No Terraform plan or apply was performed.",
        "No `DimitryZH/sre-platform` file was modified.",
    ]
    for term in required_terms:
        assert term in plan

    observability_controls = [
        "log exclusions or filters must exist before noisy workloads run",
        "log retention must be short and explicit",
        "duplicate log routing must be absent",
        "Prometheus retention time and size must be bounded",
        "scrape targets must be limited",
        "managed Prometheus ingestion must be disabled unless",
        "demo traffic and failure traffic must be time-boxed",
        "if observability cost is unbounded, unclear, or above the approved",
    ]
    for control in observability_controls:
        assert control in plan

    cost_categories = [
        "GKE cluster management",
        "Node pools",
        "Persistent disks",
        "Load balancer / ingress",
        "Cloud NAT",
        "Cloud Logging ingestion and retention",
        "Cloud Monitoring and Prometheus",
        "Artifact Registry",
        "Evidence storage",
    ]
    for category in cost_categories:
        assert category in plan

    approval_gates = [
        "project creation or billing linkage",
        "API enablement",
        "budget alert creation",
        "remote-state bucket creation",
        "IAM changes",
        "exact saved Terraform plan apply",
        "Kubernetes cluster or node-pool creation",
        "logging or monitoring configuration",
        "SRE Platform workload or GitOps deployment",
    ]
    for gate in approval_gates:
        assert gate in plan


def test_sre_platform_bootstrap_preflight_evidence_is_sanitized_and_honest() -> None:
    evidence = (
        REPOSITORY_ROOT
        / "docs"
        / "deployments"
        / "sre-platform-staging-gcp-bootstrap-preflight-2026-09-05.md"
    ).read_text(encoding="utf-8")

    required_terms = [
        "Sanitized read-only preflight for Issue #59",
        "local default configured project: `ai-operations-platform-497515`",
        "target AI Operations project explicitly checked:",
        "`ai-operations-platform-507220`",
        "target AI Operations project lifecycle: active",
        "target AI Operations project billing enabled: yes",
        "Cloud Run ingress annotation: internal",
        "Scheduler state: `PAUSED`",
        "E2_CPUS",
        "proposed project id: `sre-platform-staging-507220`",
        "current account visibility for proposed project id: not visible",
        "local repository status: clean on `main` tracking `origin/main`",
        "staging namespace: `online-shop-stage`",
        "stage GitOps application: `online-shop-stage`",
        "controlled failure path: `/stage/break`",
        "logging and monitoring must be treated as a first-class cost risk",
        "No GCP project was created.",
        "No API was enabled.",
        "No remote-state bucket was created.",
        "No IAM binding was changed.",
        "No Terraform plan or apply was performed.",
        "No Kubernetes cluster was accessed.",
        "No `DimitryZH/sre-platform` file was modified.",
    ]
    for term in required_terms:
        assert term in evidence

    forbidden_sensitive_markers = [
        "@" + "gmail.com",
        ".iam." + "gserviceaccount.com",
        "gho" + "_",
        "ghp" + "_",
        "ya29" + ".",
        "-----" + "BEGIN",
        "private" + "_key",
        "client" + "_secret",
        "postgresql" + "://",
        ".tfstate",
        ".tfplan",
        "kube" + "config",
        "billingAccounts/",
    ]
    for marker in forbidden_sensitive_markers:
        assert marker not in evidence


def test_runbook_requires_staged_bootstrap_and_gates_scheduler_activation() -> None:
    runbook = (REPOSITORY_ROOT / "gcp" / "sre-control-plane" / "README.md").read_text(encoding="utf-8")

    assert "**Remote-state bucket phase:**" in runbook
    assert "--uniform-bucket-level-access" in runbook
    assert "--public-access-prevention" in runbook
    assert "--versioning" in runbook
    assert "--soft-delete-duration=30d" in runbook
    assert "Do not set a bucket retention policy" in runbook
    assert "**Bootstrap phase:**" in runbook
    assert "**Out-of-band secret phase:**" in runbook
    assert "**Image phase:**" in runbook
    assert "**Runtime phase:**" in runbook
    assert "**Evidence adapter phase:**" in runbook
    assert "SRE_CONTROL_PLANE_EVIDENCE_STORE=gcs" in runbook
    assert "roles/storage.objectCreator" in runbook
    assert "roles/storage.objectViewer" in runbook
    assert "Evidence Smoke Boundary" in runbook
    assert "scheduler_activation_confirmed = true" in runbook
    assert "migration job succeeded and readiness was verified" in runbook
    assert "external operator workstation" in runbook
    assert "gcp-sre-control-plane-runtime-2026-09-01.md" in runbook
