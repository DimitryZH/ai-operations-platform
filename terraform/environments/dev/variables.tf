variable "project_id" {
  description = "GCP project ID where resources will be created."
  type        = string
}

variable "region" {
  description = "GCP region for Artifact Registry and Cloud Run."
  type        = string
  default     = "us-central1"
}

variable "labels" {
  description = "Optional labels applied to supported resources."
  type        = map(string)
  default     = {}
}

variable "artifact_repository_id" {
  description = "Artifact Registry Docker repository ID."
  type        = string
  default     = "ai-agent-runtime"
}

variable "runtime_service_account_id" {
  description = "Account ID for the dedicated Cloud Run runtime service account."
  type        = string
  default     = "cloudrun-runtime"
}

variable "runtime_secret_id" {
  description = "Secret Manager secret ID for runtime/provider configuration."
  type        = string
  default     = "ai-runtime-config"
}

variable "runtime_secret_placeholder" {
  description = "Non-sensitive placeholder value for the runtime config secret."
  type        = string
  default     = "{\"status\":\"placeholder\",\"note\":\"replace via CI/CD or manual secret rotation\"}"
}

variable "cloud_run_service_name" {
  description = "Cloud Run service name."
  type        = string
  default     = "ai-agent-runtime"
}

variable "cloud_run_container_image" {
  description = "Container image URI used by Cloud Run. Replace with your Artifact Registry image in later stages."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "cloud_run_ingress" {
  description = "Ingress policy for Cloud Run."
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
}

variable "cloud_run_timeout_seconds" {
  description = "Cloud Run request timeout in seconds."
  type        = number
  default     = 300
}

variable "cloud_run_cpu" {
  description = "CPU limit for the Cloud Run container."
  type        = string
  default     = "1"
}

variable "cloud_run_memory" {
  description = "Memory limit for the Cloud Run container."
  type        = string
  default     = "512Mi"
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances."
  type        = number
  default     = 0
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances."
  type        = number
  default     = 3
}

variable "cloud_run_deletion_protection" {
  description = "Enable deletion protection for Cloud Run service."
  type        = bool
  default     = false
}

variable "allow_unauthenticated" {
  description = "DEV-ONLY option to grant public unauthenticated invoker access to Cloud Run."
  type        = bool
  default     = false
}
