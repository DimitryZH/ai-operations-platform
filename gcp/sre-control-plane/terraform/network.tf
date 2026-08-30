resource "google_compute_network" "control_plane" {
  name                    = "${local.resource_name}-network"
  auto_create_subnetworks = false
  description             = "Dedicated private network for the bounded SRE control-plane MVP."

  depends_on = [google_project_service.required["compute.googleapis.com"]]
}

resource "google_compute_subnetwork" "control_plane" {
  name                     = "${local.resource_name}-subnet"
  region                   = var.region
  network                  = google_compute_network.control_plane.id
  ip_cidr_range            = "10.60.0.0/24"
  private_ip_google_access = true
}

resource "google_compute_global_address" "private_service_access" {
  name          = "${local.resource_name}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.control_plane.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.control_plane.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]

  depends_on = [google_project_service.required["servicenetworking.googleapis.com"]]
}
