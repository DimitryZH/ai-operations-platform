resource "google_service_account" "devbox" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Agent DevBox experiment VM"
  description  = "Dedicated least-privilege identity for the disposable Agent DevBox experiment VM."
}

resource "google_project_iam_member" "observability" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.devbox.email}"
}

resource "google_secret_manager_secret_iam_member" "named_secret_accessor" {
  for_each = local.secret_access_bindings

  project   = each.value.project
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.devbox.email}"
}

resource "google_artifact_registry_repository_iam_member" "optional_reader" {
  for_each = var.artifact_registry_reader_enabled ? toset(["enabled"]) : toset([])

  project    = var.artifact_registry_project_id
  location   = var.artifact_registry_location
  repository = var.artifact_registry_repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.devbox.email}"
}

resource "google_project_iam_member" "operator_iap_tunnel" {
  for_each = local.operator_members

  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = each.value
}

resource "google_project_iam_member" "operator_os_login" {
  for_each = var.operator_iam_members

  project = var.project_id
  role    = "roles/compute.osLogin"
  member  = each.value
}

resource "google_project_iam_member" "admin_os_login" {
  for_each = var.admin_iam_members

  project = var.project_id
  role    = "roles/compute.osAdminLogin"
  member  = each.value
}
