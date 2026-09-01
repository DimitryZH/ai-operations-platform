from __future__ import annotations

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


def test_runtime_requires_explicit_database_secret_version_and_pauses_scheduler() -> None:
    source = terraform_source()

    assert 'variable "database_secret_version"' in source
    assert 'version = var.database_secret_version' in source
    assert 'version = "latest"' not in source
    assert 'paused      = !var.scheduler_enabled' in source
    assert "scheduler_activation_confirmed" in source


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

    assert 'default     = "fake"' in source
    assert "google_cloud_run_v2_job" in source
    assert 'command = ["alembic"]' in source
    assert 'args    = ["upgrade", "head"]' in source


def test_terraform_example_contains_only_placeholders() -> None:
    example = (TERRAFORM_ROOT / "terraform.tfvars.example").read_text(encoding="utf-8")

    assert "replace-with-reviewed-project-id" in example
    assert "token" not in example.lower()
    assert "password" not in example.lower()


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
    assert "scheduler_activation_confirmed = true" in runbook
    assert "migration job succeeded and readiness was verified" in runbook
    assert "external operator workstation" in runbook
