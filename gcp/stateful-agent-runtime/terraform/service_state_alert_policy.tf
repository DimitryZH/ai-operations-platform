variable "service_state_alert_policy_create" {
  description = "Create the disabled-by-default Cloud Monitoring alert policy for service-state metrics."
  type        = bool
  default     = false
}

variable "service_state_alert_policy_enabled" {
  description = "Enable the service-state alert policy when it is explicitly created."
  type        = bool
  default     = false
}

variable "service_state_alert_policy_display_name" {
  description = "Optional display name for the service-state alert policy."
  type        = string
  default     = ""

  validation {
    condition     = var.service_state_alert_policy_display_name == "" || trimspace(var.service_state_alert_policy_display_name) != ""
    error_message = "service_state_alert_policy_display_name must be empty or non-blank."
  }
}

variable "service_state_alert_alignment_period" {
  description = "Alignment period for service-state alert policy conditions."
  type        = string
  default     = "300s"

  validation {
    condition     = can(regex("^[1-9][0-9]*s$", var.service_state_alert_alignment_period))
    error_message = "service_state_alert_alignment_period must be a positive duration in seconds, for example 300s."
  }
}

variable "service_state_alert_duration" {
  description = "Duration that service-state metrics must remain below threshold before alerting."
  type        = string
  default     = "300s"

  validation {
    condition     = can(regex("^[1-9][0-9]*s$", var.service_state_alert_duration))
    error_message = "service_state_alert_duration must be a positive duration in seconds, for example 300s."
  }
}

variable "service_state_alert_threshold" {
  description = "Threshold below which an approved service-state metric is considered unhealthy."
  type        = number
  default     = 1

  validation {
    condition     = var.service_state_alert_threshold > 0 && var.service_state_alert_threshold <= 1
    error_message = "service_state_alert_threshold must be greater than 0 and no more than 1."
  }
}

locals {
  service_state_alert_policy_display_name = (
    trimspace(var.service_state_alert_policy_display_name) != ""
    ? var.service_state_alert_policy_display_name
    : "${local.monitoring_alert_display_name_prefix} service-state unhealthy"
  )

  service_state_alert_policy_approved_services = [
    "openclaw.service",
  ]

  service_state_alert_policy_service_filter_values = join(",", [
    for service in local.service_state_alert_policy_approved_services : "\"${service}\""
  ])

  service_state_alert_policy_metric_types = {
    active    = "${var.service_state_exporter_metric_prefix}/active"
    available = "${var.service_state_exporter_metric_prefix}/available"
    healthy   = "${var.service_state_exporter_metric_prefix}/healthy"
    running   = "${var.service_state_exporter_metric_prefix}/running"
  }
}

resource "google_monitoring_alert_policy" "service_state" {
  count = var.service_state_alert_policy_create ? 1 : 0

  display_name          = local.service_state_alert_policy_display_name
  combiner              = "OR"
  enabled               = var.service_state_alert_policy_enabled
  notification_channels = []

  dynamic "conditions" {
    for_each = local.service_state_alert_policy_metric_types

    content {
      display_name = "${local.service_state_alert_policy_display_name} ${conditions.key}"

      condition_threshold {
        filter = "resource.type = \"global\" AND metric.type = \"${conditions.value}\" AND metric.label.service = one_of(${local.service_state_alert_policy_service_filter_values})"

        comparison      = "COMPARISON_LT"
        duration        = var.service_state_alert_duration
        threshold_value = var.service_state_alert_threshold

        aggregations {
          alignment_period   = var.service_state_alert_alignment_period
          per_series_aligner = "ALIGN_MEAN"
        }

        trigger {
          count = 1
        }
      }
    }
  }

  documentation {
    content   = "Service-state custom metrics must remain at or above 1 for approved OpenClaw services. Notification routing is intentionally not configured by this skeleton."
    mime_type = "text/markdown"
  }

  user_labels = {
    component = "stateful-agent-runtime"
    signal    = "service-state"
  }
}

check "service_state_alert_policy_enabled_requires_create" {
  assert {
    condition     = !var.service_state_alert_policy_enabled || var.service_state_alert_policy_create
    error_message = "service_state_alert_policy_create must be true before enabling the service-state alert policy."
  }
}

check "service_state_alert_policy_metric_prefix" {
  assert {
    condition     = startswith(var.service_state_exporter_metric_prefix, "custom.googleapis.com/")
    error_message = "service_state_exporter_metric_prefix must start with custom.googleapis.com/ for service-state alert policies."
  }
}

check "service_state_alert_policy_has_approved_services" {
  assert {
    condition     = length(local.service_state_alert_policy_approved_services) > 0
    error_message = "service-state alert policy approved service labels must not be empty."
  }
}
