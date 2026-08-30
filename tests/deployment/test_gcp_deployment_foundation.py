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
    assert "google_artifact_registry_repository" in source
    assert "google_project_service" in source
    assert "ipv4_enabled    = false" in source
    assert "google_storage_bucket" in source
    assert 'public_access_prevention    = "enforced"' in source
    assert "google_secret_manager_secret" in source
    assert "google_secret_manager_secret_version" not in source
    assert "secret_data" not in source
    assert "prevent_destroy = true" in source


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


def test_runbook_requires_staged_bootstrap_and_gates_scheduler_activation() -> None:
    runbook = (REPOSITORY_ROOT / "gcp" / "sre-control-plane" / "README.md").read_text(encoding="utf-8")

    assert "**Bootstrap phase:**" in runbook
    assert "**Out-of-band secret phase:**" in runbook
    assert "**Image phase:**" in runbook
    assert "**Runtime phase:**" in runbook
    assert "scheduler_activation_confirmed = true" in runbook
    assert "migration job succeeded and readiness was verified" in runbook
    assert "external operator workstation" in runbook
