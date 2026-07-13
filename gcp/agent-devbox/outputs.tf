output "vm_name" {
  description = "Agent DevBox VM name."
  value       = google_compute_instance.devbox.name
}

output "vm_zone" {
  description = "Agent DevBox VM zone."
  value       = google_compute_instance.devbox.zone
}

output "internal_ip" {
  description = "Private internal VM IP address."
  value       = google_compute_instance.devbox.network_interface[0].network_ip
}

output "service_account_email" {
  description = "Dedicated VM service account email."
  value       = google_service_account.devbox.email
}

output "network_name" {
  description = "Dedicated VPC name."
  value       = google_compute_network.devbox.name
}

output "subnet_name" {
  description = "Dedicated subnet name."
  value       = google_compute_subnetwork.devbox.name
}

output "iap_ssh_command" {
  description = "Template command for SSH through IAP."
  value       = "gcloud compute ssh ${google_compute_instance.devbox.name} --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap"
}

output "iap_tunnel_command_template" {
  description = "Template for a future private UI tunnel through IAP. Replace PORT when a later task approves a UI."
  value       = "gcloud compute start-iap-tunnel ${google_compute_instance.devbox.name} PORT --project=${var.project_id} --zone=${var.zone} --local-host-port=127.0.0.1:PORT"
}

output "readiness_validation_command" {
  description = "Template command to run base readiness validation after SSH."
  value       = "sudo /opt/devclaw/bin/validate-tools.sh && sudo /opt/devclaw/bin/validate-runtime.sh"
}
