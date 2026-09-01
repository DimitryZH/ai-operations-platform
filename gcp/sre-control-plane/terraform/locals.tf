locals {
  resource_name                    = "${var.name_prefix}-${var.environment}"
  service_account_environment      = substr(var.environment, 0, 15)
  control_plane_service_account_id = "sre-cp-${local.service_account_environment}-run"
  scheduler_service_account_id     = "sre-cp-${local.service_account_environment}-sched"
  labels = {
    application = "sre-control-plane"
    environment = var.environment
    managed_by  = "terraform"
  }
  database_secret_id = "${local.resource_name}-database-url"
}
