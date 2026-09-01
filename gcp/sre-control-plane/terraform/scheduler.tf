resource "google_cloud_scheduler_job" "dispatch_tick" {
  count       = var.deployment_phase == "runtime" ? 1 : 0
  name        = "${local.resource_name}-dispatch-tick"
  description = "Authenticated short reconciliation and dispatch tick; it is not a long-running worker."
  region      = var.region
  schedule    = var.scheduler_schedule
  time_zone   = var.scheduler_time_zone
  paused      = !var.scheduler_enabled

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.control_plane[0].uri}/internal/dispatch/tick"
    body        = base64encode(jsonencode({ lease_owner = var.scheduler_lease_owner }))

    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = google_service_account.scheduler.email
      audience              = google_cloud_run_v2_service.control_plane[0].uri
    }
  }

  lifecycle {
    precondition {
      condition     = !var.scheduler_enabled || var.scheduler_activation_confirmed
      error_message = "Scheduler activation requires explicit confirmation after migration and authenticated readiness verification."
    }

    postcondition {
      condition     = length(self.retry_config) == 0
      error_message = "Cloud Scheduler retry policy must remain API-normalized zero retries with no retry_config block."
    }
  }

  depends_on = [google_cloud_run_v2_service_iam_member.scheduler_invoker]
}
