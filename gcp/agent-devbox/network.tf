resource "google_compute_network" "devbox" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [
    google_project_service.required,
  ]
}

resource "google_compute_subnetwork" "devbox" {
  project                  = var.project_id
  name                     = var.subnet_name
  region                   = var.region
  network                  = google_compute_network.devbox.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_router" "devbox" {
  project = var.project_id
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.devbox.id
}

resource "google_compute_router_nat" "devbox" {
  project                            = var.project_id
  name                               = "${var.name_prefix}-nat"
  region                             = var.region
  router                             = google_compute_router.devbox.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.devbox.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
