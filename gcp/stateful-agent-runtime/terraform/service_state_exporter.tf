variable "service_state_exporter_enabled" {
  description = "Enable deployment of the local service-state exporter systemd service and timer."
  type        = bool
  default     = false
}

variable "service_state_exporter_live_writes_enabled" {
  description = "Enable live Cloud Monitoring metric writes for the service-state exporter. Requires service_state_exporter_enabled."
  type        = bool
  default     = false
}

variable "service_state_exporter_schedule" {
  description = "Systemd OnCalendar schedule for the service-state exporter timer."
  type        = string
  default     = "*:0/5"

  validation {
    condition     = trimspace(var.service_state_exporter_schedule) != ""
    error_message = "service_state_exporter_schedule must not be empty."
  }
}

variable "service_state_exporter_metric_prefix" {
  description = "Cloud Monitoring custom metric prefix for service-state metrics."
  type        = string
  default     = "custom.googleapis.com/openclaw/service_state"

  validation {
    condition = (
      startswith(var.service_state_exporter_metric_prefix, "custom.googleapis.com/") &&
      !can(regex("\\s", var.service_state_exporter_metric_prefix))
    )
    error_message = "service_state_exporter_metric_prefix must start with custom.googleapis.com/ and contain no whitespace."
  }
}

variable "service_state_exporter_working_directory" {
  description = "Working directory expected to contain the local monitoring helper package during a future approved rollout."
  type        = string
  default     = "/opt/openclaw-service-state-exporter"

  validation {
    condition     = startswith(var.service_state_exporter_working_directory, "/")
    error_message = "service_state_exporter_working_directory must be an absolute path."
  }
}

variable "service_state_exporter_user" {
  description = "Local low-privilege user for the future service-state exporter systemd service."
  type        = string
  default     = "openclaw-monitoring"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*[$]?$", var.service_state_exporter_user))
    error_message = "service_state_exporter_user must be a valid Linux user name."
  }
}

variable "service_state_exporter_group" {
  description = "Local low-privilege group for the future service-state exporter systemd service."
  type        = string
  default     = "openclaw-monitoring"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*[$]?$", var.service_state_exporter_group))
    error_message = "service_state_exporter_group must be a valid Linux group name."
  }
}

variable "service_state_exporter_randomized_delay_seconds" {
  description = "Systemd timer randomized delay in seconds for the future service-state exporter."
  type        = number
  default     = 30

  validation {
    condition     = var.service_state_exporter_randomized_delay_seconds >= 0 && var.service_state_exporter_randomized_delay_seconds <= 300
    error_message = "service_state_exporter_randomized_delay_seconds must be between 0 and 300."
  }
}

locals {
  service_state_exporter_service_name = "openclaw-service-state-exporter.service"
  service_state_exporter_timer_name   = "openclaw-service-state-exporter.timer"

  service_state_exporter_package_files = {
    for file_name in sort(tolist(setunion(
      fileset("${path.module}/../monitoring", "*.py"),
      fileset("${path.module}/../monitoring", "requirements.txt"),
    ))) :
    "monitoring/${file_name}" => base64encode(file("${path.module}/../monitoring/${file_name}"))
  }

  service_state_exporter_systemd_unit = templatefile("${path.module}/../systemd/openclaw-service-state-exporter.service.tftpl", {
    service_state_exporter_live_writes_enabled = var.service_state_exporter_live_writes_enabled
    metric_prefix                              = var.service_state_exporter_metric_prefix
    project_id                                 = var.project_id
    service_state_exporter_group               = var.service_state_exporter_group
    service_state_exporter_user                = var.service_state_exporter_user
    service_state_exporter_working_directory   = var.service_state_exporter_working_directory
  })

  service_state_exporter_systemd_timer = templatefile("${path.module}/../systemd/openclaw-service-state-exporter.timer.tftpl", {
    randomized_delay_seconds = var.service_state_exporter_randomized_delay_seconds
    schedule                 = var.service_state_exporter_schedule
  })
}

# Bootstrap install wiring is intentionally gated by service_state_exporter_enabled.
# Defaults keep the exporter absent from live hosts until explicitly approved.

check "service_state_exporter_live_writes_require_exporter" {
  assert {
    condition     = !var.service_state_exporter_live_writes_enabled || var.service_state_exporter_enabled
    error_message = "service_state_exporter_enabled must be true before enabling service-state exporter live writes."
  }
}
