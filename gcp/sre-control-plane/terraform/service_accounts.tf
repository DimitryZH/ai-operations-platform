resource "google_service_account" "control_plane" {
  account_id   = local.control_plane_service_account_id
  display_name = "SRE control-plane Cloud Run runtime"
}

resource "google_service_account" "scheduler" {
  account_id   = local.scheduler_service_account_id
  display_name = "SRE control-plane scheduler invoker"
}

resource "google_project_iam_member" "control_plane_cloud_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.control_plane.email}"
}

resource "google_project_iam_member" "control_plane_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.control_plane.email}"
}

resource "google_project_iam_member" "control_plane_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.control_plane.email}"
}
