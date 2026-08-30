output "cloud_run_service_name" {
  value       = try(google_cloud_run_v2_service.control_plane[0].name, null)
  description = "Private Cloud Run service name. No public invoker is granted."
}

output "migration_job_name" {
  value       = try(google_cloud_run_v2_job.migrate[0].name, null)
  description = "Controlled migration job name; execute only after reviewed deployment approval."
}

output "evidence_bucket_name" {
  value       = google_storage_bucket.evidence.name
  description = "Private evidence bucket name."
}

output "database_secret_id" {
  value       = google_secret_manager_secret.database_url.secret_id
  description = "Secret container ID only; Terraform never manages the secret value."
}
