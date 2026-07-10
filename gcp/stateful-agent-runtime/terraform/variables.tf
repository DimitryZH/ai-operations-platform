variable "project_id" {
  description = "GCP project ID where the stateful OpenClaw runtime resources will be created."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the zonal stateful MIG and Persistent Disk."
  type        = string
  default     = "us-central1-a"
}

variable "name_prefix" {
  description = "RFC1035-compatible prefix used for the stateful OpenClaw runtime resources."
  type        = string
  default     = "openclaw-stateful"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name_prefix)) && length(var.name_prefix) <= 30
    error_message = "name_prefix must be an RFC1035-compatible name no longer than 30 characters."
  }
}

variable "labels" {
  description = "Additional labels applied to supported resources."
  type        = map(string)
  default     = {}
}

variable "machine_type" {
  description = "Compute Engine machine type. Validate e2-small under realistic OpenClaw load before deployment."
  type        = string
  default     = "e2-small"
}

variable "ubuntu_image_project" {
  description = "Google Cloud image project for Ubuntu images."
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "ubuntu_image_family" {
  description = "Ubuntu 24.04 LTS image family."
  type        = string
  default     = "ubuntu-2404-lts-amd64"
}

variable "ubuntu_image_name" {
  description = "Optional exact Ubuntu image name for controlled rollouts that must avoid image-family drift. Null keeps ubuntu_image_family behavior."
  type        = string
  default     = null

  validation {
    condition     = var.ubuntu_image_name == null || can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.ubuntu_image_name))
    error_message = "ubuntu_image_name must be null or an RFC1035-compatible image name."
  }
}

variable "boot_disk_size_gb" {
  description = "Recreatable boot disk size in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.boot_disk_size_gb >= 20
    error_message = "boot_disk_size_gb must be at least 20 GB."
  }
}

variable "boot_disk_type" {
  description = "Recreatable boot disk type."
  type        = string
  default     = "pd-balanced"
}

variable "data_disk_size_gb" {
  description = "Authoritative OpenClaw state disk size in GB."
  type        = number
  default     = 30

  validation {
    condition     = var.data_disk_size_gb >= 30
    error_message = "data_disk_size_gb must be at least 30 GB."
  }
}

variable "data_disk_type" {
  description = "Authoritative OpenClaw state disk type."
  type        = string
  default     = "pd-balanced"
}

variable "data_disk_device_name" {
  description = "Stable guest device name for the authoritative OpenClaw state disk."
  type        = string
  default     = "openclaw-state"
}

variable "state_mount_path" {
  description = "Host mount path for authoritative OpenClaw state."
  type        = string
  default     = "/var/lib/openclaw"

  validation {
    condition     = startswith(var.state_mount_path, "/")
    error_message = "state_mount_path must be an absolute path."
  }
}

variable "openclaw_state_dir" {
  description = "Persistent OpenClaw state directory."
  type        = string
  default     = "/var/lib/openclaw/state"
}

variable "openclaw_workspace_dir" {
  description = "Persistent OpenClaw workspace directory."
  type        = string
  default     = "/var/lib/openclaw/workspace"
}

variable "openclaw_runtime_dir" {
  description = "Ephemeral OpenClaw runtime directory."
  type        = string
  default     = "/run/openclaw/runtime"
}

variable "openclaw_uid" {
  description = "OpenClaw container runtime UID expected by the pinned runtime image."
  type        = number
  default     = 10001
}

variable "openclaw_gid" {
  description = "OpenClaw container runtime GID expected by the pinned runtime image."
  type        = number
  default     = 10001
}

variable "openclaw_port" {
  description = "OpenClaw gateway port exposed only to private IAP and health-check paths."
  type        = number
  default     = 8080

  validation {
    condition     = var.openclaw_port > 0 && var.openclaw_port < 65536
    error_message = "openclaw_port must be a valid TCP port."
  }
}

variable "container_image" {
  description = "Immutable Artifact Registry OpenClaw image URI pinned by sha256 digest."
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-fA-F]{64}$", var.container_image))
    error_message = "container_image must be pinned by an immutable @sha256 digest."
  }
}

variable "artifact_registry_project_id" {
  description = "Project containing the existing Artifact Registry repository. Null uses project_id."
  type        = string
  default     = null
}

variable "artifact_registry_location" {
  description = "Location of the existing Artifact Registry repository."
  type        = string
  default     = "us-central1"
}

variable "artifact_registry_repository_id" {
  description = "Existing Artifact Registry repository containing the OpenClaw image."
  type        = string
  default     = "ai-operations-runtime"
}

variable "runtime_service_account_id" {
  description = "Account ID for the dedicated OpenClaw VM runtime service account."
  type        = string
  default     = "openclaw-stateful-vm"
}

variable "secret_project_id" {
  description = "Project containing existing runtime secrets. Null uses project_id."
  type        = string
  default     = null
}

variable "runtime_secret_ids" {
  description = "Map of OpenClaw environment variable names to existing Secret Manager secret IDs. Values are secret identifiers, never secret values."
  type        = map(string)
  default = {
    OPENCLAW_GATEWAY_TOKEN = "openclaw-gateway-token-experimental"
    GEMINI_API_KEY         = "gemini-api-key-experimental"
    GH_TOKEN               = "openclaw-github-readonly-token-experimental"
  }

  validation {
    condition = alltrue([
      for env_name, secret_id in var.runtime_secret_ids :
      can(regex("^[A-Z][A-Z0-9_]*$", env_name)) &&
      can(regex("^[a-zA-Z0-9_-]+$", secret_id))
    ])
    error_message = "runtime_secret_ids must map uppercase environment variable names to Secret Manager secret IDs."
  }
}

variable "github_pr_secret_id" {
  description = "Existing Secret Manager secret ID for the controlled PR token. Required only when openclaw_github_mode is pr."
  type        = string
  default     = null
}

variable "openclaw_github_mode" {
  description = "GitHub capability mode. readonly is the secure default; pr requires explicit approval and a separate secret."
  type        = string
  default     = "readonly"

  validation {
    condition     = contains(["readonly", "pr"], var.openclaw_github_mode)
    error_message = "openclaw_github_mode must be readonly or pr."
  }
}

variable "openclaw_control_ui_enabled" {
  description = "Enable the OpenClaw Control UI. Access remains private through IAP."
  type        = bool
  default     = false
}

variable "openclaw_control_ui_allowed_origins_json" {
  description = "JSON array of explicitly allowed local tunnel origins."
  type        = string
  default     = "[\"http://127.0.0.1:18080\",\"http://localhost:18080\"]"
}

variable "openclaw_admin_http_rpc_enabled" {
  description = "Enable the bundled OpenClaw admin-http-rpc plugin for trusted onboarding/admin RPC over the authenticated gateway."
  type        = bool
  default     = false
}

variable "openclaw_primary_model" {
  description = "Default OpenClaw primary model."
  type        = string
  default     = "google/gemini-2.5-flash"
}

variable "openclaw_google_model_id" {
  description = "Native Google provider model ID."
  type        = string
  default     = "gemini-2.5-flash"
}

variable "openclaw_openai_model_id" {
  description = "OpenAI-compatible Gemini provider model ID retained for compatibility testing."
  type        = string
  default     = "gemini-3.5-flash"
}

variable "create_network" {
  description = "Create a dedicated VPC and subnet. Set false to use reviewed existing network self-links."
  type        = bool
  default     = true
}

variable "network_self_link" {
  description = "Existing VPC self-link when create_network is false."
  type        = string
  default     = null
}

variable "subnetwork_self_link" {
  description = "Existing subnetwork self-link when create_network is false."
  type        = string
  default     = null
}

variable "subnetwork_cidr" {
  description = "CIDR for the dedicated private subnet when create_network is true."
  type        = string
  default     = "10.42.0.0/24"
}

variable "create_cloud_nat" {
  description = "Create Cloud Router and Cloud NAT for private VM outbound access."
  type        = bool
  default     = true
}

variable "operator_iam_members" {
  description = "IAM members allowed to use IAP TCP forwarding and standard OS Login."
  type        = set(string)
  default     = []
}

variable "admin_iam_members" {
  description = "IAM members allowed to use IAP TCP forwarding and OS Admin Login."
  type        = set(string)
  default     = []
}

variable "grant_operator_service_account_user" {
  description = "Grant approved operators iam.serviceAccountUser on the runtime service account only when the OS Login access flow requires it."
  type        = bool
  default     = false
}

variable "health_check_mode" {
  description = "MIG autohealing health check mode. Keep TCP until an application endpoint is validated during burn-in."
  type        = string
  default     = "TCP"

  validation {
    condition     = contains(["TCP", "HTTP"], var.health_check_mode)
    error_message = "health_check_mode must be TCP or HTTP."
  }
}

variable "health_check_request_path" {
  description = "HTTP health check path used only when health_check_mode is HTTP."
  type        = string
  default     = "/readyz"
}

variable "health_check_initial_delay_sec" {
  description = "Conservative MIG autohealing startup grace period."
  type        = number
  default     = 300

  validation {
    condition     = var.health_check_initial_delay_sec >= 300 && var.health_check_initial_delay_sec <= 3600
    error_message = "health_check_initial_delay_sec must be between 300 and 3600 seconds."
  }
}

variable "snapshot_start_time_utc" {
  description = "Daily snapshot start time in an accepted UTC snapshot schedule window."
  type        = string
  default     = "04:00"

  validation {
    condition     = contains(["00:00", "04:00", "08:00", "12:00", "16:00", "20:00"], var.snapshot_start_time_utc)
    error_message = "snapshot_start_time_utc must be one of 00:00, 04:00, 08:00, 12:00, 16:00, or 20:00."
  }
}

variable "snapshot_retention_days" {
  description = "Prototype scheduled snapshot retention in days."
  type        = number
  default     = 14

  validation {
    condition     = var.snapshot_retention_days >= 14
    error_message = "snapshot_retention_days must be at least 14 days."
  }
}

variable "snapshot_storage_locations" {
  description = "Storage locations for scheduled snapshots."
  type        = list(string)
  default     = ["us"]
}

variable "enable_secure_boot" {
  description = "Enable Shielded VM Secure Boot."
  type        = bool
  default     = true
}
