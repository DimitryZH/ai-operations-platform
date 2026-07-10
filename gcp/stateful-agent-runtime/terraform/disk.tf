resource "google_compute_disk" "openclaw_state" {
  project = var.project_id
  name    = "${var.name_prefix}-state"
  zone    = var.zone
  type    = var.data_disk_type
  size    = var.data_disk_size_gb
  labels  = local.labels

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_compute_disk_resource_policy_attachment" "openclaw_state_snapshot" {
  project = var.project_id
  name    = google_compute_resource_policy.daily_state_snapshot_standard.name
  disk    = google_compute_disk.openclaw_state.name
  zone    = var.zone
}
