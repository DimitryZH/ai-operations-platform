variable "project_id" {
  description = "GCP project ID for the disposable Agent DevBox."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the VM."
  type        = string
  default     = "us-central1-a"
}

variable "name_prefix" {
  description = "RFC1035-compatible resource name prefix."
  type        = string
  default     = "agent-devbox"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name_prefix)) && length(var.name_prefix) <= 30
    error_message = "name_prefix must be RFC1035-compatible and no longer than 30 characters."
  }
}

variable "network_name" {
  description = "Dedicated VPC name."
  type        = string
  default     = "agent-devbox-vpc"
}

variable "subnet_name" {
  description = "Dedicated regional subnet name."
  type        = string
  default     = "agent-devbox-subnet"
}

variable "subnet_cidr" {
  description = "CIDR block for the private subnet."
  type        = string
  default     = "10.52.0.0/24"
}

variable "machine_type" {
  description = "Compute Engine machine type for the disposable experiment VM."
  type        = string
  default     = "e2-standard-2"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB. The first skeleton uses the boot disk for workspace and runtime state."
  type        = number
  default     = 80

  validation {
    condition     = var.boot_disk_size_gb >= 80
    error_message = "boot_disk_size_gb must be at least 80 GB for Docker, NuGet, and Aspire caches."
  }
}

variable "boot_disk_type" {
  description = "Boot disk type."
  type        = string
  default     = "pd-balanced"
}

variable "source_image_project" {
  description = "Image project for the Ubuntu base image."
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "source_image_family" {
  description = "Ubuntu 24.04 LTS amd64 image family."
  type        = string
  default     = "ubuntu-2404-lts-amd64"
}

variable "service_account_id" {
  description = "Account ID for the dedicated VM service account."
  type        = string
  default     = "agent-devbox-vm"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.service_account_id)) && length(var.service_account_id) <= 30
    error_message = "service_account_id must be RFC1035-compatible and no longer than 30 characters."
  }
}

variable "labels" {
  description = "Additional labels applied to supported resources."
  type        = map(string)
  default     = {}
}

variable "operator_iam_members" {
  description = "IAM members allowed to use IAP TCP forwarding and standard OS Login. Empty by default."
  type        = set(string)
  default     = []
}

variable "admin_iam_members" {
  description = "IAM members allowed to use IAP TCP forwarding and OS Admin Login. Empty by default."
  type        = set(string)
  default     = []
}

variable "secret_project_id" {
  description = "Project containing existing Secret Manager secrets. Null uses project_id."
  type        = string
  default     = null
}

variable "secret_manager_secret_refs" {
  description = "Existing Secret Manager secret names or resource IDs for future runtime secret references. Values are identifiers only, never payloads."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for secret_ref in var.secret_manager_secret_refs :
      can(regex("^[a-zA-Z0-9_-]+$", secret_ref)) || can(regex("^projects/[a-z][a-z0-9-]*/secrets/[a-zA-Z0-9_-]+$", secret_ref))
    ])
    error_message = "Secrets must be simple secret IDs or resource IDs like projects/example-project/secrets/example-secret."
  }
}

variable "artifact_registry_reader_enabled" {
  description = "Grant Artifact Registry reader on an existing repository. Disabled by default."
  type        = bool
  default     = false
}

variable "artifact_registry_project_id" {
  description = "Project containing the optional existing Artifact Registry repository."
  type        = string
  default     = null
}

variable "artifact_registry_location" {
  description = "Location of the optional existing Artifact Registry repository."
  type        = string
  default     = null
}

variable "artifact_registry_repository_id" {
  description = "Optional existing Artifact Registry repository ID."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Enable VM deletion protection. Disabled by default for a disposable experiment."
  type        = bool
  default     = false
}

variable "dotnet_sdk_channel" {
  description = ".NET SDK channel installed by the base startup script."
  type        = string
  default     = "10.0"
}

variable "nodejs_major_version" {
  description = "Node.js major version compatible with future DevClaw installation."
  type        = number
  default     = 22

  validation {
    condition     = var.nodejs_major_version >= 22
    error_message = "nodejs_major_version must be at least 22."
  }
}

variable "observability_iam_enabled" {
  description = "Grant logging and monitoring writer roles. This does not install or configure the Ops Agent."
  type        = bool
  default     = false
}

variable "enable_secure_boot" {
  description = "Enable Shielded VM Secure Boot."
  type        = bool
  default     = true
}
