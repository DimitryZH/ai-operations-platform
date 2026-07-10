variable "monitoring_alerts_enabled" {
  description = "Enable Cloud Monitoring alert policies for the Stateful VM runtime."
  type        = bool
  default     = false
}

variable "monitoring_notification_channel_ids" {
  description = "Existing Cloud Monitoring notification channel IDs to attach to future alert policies."
  type        = list(string)
  default     = []
  sensitive   = true
}

locals {
  monitoring_alert_display_name_prefix = "${var.name_prefix} Stateful VM"

  monitoring_monitored_resource_labels = {
    project_id          = var.project_id
    zone                = var.zone
    instance_group_name = "${var.name_prefix}-mig"
    state_disk_name     = "${var.name_prefix}-state"
  }

  monitoring_future_alert_candidates = {
    openclaw_service = {
      display_name = "${local.monitoring_alert_display_name_prefix} OpenClaw service failure"
      severity     = "critical"
    }
    mig_health = {
      display_name = "${local.monitoring_alert_display_name_prefix} MIG unhealthy"
      severity     = "critical"
    }
    state_disk_capacity = {
      display_name = "${local.monitoring_alert_display_name_prefix} state disk capacity"
      severity     = "warning"
    }
    snapshot_freshness = {
      display_name = "${local.monitoring_alert_display_name_prefix} snapshot freshness"
      severity     = "critical"
    }
  }
}

# This file is intentionally a no-resource monitoring skeleton.
# Do not add google_monitoring_alert_policy or
# google_monitoring_notification_channel resources until a later approved
# change has confirmed signal safety and alert routing.
# Future alert policies should use existing notification channel IDs supplied
# through monitoring_notification_channel_ids after routing ownership is
# explicitly approved.

check "monitoring_alerts_require_notification_channels" {
  assert {
    condition     = !var.monitoring_alerts_enabled || length(var.monitoring_notification_channel_ids) > 0
    error_message = "monitoring_notification_channel_ids must be set before enabling monitoring alerts."
  }
}
