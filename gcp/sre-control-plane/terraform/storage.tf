resource "google_storage_bucket" "evidence" {
  name                        = "${var.project_id}-${local.resource_name}-evidence"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = local.labels

  versioning {
    enabled = true
  }

  retention_policy {
    retention_period = var.evidence_retention_days * 86400
    is_locked        = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_storage_bucket_iam_member" "control_plane_evidence_writer" {
  bucket = google_storage_bucket.evidence.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.control_plane.email}"
}
