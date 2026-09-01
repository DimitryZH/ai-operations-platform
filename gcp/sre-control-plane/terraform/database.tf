resource "google_sql_database_instance" "control_plane" {
  name                = "${local.resource_name}-postgres"
  region              = var.region
  database_version    = var.cloud_sql_database_version
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.cloud_sql_tier
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.cloud_sql_disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.control_plane.id
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "control_plane" {
  name     = var.cloud_sql_database_name
  instance = google_sql_database_instance.control_plane.name
}
