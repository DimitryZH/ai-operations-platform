resource "google_cloud_run_v2_service" "control_plane" {
  count    = var.deployment_phase == "runtime" ? 1 : 0
  name     = local.resource_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  labels   = local.labels

  scaling {
    min_instance_count = 0
    scaling_mode       = "AUTOMATIC"
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

      env {
        name  = "SRE_CONTROL_PLANE_EXECUTOR"
        value = var.executor_mode
      }

      dynamic "env" {
        for_each = var.executor_mode == "sre_replay" ? [1] : []
        content {
          name  = "SRE_CONTROL_PLANE_SRE_REPLAY_SCENARIO_ID"
          value = local.sre_replay_provider_declarations.scenario_id
        }
      }

      dynamic "env" {
        for_each = var.executor_mode == "sre_replay" ? [1] : []
        content {
          name  = "SRE_CONTROL_PLANE_SRE_REPLAY_PROVIDERS_JSON"
          value = jsonencode(local.sre_replay_provider_declarations)
        }
      }

      env {
        name  = "SRE_CONTROL_PLANE_EVIDENCE_STORE"
        value = "gcs"
      }

      env {
        name  = "SRE_CONTROL_PLANE_GCS_PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "SRE_CONTROL_PLANE_EVIDENCE_BUCKET"
        value = google_storage_bucket.evidence.name
      }

      env {
        name  = "SRE_CONTROL_PLANE_PUBLISHER"
        value = var.github_publisher_mode
      }

      dynamic "env" {
        for_each = var.github_publisher_mode == "github" ? [1] : []
        content {
          name  = "SRE_CONTROL_PLANE_GITHUB_REPOSITORY"
          value = var.github_publication_repository
        }
      }

      dynamic "env" {
        for_each = var.github_publisher_mode == "github" ? [1] : []
        content {
          name  = "SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER"
          value = tostring(var.github_publication_issue_number)
        }
      }

      dynamic "env" {
        for_each = var.github_publisher_mode == "github" ? [1] : []
        content {
          name  = "SRE_CONTROL_PLANE_GITHUB_ALLOWED_REPOSITORY"
          value = var.github_publication_allowed_repository
        }
      }

      dynamic "env" {
        for_each = var.github_publisher_mode == "github" ? [1] : []
        content {
          name  = "SRE_CONTROL_PLANE_GITHUB_ALLOWED_ISSUE_NUMBER"
          value = tostring(var.github_publication_allowed_issue_number)
        }
      }

      dynamic "env" {
        for_each = var.github_publisher_mode == "github" ? [1] : []
        content {
          name  = "SRE_CONTROL_PLANE_GITHUB_CREDENTIAL_SECRET_NAME"
          value = google_secret_manager_secret.github_token.secret_id
        }
      }

      dynamic "env" {
        for_each = var.github_publisher_mode == "github" ? [1] : []
        content {
          name  = "SRE_CONTROL_PLANE_GITHUB_CREDENTIAL_SECRET_VERSION"
          value = var.github_publication_credential_secret_version
        }
      }

      dynamic "env" {
        for_each = var.github_publisher_mode == "github" ? [1] : []
        content {
          name = "SRE_CONTROL_PLANE_GITHUB_TOKEN"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.github_token.secret_id
              version = var.github_publication_credential_secret_version
            }
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
      condition     = contains(["fake", "sre_replay"], var.executor_mode)
      error_message = "Runtime executor mode must be fake or the bounded fixture-backed SRE replay adapter."
    }

    precondition {
      condition     = var.container_image != null && var.database_secret_version != null
      error_message = "runtime deployment requires an immutable container_image and an explicit database_secret_version."
    }

    precondition {
      condition = (
        var.github_publisher_mode == "fake" || (
          var.github_publication_repository != null
          && var.github_publication_issue_number != null
          && var.github_publication_allowed_repository != null
          && var.github_publication_allowed_issue_number != null
          && var.github_publication_credential_secret_version != null
          && var.github_publication_repository == var.github_publication_allowed_repository
          && var.github_publication_issue_number == var.github_publication_allowed_issue_number
        )
      )
      error_message = "GitHub publisher mode requires an explicit matching repository/issue allowlist and credential Secret Manager version."
    }

    precondition {
      condition = (
        var.github_publisher_mode == "github"
        || (
          var.github_publication_repository == null
          && var.github_publication_issue_number == null
          && var.github_publication_allowed_repository == null
          && var.github_publication_allowed_issue_number == null
          && var.github_publication_credential_secret_version == null
        )
      )
      error_message = "GitHub publication target and credential references must not be configured while publisher mode is fake."
    }

    postcondition {
      condition     = self.scaling[0].scaling_mode == "AUTOMATIC" && self.scaling[0].min_instance_count == 0 && self.scaling[0].manual_instance_count == 0
      error_message = "Cloud Run service-level scaling must remain automatic with zero minimum and zero manual instances."
    }
  }

  depends_on = [
    google_project_iam_member.control_plane_cloud_sql,
    google_secret_manager_secret_iam_member.control_plane_database_url,
    google_secret_manager_secret_iam_member.control_plane_github_token,
    google_storage_bucket_iam_member.control_plane_evidence_creator,
    google_storage_bucket_iam_member.control_plane_evidence_viewer,
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
