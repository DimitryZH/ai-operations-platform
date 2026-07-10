resource "google_compute_network" "openclaw" {
  count = var.create_network ? 1 : 0

  project                 = var.project_id
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "openclaw" {
  count = var.create_network ? 1 : 0

  project                  = var.project_id
  name                     = "${var.name_prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.openclaw[0].id
  ip_cidr_range            = var.subnetwork_cidr
  private_ip_google_access = true
}

resource "google_compute_router" "openclaw" {
  count = var.create_cloud_nat ? 1 : 0

  project = var.project_id
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = local.network_self_link
}

resource "google_compute_router_nat" "openclaw" {
  count = var.create_cloud_nat ? 1 : 0

  project                            = var.project_id
  name                               = "${var.name_prefix}-nat"
  region                             = var.region
  router                             = google_compute_router.openclaw[0].name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = local.subnetwork_self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_firewall" "iap_ssh" {
  project = var.project_id
  name    = "${var.name_prefix}-iap-ssh"
  network = local.network_self_link

  description             = "Allow SSH only through IAP TCP forwarding."
  direction               = "INGRESS"
  source_ranges           = ["35.235.240.0/20"]
  target_service_accounts = [google_service_account.openclaw.email]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "iap_gateway" {
  project = var.project_id
  name    = "${var.name_prefix}-iap-gateway"
  network = local.network_self_link

  description             = "Allow the private OpenClaw gateway port only through IAP TCP forwarding."
  direction               = "INGRESS"
  source_ranges           = ["35.235.240.0/20"]
  target_service_accounts = [google_service_account.openclaw.email]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.openclaw_port)]
  }
}

resource "google_compute_firewall" "health_checks" {
  project = var.project_id
  name    = "${var.name_prefix}-health-checks"
  network = local.network_self_link

  description             = "Allow Google Cloud health check probes to the private OpenClaw gateway port."
  direction               = "INGRESS"
  source_ranges           = ["35.191.0.0/16", "130.211.0.0/22"]
  target_service_accounts = [google_service_account.openclaw.email]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.openclaw_port)]
  }
}
