resource "google_compute_instance_group_manager" "openclaw" {
  project            = var.project_id
  name               = "${var.name_prefix}-mig"
  description        = "Zonal stateful MIG for exactly one OpenClaw gateway writer."
  base_instance_name = var.name_prefix
  zone               = var.zone
  target_size        = 1

  version {
    name              = "primary"
    instance_template = google_compute_instance_template.openclaw.self_link_unique
  }

  named_port {
    name = "openclaw"
    port = var.openclaw_port
  }

  stateful_disk {
    device_name = var.data_disk_device_name
    delete_rule = "NEVER"
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.openclaw.id
    initial_delay_sec = var.health_check_initial_delay_sec
  }

  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    replacement_method             = "RECREATE"
    max_surge_fixed                = 0
    max_unavailable_fixed          = 1
  }

  lifecycle {
    prevent_destroy = true
  }
}
