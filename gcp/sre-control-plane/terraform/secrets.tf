resource "google_secret_manager_secret" "database_url" {
  secret_id = local.database_secret_id
  labels    = local.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret" "github_token" {
  secret_id = "${local.resource_name}-github-token"
  labels    = local.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret" "executor_config" {
  secret_id = "${local.resource_name}-executor-config"
  labels    = local.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret_iam_member" "control_plane_database_url" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.control_plane.email}"
}

# Terraform creates secret containers only; it never creates a secret version or value.
