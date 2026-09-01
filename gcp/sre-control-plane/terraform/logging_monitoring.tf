resource "google_logging_project_bucket_config" "control_plane" {
  project        = var.project_id
  location       = "global"
  bucket_id      = "${local.resource_name}-logs"
  retention_days = var.log_retention_days
}

resource "google_logging_project_sink" "control_plane" {
  name        = "${local.resource_name}-logs"
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.control_plane.id}"
  filter      = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.resource_name}\""
}

resource "google_monitoring_alert_policy" "cloud_run_errors" {
  display_name          = "${local.resource_name} Cloud Run 5xx errors"
  combiner              = "OR"
  notification_channels = var.alert_notification_channel_ids

  conditions {
    display_name = "Cloud Run 5xx responses"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.resource_name}\" AND metric.labels.response_code_class=\"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
}
