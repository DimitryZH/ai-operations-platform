provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  required_apis = toset([
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com"
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_apis

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "runtime" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_repository_id
  description   = "Container images for the Cloud Run AI runtime."
  format        = "DOCKER"

  labels = var.labels

  depends_on = [
    google_project_service.required["artifactregistry.googleapis.com"]
  ]
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = var.runtime_service_account_id
  display_name = "Cloud Run runtime identity"
  description  = "Dedicated identity for Cloud Run AI runtime revisions."
}

resource "google_secret_manager_secret" "runtime_config" {
  project   = var.project_id
  secret_id = var.runtime_secret_id

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [
    google_project_service.required["secretmanager.googleapis.com"]
  ]
}

resource "google_secret_manager_secret_version" "runtime_config_placeholder" {
  secret      = google_secret_manager_secret.runtime_config.id
  secret_data = var.runtime_secret_placeholder
}

resource "google_secret_manager_secret_iam_member" "runtime_secret_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.runtime_config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_cloud_run_v2_service" "runtime" {
  project  = var.project_id
  name     = var.cloud_run_service_name
  location = var.region
  ingress  = var.cloud_run_ingress

  deletion_protection = var.cloud_run_deletion_protection

  template {
    service_account = google_service_account.runtime.email
    timeout         = "${var.cloud_run_timeout_seconds}s"

    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }

    containers {
      image = var.cloud_run_container_image

      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }

      env {
        name = "AI_RUNTIME_CONFIG_JSON"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.runtime_config.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [
    google_project_service.required["run.googleapis.com"],
    google_secret_manager_secret_iam_member.runtime_secret_accessor
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.runtime.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
