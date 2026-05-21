output "artifact_registry_repository_name" {
  description = "Artifact Registry repository name."
  value       = google_artifact_registry_repository.runtime.name
}

output "artifact_registry_repository_url" {
  description = "Base URL for pushing images to Artifact Registry."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.runtime.repository_id}"
}

output "runtime_service_account_email" {
  description = "Email of the dedicated Cloud Run runtime service account."
  value       = google_service_account.runtime.email
}

output "runtime_secret_resource" {
  description = "Secret Manager resource ID used for runtime configuration."
  value       = google_secret_manager_secret.runtime_config.id
}

output "cloud_run_service_name" {
  description = "Cloud Run service name."
  value       = google_cloud_run_v2_service.runtime.name
}

output "cloud_run_service_uri" {
  description = "Cloud Run service URL."
  value       = google_cloud_run_v2_service.runtime.uri
}

output "cloud_run_is_public" {
  description = "Whether unauthenticated invoker access is enabled."
  value       = var.allow_unauthenticated
}
