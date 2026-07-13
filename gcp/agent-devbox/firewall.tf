resource "google_compute_firewall" "iap_ssh" {
  project = var.project_id
  name    = "${var.name_prefix}-iap-ssh"
  network = google_compute_network.devbox.name

  description             = "Allow SSH only through IAP TCP forwarding."
  direction               = "INGRESS"
  source_ranges           = ["35.235.240.0/20"]
  target_service_accounts = [google_service_account.devbox.email]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
