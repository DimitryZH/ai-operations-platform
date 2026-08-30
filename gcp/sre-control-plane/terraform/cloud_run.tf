resource "google_cloud_run_v2_service" "control_plane" {
  name     = local.resource_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  labels   = local.labels

  template {
    service_account                  = google_service_account.control_plane.email
    timeout                          = "${var.service_timeout_seconds}s"
    max_instance_request_concurrency = var.service_concurrency

    scaling {
      min_instance_count = 0
      max_instance_count = var.service_max_instances
    }

    vpc_access {
      egress = "ALL_TRAFFIC"
      network_interfaces {
        network    = google_compute_network.control_plane.id
        subnetwork = google_compute_subnetwork.control_plane.id
      }
    }

    containers {
      image = var.container_image

      ports {
        container_port = 8080
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
          port = 8080
        }
        initial_delay_seconds = 5
        timeout_seconds       = 3
        period_seconds        = 10
        failure_threshold     = 6
      }

      liveness_probe {
        http_get {
          path = "/healthz"
          port = 8080
        }
        timeout_seconds   = 3
        period_seconds    = 30
        failure_threshold = 3
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.executor_mode == "fake" && var.github_publisher_mode == "fake"
      error_message = "This foundation deploys only fake adapters."
    }
  }

  depends_on = [
    google_project_iam_member.control_plane_cloud_sql,
    google_secret_manager_secret_iam_member.control_plane_database_url,
  ]
}

resource "google_cloud_run_v2_job" "migrate" {
  name     = "${local.resource_name}-migrate"
  location = var.region
  labels   = local.labels

  template {
    template {
      service_account = google_service_account.control_plane.email
      timeout         = "300s"
      max_retries     = 0

      vpc_access {
        egress = "ALL_TRAFFIC"
        network_interfaces {
          network    = google_compute_network.control_plane.id
          subnetwork = google_compute_subnetwork.control_plane.id
        }
      }

      containers {
        image   = var.container_image
        command = ["alembic"]
        args    = ["upgrade", "head"]

        env {
          name = "DATABASE_URL"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.database_url.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_project_iam_member.control_plane_cloud_sql,
    google_secret_manager_secret_iam_member.control_plane_database_url,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "scheduler_invoker" {
  name     = google_cloud_run_v2_service.control_plane.name
  location = google_cloud_run_v2_service.control_plane.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}
