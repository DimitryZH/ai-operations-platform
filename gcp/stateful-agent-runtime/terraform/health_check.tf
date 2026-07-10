resource "google_compute_health_check" "openclaw" {
  project = var.project_id
  name    = "${var.name_prefix}-health"

  description         = "Conservative OpenClaw autohealing signal. Keep TCP until HTTP readiness is proven stable."
  check_interval_sec  = 30
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 5

  dynamic "tcp_health_check" {
    for_each = var.health_check_mode == "TCP" ? [1] : []

    content {
      port = var.openclaw_port
    }
  }

  dynamic "http_health_check" {
    for_each = var.health_check_mode == "HTTP" ? [1] : []

    content {
      port         = var.openclaw_port
      request_path = var.health_check_request_path
    }
  }
}
