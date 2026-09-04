variable "project_id" {
  description = "GCP project ID. It has no default to prevent an accidental deployment."
  type        = string
}

variable "region" {
  description = "Region for the first SRE control-plane MVP deployment."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Bounded environment name used in resource names and labels."
  type        = string
  default     = "staging"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.environment)) && length(var.environment) <= 20
    error_message = "environment must be an RFC1035-compatible name no longer than 20 characters."
  }
}

variable "name_prefix" {
  description = "RFC1035-compatible resource prefix."
  type        = string
  default     = "sre-control-plane"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name_prefix)) && length(var.name_prefix) <= 30
    error_message = "name_prefix must be an RFC1035-compatible name no longer than 30 characters."
  }
}

variable "container_image" {
  description = "Immutable Artifact Registry image URI pinned to a sha256 digest."
  type        = string
  default     = null

  validation {
    condition     = var.container_image == null || can(regex("^[a-z0-9-]+-docker\\.pkg\\.dev/.+@sha256:[0-9a-fA-F]{64}$", var.container_image))
    error_message = "container_image must be null or an Artifact Registry URI pinned by an immutable @sha256 digest."
  }
}

variable "deployment_phase" {
  description = "bootstrap creates prerequisites only; runtime creates Cloud Run, migration job, and paused scheduler."
  type        = string
  default     = "bootstrap"

  validation {
    condition     = contains(["bootstrap", "runtime"], var.deployment_phase)
    error_message = "deployment_phase must be bootstrap or runtime."
  }
}

variable "database_secret_version" {
  description = "Explicit existing Secret Manager version for DATABASE_URL. The value is a version number, never the secret value."
  type        = string
  default     = null

  validation {
    condition     = var.database_secret_version == null || can(regex("^[1-9][0-9]*$", var.database_secret_version))
    error_message = "database_secret_version must be a positive numeric Secret Manager version."
  }
}

variable "scheduler_enabled" {
  description = "Keep the scheduler paused until migration and authenticated readiness verification have succeeded."
  type        = bool
  default     = false
}

variable "scheduler_activation_confirmed" {
  description = "Explicit reviewed acknowledgement that migration and authenticated readiness verification succeeded before scheduler activation."
  type        = bool
  default     = false
}

variable "cloud_sql_tier" {
  description = "Cloud SQL machine tier for the bounded MVP."
  type        = string
  default     = "db-custom-1-3840"
}

variable "cloud_sql_database_name" {
  description = "Control-plane database name."
  type        = string
  default     = "sre_control_plane"
}

variable "cloud_sql_database_version" {
  description = "PostgreSQL version for the durable workflow database."
  type        = string
  default     = "POSTGRES_16"
}

variable "cloud_sql_disk_size_gb" {
  description = "Initial durable Cloud SQL storage allocation in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.cloud_sql_disk_size_gb >= 20
    error_message = "cloud_sql_disk_size_gb must be at least 20."
  }
}

variable "evidence_retention_days" {
  description = "Minimum retention for sanitized evidence artifacts."
  type        = number
  default     = 30

  validation {
    condition     = var.evidence_retention_days >= 30
    error_message = "evidence_retention_days must be at least 30."
  }
}

variable "log_retention_days" {
  description = "Retention for the dedicated structured-log bucket."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30
    error_message = "log_retention_days must be at least 30."
  }
}

variable "service_max_instances" {
  description = "Maximum Cloud Run instances. Correctness still depends on the database lease and fencing token."
  type        = number
  default     = 1

  validation {
    condition     = var.service_max_instances == 1
    error_message = "The first MVP must keep service_max_instances at 1."
  }
}

variable "service_concurrency" {
  description = "Maximum concurrent HTTP requests per Cloud Run instance."
  type        = number
  default     = 10

  validation {
    condition     = var.service_concurrency >= 1 && var.service_concurrency <= 20
    error_message = "service_concurrency must be between 1 and 20."
  }
}

variable "service_timeout_seconds" {
  description = "Bounded Cloud Run request timeout for API and scheduler tick calls."
  type        = number
  default     = 60

  validation {
    condition     = var.service_timeout_seconds >= 10 && var.service_timeout_seconds <= 300
    error_message = "service_timeout_seconds must be between 10 and 300."
  }
}

variable "scheduler_schedule" {
  description = "Cron schedule for the short reconciliation and dispatch tick."
  type        = string
  default     = "*/5 * * * *"
}

variable "scheduler_time_zone" {
  description = "IANA time zone used by Cloud Scheduler."
  type        = string
  default     = "Etc/UTC"
}

variable "scheduler_lease_owner" {
  description = "Stable lease-owner identity sent by the authenticated scheduler tick."
  type        = string
  default     = "cloud-scheduler"
}

variable "github_publisher_mode" {
  description = "Publisher selection. Fake is default; github requires explicit allowlist and Secret Manager credential reference."
  type        = string
  default     = "fake"

  validation {
    condition     = contains(["fake", "github"], var.github_publisher_mode)
    error_message = "github_publisher_mode must be fake or github."
  }
}

variable "github_publication_repository" {
  description = "Explicit GitHub repository publication target. Required only when github_publisher_mode is github."
  type        = string
  default     = null

  validation {
    condition     = var.github_publication_repository == null || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_publication_repository))
    error_message = "github_publication_repository must be null or an owner/repository name."
  }
}

variable "github_publication_issue_number" {
  description = "Explicit GitHub issue publication target. Required only when github_publisher_mode is github."
  type        = number
  default     = null

  validation {
    condition = (
      var.github_publication_issue_number == null
      || (
        var.github_publication_issue_number >= 1
        && floor(var.github_publication_issue_number) == var.github_publication_issue_number
      )
    )
    error_message = "github_publication_issue_number must be null or a positive integer issue number."
  }
}

variable "github_publication_allowed_repository" {
  description = "Allowlisted GitHub repository for publication. Must exactly match the target when github_publisher_mode is github."
  type        = string
  default     = null

  validation {
    condition     = var.github_publication_allowed_repository == null || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_publication_allowed_repository))
    error_message = "github_publication_allowed_repository must be null or an owner/repository name."
  }
}

variable "github_publication_allowed_issue_number" {
  description = "Allowlisted GitHub issue for publication. Must exactly match the target when github_publisher_mode is github."
  type        = number
  default     = null

  validation {
    condition = (
      var.github_publication_allowed_issue_number == null
      || (
        var.github_publication_allowed_issue_number >= 1
        && floor(var.github_publication_allowed_issue_number) == var.github_publication_allowed_issue_number
      )
    )
    error_message = "github_publication_allowed_issue_number must be null or a positive integer issue number."
  }
}

variable "github_publication_credential_secret_version" {
  description = "Explicit existing Secret Manager version for the GitHub publisher credential. The value is a version number, never the secret value."
  type        = string
  default     = null

  validation {
    condition     = var.github_publication_credential_secret_version == null || can(regex("^[1-9][0-9]*$", var.github_publication_credential_secret_version))
    error_message = "github_publication_credential_secret_version must be null or a positive numeric Secret Manager version."
  }
}

variable "executor_mode" {
  description = "Executor selection. Fake is default; sre_replay is the bounded fixture-backed read-only SRE adapter."
  type        = string
  default     = "fake"

  validation {
    condition     = contains(["fake", "sre_replay"], var.executor_mode)
    error_message = "executor_mode must be fake or sre_replay."
  }
}

variable "deletion_protection" {
  description = "Keep data-bearing resources protected until an explicit reviewed teardown."
  type        = bool
  default     = true

  validation {
    condition     = var.deletion_protection
    error_message = "deletion_protection must remain true for the first MVP foundation."
  }
}

variable "alert_notification_channel_ids" {
  description = "Existing Cloud Monitoring notification channel IDs. Empty leaves alerts un-routed until a reviewed channel is supplied."
  type        = list(string)
  default     = []
}
