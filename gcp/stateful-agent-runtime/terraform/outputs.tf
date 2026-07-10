output "runtime_service_account_email" {
  description = "Dedicated OpenClaw VM runtime service account."
  value       = google_service_account.openclaw.email
}

output "instance_group_manager_name" {
  description = "Zonal stateful Managed Instance Group name."
  value       = google_compute_instance_group_manager.openclaw.name
}

output "instance_group_self_link" {
  description = "Managed instance group self-link."
  value       = google_compute_instance_group_manager.openclaw.instance_group
}

output "state_disk_name" {
  description = "Authoritative OpenClaw state disk name."
  value       = google_compute_disk.openclaw_state.name
}

output "snapshot_policy_name" {
  description = "Daily state disk snapshot policy name."
  value       = google_compute_resource_policy.daily_state_snapshot_standard.name
}

output "iap_ssh_command" {
  description = "Template command for SSH through IAP. Replace INSTANCE_NAME with the current managed instance name."
  value       = "gcloud compute ssh INSTANCE_NAME --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap"
}

output "iap_gateway_tunnel_command" {
  description = "Template command for a private OpenClaw Control UI tunnel through IAP."
  value       = "gcloud compute start-iap-tunnel INSTANCE_NAME ${var.openclaw_port} --project=${var.project_id} --zone=${var.zone} --local-host-port=127.0.0.1:18080"
}

output "required_apis_not_managed" {
  description = "APIs required before apply. This Terraform root intentionally does not enable them."
  value = [
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}
