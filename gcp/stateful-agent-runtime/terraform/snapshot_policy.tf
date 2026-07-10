resource "google_compute_resource_policy" "daily_state_snapshot_standard" {
  project     = var.project_id
  name        = "${var.name_prefix}-daily-snapshot-standard"
  region      = var.region
  description = "Daily prototype snapshots for the authoritative OpenClaw state disk."

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = var.snapshot_start_time_utc
      }
    }

    retention_policy {
      max_retention_days    = var.snapshot_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      guest_flush       = false
      labels            = local.labels
      storage_locations = var.snapshot_storage_locations
    }
  }
}
