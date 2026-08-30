resource "google_cloud_scheduler_job" "dispatch_tick" {
  name        = "${local.resource_name}-dispatch-tick"
  description = "Authenticated short reconciliation and dispatch tick; it is not a long-running worker."
  region      = var.region
  schedule    = var.scheduler_schedule
  time_zone   = var.scheduler_time_zone

  retry_config {
    retry_count = 0
  }

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.control_plane.uri}/internal/dispatch/tick"
    body        = base64encode(jsonencode({ lease_owner = var.scheduler_lease_owner }))

    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = google_service_account.scheduler.email
      audience              = google_cloud_run_v2_service.control_plane.uri
    }
  }

  depends_on = [google_cloud_run_v2_service_iam_member.scheduler_invoker]
}
