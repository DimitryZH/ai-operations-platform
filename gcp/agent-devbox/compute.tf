resource "google_compute_instance" "devbox" {
  project      = var.project_id
  name         = var.name_prefix
  zone         = var.zone
  machine_type = var.machine_type

  allow_stopping_for_update = true
  can_ip_forward            = false
  deletion_protection       = var.deletion_protection
  labels                    = local.labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image = "projects/${var.source_image_project}/global/images/family/${var.source_image_family}"
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.devbox.id
  }

  metadata = {
    block-project-ssh-keys = "TRUE"
    enable-oslogin         = "TRUE"
    serial-port-enable     = "FALSE"
  }

  metadata_startup_script = local.startup_script

  service_account {
    email  = google_service_account.devbox.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = var.enable_secure_boot
    enable_vtpm                 = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }

  depends_on = [
    google_compute_router_nat.devbox,
    google_project_iam_member.observability,
    google_secret_manager_secret_iam_member.named_secret_accessor,
  ]
}
