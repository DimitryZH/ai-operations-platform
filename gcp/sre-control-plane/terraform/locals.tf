locals {
  resource_name = "${var.name_prefix}-${var.environment}"
  labels = {
    application = "sre-control-plane"
    environment = var.environment
    managed_by  = "terraform"
  }
  database_secret_id = "${local.resource_name}-database-url"
}
