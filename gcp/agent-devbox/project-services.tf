resource "google_project_service" "required" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry" {
  for_each = var.artifact_registry_reader_enabled ? toset(["artifactregistry.googleapis.com"]) : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
