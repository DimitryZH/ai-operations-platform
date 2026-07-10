resource "google_service_account" "openclaw" {
  project      = var.project_id
  account_id   = var.runtime_service_account_id
  display_name = "OpenClaw stateful VM runtime identity"
  description  = "Dedicated least-privilege identity for the single-writer OpenClaw stateful VM runtime."
}

resource "google_project_iam_member" "runtime_observability" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_artifact_registry_repository_iam_member" "runtime_image_reader" {
  project    = local.artifact_registry_project_id
  location   = var.artifact_registry_location
  repository = var.artifact_registry_repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_secret_manager_secret_iam_member" "runtime_secret_accessor" {
  for_each = local.runtime_secret_ids

  project   = local.secret_project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_project_iam_member" "operator_iap_tunnel" {
  for_each = local.iap_iam_members

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

resource "google_service_account_iam_member" "operator_service_account_user" {
  for_each = var.grant_operator_service_account_user ? local.iap_iam_members : toset([])

  service_account_id = google_service_account.openclaw.name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
