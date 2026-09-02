resource "google_storage_bucket" "evidence" {
  name                        = "${var.project_id}-sre-cp-${var.environment}-evidence"
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

resource "google_storage_bucket_iam_member" "control_plane_evidence_creator" {
  bucket = google_storage_bucket.evidence.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.control_plane.email}"
}

resource "google_storage_bucket_iam_member" "control_plane_evidence_viewer" {
  bucket = google_storage_bucket.evidence.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.control_plane.email}"
}
