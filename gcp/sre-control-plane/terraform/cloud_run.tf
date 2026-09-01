resource "google_cloud_run_v2_service" "control_plane" {
  count    = var.deployment_phase == "runtime" ? 1 : 0
  name     = local.resource_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  labels   = local.labels

  scaling {
    min_instance_count = 0
  }

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
            version = var.database_secret_version
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

    precondition {
      condition     = var.container_image != null && var.database_secret_version != null
      error_message = "runtime deployment requires an immutable container_image and an explicit database_secret_version."
    }

    postcondition {
      condition     = self.scaling[0].min_instance_count == 0 && self.scaling[0].manual_instance_count == 0
      error_message = "Cloud Run service-level scaling must remain automatic with zero minimum and zero manual instances."
    }
  }

  depends_on = [
    google_project_iam_member.control_plane_cloud_sql,
    google_secret_manager_secret_iam_member.control_plane_database_url,
  ]
}

resource "google_cloud_run_v2_job" "migrate" {
  count    = var.deployment_phase == "runtime" ? 1 : 0
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
              version = var.database_secret_version
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
  count    = var.deployment_phase == "runtime" ? 1 : 0
  name     = google_cloud_run_v2_service.control_plane[0].name
  location = google_cloud_run_v2_service.control_plane[0].location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}
