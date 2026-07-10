resource "google_compute_instance_template" "openclaw" {
  project      = var.project_id
  name_prefix  = "${var.name_prefix}-"
  description  = "Private single-writer OpenClaw VM template. The state disk is authoritative and preserved."
  machine_type = var.machine_type
  region       = var.region

  can_ip_forward = false
  labels         = local.labels

  disk {
    source_image = data.google_compute_image.ubuntu_lts.id
    auto_delete  = true
    boot         = true
    disk_type    = var.boot_disk_type
    disk_size_gb = var.boot_disk_size_gb
  }

  disk {
    source      = google_compute_disk.openclaw_state.name
    device_name = var.data_disk_device_name
    auto_delete = false
    boot        = false
    mode        = "READ_WRITE"
  }

  network_interface {
    subnetwork = local.subnetwork_self_link
  }

  metadata = {
    block-project-ssh-keys = "TRUE"
    enable-osconfig        = "TRUE"
    enable-oslogin         = "TRUE"
    serial-port-enable     = "FALSE"
  }

  metadata_startup_script = local.bootstrap_script

  service_account {
    email  = google_service_account.openclaw.email
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

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_artifact_registry_repository_iam_member.runtime_image_reader,
    google_compute_disk_resource_policy_attachment.openclaw_state_snapshot,
    google_project_iam_member.runtime_observability,
    google_secret_manager_secret_iam_member.runtime_secret_accessor,
  ]
}
